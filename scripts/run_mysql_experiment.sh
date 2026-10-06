#!/usr/bin/env bash
set -Eeuo pipefail
trap '' HUP
source "$(dirname "$0")/mysql_common.sh"

RUN_ID=${SHQVEL_RUN_ID:-shqvel-mysql-24h-$(date +%Y%m%d_%H%M%S)}
HOURS=${1:-24}
EPOCH_SECONDS=${2:-3600}
[[ "$HOURS" =~ ^[1-9][0-9]*$ && "$EPOCH_SECONDS" =~ ^[1-9][0-9]*$ ]] || mysql_die "hours and epoch seconds must be positive integers"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ && "$RUN_ID" != . && "$RUN_ID" != .. ]] || mysql_die "unsafe run ID"

RUN_SECONDS=$((HOURS * EPOCH_SECONDS))
RUN_ROOT="$SHQVEL_ROOT/spool/$RUN_ID"
LIVE="$RUN_ROOT/live"
RUN_WORK="$RUN_ROOT/work"
SQL_DIR="$RUN_ROOT/mysql-general"
REMOTE="$MYSQL_NFS_ROOT/$RUN_ID"
REMOTE_LIVE="$REMOTE/_live"
SQLANCER_LIVE="$REMOTE_LIVE/sqlancer-logs"
MIN_LOCAL_KB=${SHQVEL_MIN_FREE_KB:-5000000}
MIN_NFS_KB=${SHQVEL_NFS_MIN_FREE_KB:-20000000}
SHQVEL_PID=""
MYSQL_PID=""
RUN_STARTED=0
RUN_FINALIZED=0
CURRENT_SQL_LOG=""

proc_state() { ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' || true; }
process_alive() { local state; state="$(proc_state "$1")"; [[ -n "$state" && "$state" != Z* && "$state" != X* ]]; }
lifecycle() { printf '%s %s\n' "$(date --iso-8601=ns)" "$*" >> "$LIVE/runner-lifecycle.log"; }
check_space() {
  local local_kb nfs_kb
  local_kb="$(df -Pk "$SHQVEL_ROOT" | awk 'NR==2 {print $4}')"
  nfs_kb="$(df -Pk "$MYSQL_NFS_ROOT" | awk 'NR==2 {print $4}')"
  (( local_kb >= MIN_LOCAL_KB )) || mysql_die "local free space too low: ${local_kb}KB < ${MIN_LOCAL_KB}KB"
  (( nfs_kb >= MIN_NFS_KB )) || mysql_die "NFS free space too low: ${nfs_kb}KB < ${MIN_NFS_KB}KB"
}
start_epoch_mysql() {
  local epoch_no="$1"
  CURRENT_SQL_LOG="$SQL_DIR/epoch-$(printf '%02d' "$epoch_no").log"
  "$SHQVEL_ROOT/scripts/start_mysql_cov.sh" "$LIVE/mysql-error.log" "$CURRENT_SQL_LOG" >> "$LIVE/mysql-start-stop.log" 2>&1
  MYSQL_PID="$(<"$MYSQL_DATA/mysqld.pid")"
  mysql_verify_running > "$LIVE/mysql-identity-current.txt"
  lifecycle "mysql_started epoch=$epoch_no pid=$MYSQL_PID general_log=$CURRENT_SQL_LOG"
}
pause_shqvel() {
  process_alive "$SHQVEL_PID" || return 1
  kill -STOP -- "-$SHQVEL_PID"
  lifecycle "shqvel_paused pid=$SHQVEL_PID"
}
resume_shqvel() {
  process_alive "$SHQVEL_PID" || return 0
  kill -CONT -- "-$SHQVEL_PID"
  lifecycle "shqvel_resumed pid=$SHQVEL_PID"
}
on_exit() {
  local rc=$?
  trap - EXIT INT TERM
  if (( RUN_STARTED == 1 )); then lifecycle "exit_trap rc=$rc finalized=$RUN_FINALIZED"; resume_shqvel || true; fi
  if (( rc != 0 && RUN_FINALIZED == 0 && RUN_STARTED == 1 )); then
    if [[ -n "$SHQVEL_PID" ]] && process_alive "$SHQVEL_PID"; then
      kill -INT -- "-$SHQVEL_PID" 2>/dev/null || true
      for _ in {1..30}; do process_alive "$SHQVEL_PID" || break; sleep 1; done
      process_alive "$SHQVEL_PID" && kill -KILL -- "-$SHQVEL_PID" 2>/dev/null || true
    fi
    "$SHQVEL_ROOT/scripts/stop_mysql_cov.sh" >> "$LIVE/mysql-start-stop.log" 2>&1 || true
    printf '{"run_id":"%s","failed_at":"%s","harness_exit":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$rc" > "$LIVE/FAILED"
    if mountpoint -q /app/nfs/chq_data && [[ -d "$REMOTE" ]]; then
      cp "$LIVE/FAILED" "$REMOTE/FAILED" 2>/dev/null || true
      rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/" 2>/dev/null || true
    fi
  fi
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mysql_assert_managed_paths
"$SHQVEL_ROOT/scripts/preflight_mysql_cov.sh" --require-probe
mountpoint -q /app/nfs/chq_data || mysql_die "Synology NFS is unavailable"
findmnt -T "$MYSQL_NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || mysql_die "MySQL result root is not on NFS"
check_space
mysql_port_is_free || mysql_die "managed MySQL port $MYSQL_PORT is occupied"
[[ ! -e "$MYSQL_DATA/mysqld.pid" ]] || mysql_die "managed MySQL PID file already exists"
[[ ! -e "$RUN_ROOT" && ! -e "$REMOTE" ]] || mysql_die "run ID already exists: $RUN_ID"
"$SHQVEL_ROOT/scripts/prepare_mysql_coverage_template.sh"

mkdir -p "$LIVE" "$RUN_WORK" "$SQL_DIR" "$REMOTE_LIVE" "$SQLANCER_LIVE"
ln -s "$SHQVEL_WORK/src" "$RUN_WORK/src"
ln -s "$SHQVEL_WORK/dbconfigs" "$RUN_WORK/dbconfigs"
ln -s "$SQLANCER_LIVE" "$RUN_WORK/logs"
RUN_STARTED=1
lifecycle "run_preparation_started"
find "$MYSQL_BUILD" -type f -name '*.gcda' -delete
start_epoch_mysql 1

export SQLANCER_MYSQL_HOST=127.0.0.1 SQLANCER_MYSQL_PORT="$MYSQL_PORT"
export SQLANCER_MYSQL_USER="$MYSQL_USER" SQLANCER_MYSQL_PASSWORD="$MYSQL_PASSWORD" SQLANCER_MYSQL_DATABASE=test
export SHQVEL_PYTHON_LLM_EVENT_LOG="$LIVE/python-llm-events.jsonl"
export SHQVEL_JAVA_LLM_EVENT_LOG="$LIVE/java-llm-events.jsonl"
export JAVA_TOOL_OPTIONS="-Xms2g -Xmx8g -XX:+UseG1GC"
jar_sha="$(sha256sum "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" | awk '{print $1}')"
mysql_sha="$(sha256sum "$MYSQL_BIN/mysqld" | awk '{print $1}')"
printf '{"run_id":"%s","started_at":"%s","hours":%s,"epoch_seconds":%s,"mode":"online-learning-and-fuzzing","mysql_version":"8.4.8","mysql_port":%s,"mysql_data":"%s","mysql_sha256":"%s","sqlancer_jar_sha256":"%s","coverage":"cumulative-hourly-via-controlled-graceful-restart","threads":1}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$HOURS" "$EPOCH_SECONDS" "$MYSQL_PORT" "$MYSQL_DATA" "$mysql_sha" "$jar_sha" > "$LIVE/run-manifest.json"

source /usr/local/miniconda3/etc/profile.d/conda.sh
conda activate shqvel
cd "$RUN_WORK"
setsid --wait timeout --signal=INT --kill-after=60 "$RUN_SECONDS" java -jar "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 2147483647 --num-queries 100000 \
  --log-each-select true --log-execution-time true general --database-engine mysql \
  --documentation-yaml "$SHQVEL_WORK/dbconfigs/mysql-url-8.4.yml" --configured-datatypes-only true \
  --enable-function-overview-learning false --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false --enable-direct-validation true \
  --learning-interval-seconds 60 --oracle FUZZING --save-learned-fragments "$LIVE/learned-fragments.json" \
  > "$LIVE/shqvel.stdout.log" 2>&1 &
SHQVEL_PID=$!
printf '%s\n' "$SHQVEL_PID" > "$MYSQL_STATE/$RUN_ID.pid"
RUN_START="$(date +%s)"
lifecycle "shqvel_started pid=$SHQVEL_PID"

for ((epoch_no=1; epoch_no<=HOURS; epoch_no++)); do
  deadline=$((RUN_START + epoch_no * EPOCH_SECONDS))
  while process_alive "$SHQVEL_PID" && (( $(date +%s) < deadline )); do
    mysql_admin ping >/dev/null 2>&1 || { lifecycle "mysql_healthcheck_failed epoch=$epoch_no"; mysql_die "managed MySQL became unavailable"; }
    remaining=$((deadline - $(date +%s))); step=30; (( remaining < step )) && step=$remaining
    (( step > 0 )) && sleep "$step"
  done
  check_space
  epoch_name="epoch-$(printf '%02d' "$epoch_no")"
  epoch_dir="$RUN_ROOT/$epoch_name"
  frozen="$RUN_ROOT/coverage-input"
  mkdir -p "$epoch_dir/sql" "$epoch_dir/runtime" "$epoch_dir/learning" "$epoch_dir/coverage"
  boundary_started="$(date --iso-8601=ns)"; boundary_ns="$(date +%s%N)"

  paused=false; if pause_shqvel; then paused=true; fi
  "$SHQVEL_ROOT/scripts/stop_mysql_cov.sh" >> "$LIVE/mysql-start-stop.log" 2>&1
  lifecycle "mysql_stopped epoch=$epoch_no pid=$MYSQL_PID"
  [[ -f "$CURRENT_SQL_LOG" ]] || mysql_die "missing MySQL general log for $epoch_name"
  mv "$CURRENT_SQL_LOG" "$epoch_dir/sql/mysql-general.log"
  "$SHQVEL_ROOT/scripts/freeze_mysql_coverage.sh" "$frozen"
  python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$MYSQL_STATE/$RUN_ID-runtime-offsets.json" --output "$epoch_dir/runtime"
  python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$MYSQL_STATE/$RUN_ID-sqlancer-offsets.json" --output "$epoch_dir/runtime/sqlancer"
  [[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$epoch_dir/learning/"
  [[ ! -d "$SQLANCER_LIVE/general/learner" ]] || cp -a "$SQLANCER_LIVE/general/learner" "$epoch_dir/learning/"

  start_epoch_mysql "$((epoch_no + 1))"
  [[ "$paused" == false ]] || resume_shqvel
  boundary_elapsed=$(( ($(date +%s%N) - boundary_ns) / 1000000 ))
  lifecycle "epoch_boundary_released epoch=$epoch_no downtime_ms=$boundary_elapsed"
  gzip -9 "$epoch_dir/sql/mysql-general.log"
  python3 "$SHQVEL_ROOT/scripts/extract_mysql_general_log.py" \
    --input "$epoch_dir/sql/mysql-general.log.gz" \
    --output "$epoch_dir/sql/replay.sql.gz" \
    --summary "$epoch_dir/sql/mysql-general-summary.json"
  "$SHQVEL_ROOT/scripts/collect_mysql_coverage.sh" "$frozen" "$epoch_dir/coverage"
  find "$frozen" -xdev -depth -delete
  python3 "$SHQVEL_ROOT/scripts/analyze_mysql_epoch.py" --epoch "$epoch_dir"
  printf 'run_id=%s\nepoch=%s\nboundary_started_at=%s\ncaptured_at=%s\nboundary_downtime_ms=%s\nmysql_sha256=%s\n' "$RUN_ID" "$epoch_no" "$boundary_started" "$(date --iso-8601=seconds)" "$boundary_elapsed" "$mysql_sha" > "$epoch_dir/epoch-manifest.txt"
  (cd "$epoch_dir" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
  "$SHQVEL_ROOT/scripts/upload_mysql_epoch.sh" "$RUN_ID" "$epoch_name" "$epoch_dir"
  find "$epoch_dir" -xdev -depth -delete
  lifecycle "epoch_complete epoch=$epoch_no"
  process_alive "$SHQVEL_PID" || break
done

set +e; wait "$SHQVEL_PID"; SHQVEL_EXIT=$?; set -e
ACTUAL_SECONDS=$(( $(date +%s) - RUN_START ))
lifecycle "shqvel_wait_complete exit=$SHQVEL_EXIT actual_seconds=$ACTUAL_SECONDS"
printf '%s\n' "$SHQVEL_EXIT" > "$LIVE/shqvel-exit-status.txt"
[[ "$SHQVEL_EXIT" -eq 124 ]] || mysql_die "ShQveL did not complete its scheduled timeout: exit=$SHQVEL_EXIT"

"$SHQVEL_ROOT/scripts/stop_mysql_cov.sh" >> "$LIVE/mysql-start-stop.log" 2>&1
final_input="$RUN_ROOT/coverage-input"
"$SHQVEL_ROOT/scripts/freeze_mysql_coverage.sh" "$final_input"
final_dir="$RUN_ROOT/final-artifacts"
mkdir -p "$final_dir/runtime" "$final_dir/coverage" "$final_dir/sql"
if [[ -f "$CURRENT_SQL_LOG" ]]; then
  gzip -9 -c "$CURRENT_SQL_LOG" > "$final_dir/sql/mysql-general.log.gz"
  python3 "$SHQVEL_ROOT/scripts/extract_mysql_general_log.py" \
    --input "$final_dir/sql/mysql-general.log.gz" \
    --output "$final_dir/sql/replay.sql.gz" \
    --summary "$final_dir/sql/mysql-general-summary.json"
fi
python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$MYSQL_STATE/$RUN_ID-runtime-offsets.json" --output "$final_dir/runtime"
python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$MYSQL_STATE/$RUN_ID-sqlancer-offsets.json" --output "$final_dir/runtime/sqlancer"
[[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$final_dir/"
"$SHQVEL_ROOT/scripts/collect_mysql_coverage.sh" "$final_input" "$final_dir/coverage"
find "$final_input" -xdev -depth -delete
printf '{"run_id":"%s","completed_at":"%s","harness_wall_seconds":%s,"scheduled_fuzz_seconds":%s,"shqvel_exit_status":%s,"completed_scheduled_timeout":true}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$ACTUAL_SECONDS" "$RUN_SECONDS" "$SHQVEL_EXIT" > "$final_dir/run-result.json"
(cd "$final_dir" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
"$SHQVEL_ROOT/scripts/upload_mysql_epoch.sh" "$RUN_ID" final-artifacts "$final_dir"
find "$final_dir" -xdev -depth -delete
rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/"
printf '{"run_id":"%s","completed_at":"%s","harness_wall_seconds":%s,"scheduled_fuzz_seconds":%s,"shqvel_exit_status":%s,"completed_scheduled_timeout":true,"epochs":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$ACTUAL_SECONDS" "$RUN_SECONDS" "$SHQVEL_EXIT" "$HOURS" > "$REMOTE/run-result.json"
date --iso-8601=seconds > "$REMOTE/COMPLETE"
mv "$MYSQL_STATE/$RUN_ID.pid" "$MYSQL_STATE/$RUN_ID.pid.completed"
RUN_FINALIZED=1
lifecycle "run_complete"
printf 'run_id=%s status=%s actual_seconds=%s\n' "$RUN_ID" "$SHQVEL_EXIT" "$ACTUAL_SECONDS"
