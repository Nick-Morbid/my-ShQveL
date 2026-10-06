#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"
run_id=${1:?run ID required}
root=/app/my_ShQveL
pid_file="$root/state/$run_id.pid"
remote="/app/nfs/chq_data/ShQveL/mysql/$run_id/coverage-final"
out="$remote"
build="$root/mysql/source/build"
source_dir="$root/mysql/source"
mountpoint -q /app/nfs/chq_data || { echo '群晖 NFS mount is unavailable; preserving local coverage only' >&2; exit 1; }
mkdir -p "$out" "$remote"
while [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; do
  sleep 30
done
if [[ -s "$MYSQL_DATA/mysqld.pid" ]]; then
  mysql_pid="$(<"$MYSQL_DATA/mysqld.pid")"
  if mysql_pid_running "$mysql_pid"; then
    echo "Harness MySQL PID $mysql_pid is still running; refusing a partial gcov snapshot" >&2
    exit 1
  fi
fi
date --iso-8601=seconds > "$out/capture-started-at.txt"
gcda_count="$(find "$build" -type f -name '*.gcda' | wc -l)"
(( gcda_count > 0 )) || { echo 'no gcda counters found after managed MySQL shutdown' >&2; exit 1; }
lcov --capture --directory "$build" --output-file "$out/raw-full.info" \
  --rc lcov_branch_coverage=1 > "$out/collect.log" 2>&1
[[ -s "$out/raw-full.info" ]] || { echo 'lcov produced an empty full trace' >&2; exit 1; }
grep -q '^SF:' "$out/raw-full.info" || { echo 'lcov full trace has no source records' >&2; exit 1; }
lcov --extract "$out/raw-full.info" "$source_dir/sql/*" "$source_dir/storage/*" "$source_dir/include/*" \
  --output-file "$out/raw.info" --rc lcov_branch_coverage=1 >> "$out/collect.log" 2>&1
[[ -s "$out/raw.info" ]] || { echo 'lcov produced an empty core trace' >&2; exit 1; }
grep -q '^SF:' "$out/raw.info" || { echo 'lcov core trace has no source records' >&2; exit 1; }
lcov --summary "$out/raw.info" --rc lcov_branch_coverage=1 > "$out/summary.txt"
gzip -c "$out/raw-full.info" > "$out/raw-full.info.gz"
gzip -c "$out/raw.info" > "$out/raw.info.gz"
gzip -t "$out/raw-full.info.gz" "$out/raw.info.gz"
printf '{"run_id":"%s","captured_at":"%s","gcda_count":%s,"server_sha256":"%s"}\n' \
  "$run_id" "$(date --iso-8601=seconds)" "$gcda_count" \
  "$(sha256sum "$root/mysql/install/bin/mysqld" | awk '{print $1}')" > "$out/coverage-manifest.json"
(cd "$out" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
(cd "$remote" && sha256sum -c checksums.sha256)
printf '%s\n' "$(date --iso-8601=seconds)" > "$remote/COMPLETE"
