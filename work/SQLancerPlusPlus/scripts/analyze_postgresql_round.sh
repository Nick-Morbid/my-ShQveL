#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
input_log=${1:-"$repo_dir/logs/postgresql-focused/one-round.typescript"}
manifest=${2:-"$repo_dir/logs/postgresql-focused/one-round-features.tsv"}
results=${3:-"$repo_dir/logs/postgresql-focused/one-round-composed-results.tsv"}

tmp_manifest=$(mktemp)
trap 'rm -f "$tmp_manifest"' EXIT

# Stop at the first scheduler refresh, so a partially-started second round is excluded.
awk '
  { sub(/\r$/, "") }
  /All topics are learned\. Refresh/ { exit }
  /Updating fragments from learner for type / {
    topic=$0
    sub(/^.*type /, "", topic)
    next
  }
  /^Fragment .* is (supported|invalid)$/ {
    verdict=($0 ~ / is supported$/ ? "supported" : "invalid")
    line=$0
    sub(/^Fragment /, "", line)
    sub(/ is (supported|invalid)$/, "", line)
    if (line ~ /^DATATYPE-/) category="DATATYPE"
    else if (line ~ /^FUNCTION-/) category="FUNCTION"
    else if (line ~ /^OPERATOR-/) category="OPERATOR"
    else category="OTHER"
    feature=line
    prefix=category "-" topic "-"
    candidate=line
    if (category == "DATATYPE" && index(candidate, prefix) == 1) {
      candidate=substr(candidate, length(prefix) + 1)
    } else if (category == "FUNCTION") {
      candidate=line
      sub(/^FUNCTION-[0-9]+-/, "", candidate)
    } else if (category == "OPERATOR") {
      candidate=line
      sub(/^OPERATOR-[^-]+-/, "", candidate)
    }
    pending=1
    next
  }
  pending && (/^SELECT / || /^INSERT INTO TEST_FEATURE VALUES /) {
    sql=$0
    gsub(/\t/, " ", sql)
    gsub(/\t/, " ", candidate)
    print topic "\t" category "\t" verdict "\t" candidate "\t" sql
    pending=0
  }
' "$input_log" > "$tmp_manifest"

{
  printf 'topic\tcategory\tverdict\tcandidate\toriginal_validation_sql\n'
  cat "$tmp_manifest"
} > "$manifest"

declare -A representative
while IFS=$'\t' read -r topic category verdict candidate original_sql; do
  if [[ $category == DATATYPE && $verdict == supported && -z ${representative[$topic]+x} ]]; then
    representative[$topic]=$candidate
  fi
done < "$tmp_manifest"

# Optional coverage-only fallback. INTEGER produced only unresolved placeholders
# (RANDOM_INT/RANDOM_POSITIVE_INT), so it has no accepted learned literal.
if [[ ${ALLOW_CANONICAL_INTEGER:-false} == true && -z ${representative[INTEGER]+x} ]]; then
  representative[INTEGER]=0
fi

printf 'topic\tcategory\tcandidate\trepresentative_value\tcomposed_sql\tresult\tdetail\n' > "$results"

while IFS=$'\t' read -r topic category verdict candidate original_sql; do
  [[ $verdict == supported ]] || continue
  [[ $category == FUNCTION || $category == OPERATOR ]] || continue
  value=${representative[$topic]:-}
  if [[ -z $value ]]; then
    printf '%s\t%s\t%s\t\t%s\tSKIP\tno representative datatype value\n' \
      "$topic" "$category" "$candidate" "$original_sql" >> "$results"
    continue
  fi
  operand="CAST(($value) AS $topic)"
  composed_sql=${original_sql//NULL/$operand}
  detail=$(PGPASSWORD=shqvel-postgres PGOPTIONS='-c statement_timeout=5000' \
    psql -X -qAt -h 127.0.0.1 -p 5433 -U postgres -d shqvel \
    -v ON_ERROR_STOP=1 -c "$composed_sql" 2>&1) && result=PASS || result=FAIL
  detail=${detail//$'\n'/ | }
  detail=${detail//$'\t'/ }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$topic" "$category" "$candidate" "$value" "$composed_sql" "$result" "$detail" >> "$results"
done < "$tmp_manifest"

printf 'Wrote %s and %s\n' "$manifest" "$results"
