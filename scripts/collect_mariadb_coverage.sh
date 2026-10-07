#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
[[ $# -eq 1 || $# -eq 2 ]] || mariadb_die "usage: $0 [FROZEN_INPUT] OUTPUT_DIR"
if [[ $# -eq 2 ]]; then input="$(readlink -m "$1")"; out="$(readlink -m "$2")"; else input="$MARIADB_BUILD"; out="$(readlink -m "$1")"; fi
mkdir -p "$out"; mariadb_require_dir "$input"
[[ "$input" != "$MARIADB_BUILD" || ! -e "$MARIADB_PID_FILE" ]] || mariadb_die "server must be gracefully stopped before live-tree capture"
gcda="$(find "$input" -type f -name '*.gcda' | wc -l)"; (( gcda > 0 )) || mariadb_die "no gcda files"
lcov --capture --directory "$input" --output-file "$out/raw-full.info" --rc lcov_branch_coverage=1 --ignore-errors source,gcov > "$out/collect.log" 2>&1
if rg -qi 'negative counts found|counter mismatch|version mismatch' "$out/collect.log"; then
  mariadb_die "gcov reported corrupt or incompatible counters; inspect $out/collect.log"
fi
grep -q '^SF:' "$out/raw-full.info" || mariadb_die "full trace has no source records"
lcov --extract "$out/raw-full.info" "$MARIADB_SOURCE/sql/*" "$MARIADB_SOURCE/storage/*" "$MARIADB_SOURCE/include/*" \
  --output-file "$out/raw.info" --rc lcov_branch_coverage=1 >> "$out/collect.log" 2>&1
grep -Eq '^SF:.*/(sql|storage|include)/' "$out/raw.info" || mariadb_die "core trace empty"
lcov --summary "$out/raw.info" --rc lcov_branch_coverage=1 > "$out/summary.txt" 2>&1
gzip -9 -c "$out/raw-full.info" > "$out/raw-full.info.gz"; gzip -9 -c "$out/raw.info" > "$out/raw.info.gz"
printf '{"captured_at":"%s","gcda_count":%s}\n' "$(date --iso-8601=ns)" "$gcda" > "$out/timing.json"
printf 'MARIADB_COVERAGE_CAPTURE_OK gcda=%s\n' "$gcda"
