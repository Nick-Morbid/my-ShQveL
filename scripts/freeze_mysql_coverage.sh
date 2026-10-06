#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"
[[ $# -eq 1 ]] || mysql_die "usage: $0 SNAPSHOT_DIR"

snapshot="$(readlink -m "$1")"
[[ "$snapshot" == "$SHQVEL_ROOT"/spool/*/coverage-input ]] || \
  mysql_die "coverage snapshot must be a run-local coverage-input directory"
[[ ! -e "$snapshot" ]] || mysql_die "coverage snapshot already exists: $snapshot"
mysql_require_file "$MYSQL_COVERAGE_TEMPLATE/manifest.txt"
# The static 1 GiB gcno template is cloned with hard links. Only the small,
# mutable gcda counter set is copied from the just-stopped server lifetime.
cp -al "$MYSQL_COVERAGE_TEMPLATE" "$snapshot"
(cd "$MYSQL_BUILD" && find . -type f -name '*.gcda' -print0 | tar --null -T - -cf -) | \
  (cd "$snapshot" && tar -xf -)

gcno_count="$(find "$snapshot" -type f -name '*.gcno' | wc -l)"
gcda_count="$(find "$snapshot" -type f -name '*.gcda' | wc -l)"
(( gcno_count > 1000 && gcda_count > 0 )) || \
  mysql_die "incomplete frozen coverage input: gcno=$gcno_count gcda=$gcda_count"
printf 'gcno_count=%s\ngcda_count=%s\nfrozen_at=%s\n' \
  "$gcno_count" "$gcda_count" "$(date --iso-8601=ns)" > "$snapshot/manifest.txt"
