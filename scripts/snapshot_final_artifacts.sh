#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -eq 3 ]] || die "usage: $0 RUN_ID WORK_REPO LIVE_DIR"
RUN_ID="$1"
WORK_REPO="$(readlink -m "$2")"
LIVE_DIR="$(readlink -m "$3")"
NAME="final-artifacts"
OUT="$SPOOL_DIR/$RUN_ID/$NAME"
[[ ! -e "$OUT/COMPLETE" ]] || die "local final artifacts already complete: $OUT"
mkdir -p "$OUT/sql" "$OUT/runtime" "$OUT/postgres" "$OUT/llm" "$OUT/learning"

# ShQveL has exited. Rotate once more so all of its last JDBC records are in
# immutable CSV files. The newly active file contains only harness traffic.
psql_cov -Atc "SELECT pg_rotate_logfile();" >/dev/null
sleep 1
ACTIVE_LOG="$(basename "$(psql_cov -Atc "SELECT pg_current_logfile('csvlog');")")"

python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$WORK_REPO/logs/postgresql" \
  --state "$STATE_DIR/$RUN_ID-sql-offsets.json" --output "$OUT/sql"
python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$LIVE_DIR" \
  --state "$STATE_DIR/$RUN_ID-runtime-offsets.json" --output "$OUT/runtime"
python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$LOCAL_ROOT/postgres/logs" \
  --state "$STATE_DIR/$RUN_ID-postgres-offsets.json" --output "$OUT/postgres" \
  --exclude "$ACTIVE_LOG"

for event_file in "$LIVE_DIR"/*.jsonl; do
  [[ -f "$event_file" ]] || continue
  cp "$event_file" "$OUT/llm/$(basename "$event_file")"
done
for checkpoint in "$LIVE_DIR"/*.json; do
  [[ -f "$checkpoint" ]] || continue
  cp "$checkpoint" "$OUT/learning/$(basename "$checkpoint")"
done
if [[ -d "$WORK_REPO/logs/postgresql/learner" ]]; then
  cp -a "$WORK_REPO/logs/postgresql/learner" "$OUT/learning/"
fi

python3 "$HARNESS_ROOT/scripts/analyze_epoch.py" --epoch "$OUT"
{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'captured_at=%s\n' "$(date --iso-8601=seconds)"
  "$HARNESS_ROOT/scripts/verify_target.sh"
} > "$OUT/final-manifest.txt"
(cd "$OUT" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
date --iso-8601=seconds > "$OUT/COMPLETE"
"$HARNESS_ROOT/scripts/upload_epoch.sh" "$RUN_ID" "$NAME" "$OUT"
