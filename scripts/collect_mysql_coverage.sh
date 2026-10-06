#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"
[[ $# -eq 2 ]] || mysql_die "usage: $0 FROZEN_INPUT OUTPUT_DIR"

input="$(readlink -m "$1")"
out="$(readlink -m "$2")"
mysql_require_dir "$input"
mysql_require_file "$input/manifest.txt"
mkdir -p "$out"
started="$(date --iso-8601=ns)"
start_ns="$(date +%s%N)"

capture_ok=false
for attempt in 1 2 3; do
  printf 'capture_attempt=%s\n' "$attempt" >> "$out/collect.log"
  shards="$out/.coverage-shards"
  traces="$out/.coverage-traces"
  find "$shards" "$traces" -xdev -depth -delete 2>/dev/null || true
  mkdir -p "$shards" "$traces"
  python3 "$SHQVEL_ROOT/scripts/shard_mysql_coverage.py" --input "$input" --output "$shards" --shards 8
  pids=()
  for shard in "$shards"/shard-*; do
    name="$(basename "$shard")"
    lcov --capture --directory "$shard" --output-file "$traces/$name.info" \
      --rc lcov_branch_coverage=1 > "$traces/$name.log" 2>&1 &
    pids+=("$!")
  done
  parallel_ok=true
  for pid in "${pids[@]}"; do wait "$pid" || parallel_ok=false; done
  if rg -q 'negative counts found' "$traces"/*.log; then
    printf 'ERROR: gcov reported negative counters; the MySQL build is not safe for multithreaded coverage\n' >> "$out/collect.log"
    parallel_ok=false
  fi
  merge_args=()
  for trace in "$traces"/*.info; do merge_args+=(--add-tracefile "$trace"); done
  if [[ "$parallel_ok" == true ]] && lcov "${merge_args[@]}" --output-file "$out/raw-full.info" \
      --rc lcov_branch_coverage=1 >> "$out/collect.log" 2>&1; then
    capture_ok=true
    for log in "$traces"/*.log; do printf '\n[%s]\n' "$(basename "$log")" >> "$out/collect.log"; cat "$log" >> "$out/collect.log"; done
    break
  fi
  sleep 2
done
find "$shards" "$traces" -xdev -depth -delete 2>/dev/null || true
[[ "$capture_ok" == true ]] || mysql_die "MySQL lcov capture failed after 3 attempts"
grep -q '^SF:' "$out/raw-full.info" || mysql_die "full MySQL trace has no source records"
lcov --extract "$out/raw-full.info" "$MYSQL_SOURCE/sql/*" "$MYSQL_SOURCE/storage/*" "$MYSQL_SOURCE/include/*" \
  --output-file "$out/raw.info" --rc lcov_branch_coverage=1 >> "$out/collect.log" 2>&1
grep -Eq '^SF:.*/(sql|storage|include)/' "$out/raw.info" || mysql_die "core MySQL trace has no expected source records"
lcov --summary "$out/raw.info" --rc lcov_branch_coverage=1 > "$out/summary.txt"
gzip -c "$out/raw-full.info" > "$out/raw-full.info.gz"
gzip -c "$out/raw.info" > "$out/raw.info.gz"
gzip -t "$out/raw-full.info.gz" "$out/raw.info.gz"
end_ns="$(date +%s%N)"
printf '{"started_at":"%s","completed_at":"%s","elapsed_seconds":%s}\n' \
  "$started" "$(date --iso-8601=ns)" "$(( (end_ns-start_ns)/1000000000 ))" > "$out/timing.json"
cp "$input/manifest.txt" "$out/coverage-input-manifest.txt"
