#!/usr/bin/env bash
set -Eeuo pipefail
trap '' HUP
source "$(dirname "$0")/mariadb_common.sh"
RUN_ID=${SHQVEL_RUN_ID:-shqvel-mariadb-24h-$(date +%Y%m%d_%H%M%S)}
HOURS=${1:-24}; EPOCH_SECONDS=${2:-3600}
[[ "$HOURS" =~ ^[1-9][0-9]*$ && "$EPOCH_SECONDS" =~ ^[1-9][0-9]*$ ]] || mariadb_die "positive integer arguments required"
(( HOURS == 1 || EPOCH_SECONDS >= 180 )) || mariadb_die "multi-epoch runs require EPOCH_SECONDS>=180 so coverage publication cannot consume the next epoch"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || mariadb_die "unsafe run ID"
RUN_SECONDS=$((HOURS*EPOCH_SECONDS)); ROOT="$SHQVEL_ROOT/spool/$RUN_ID"; LIVE="$ROOT/live"; RUN_WORK="$ROOT/work"
SQL_DIR="$ROOT/mariadb-general"; REMOTE="$MARIADB_NFS_ROOT/$RUN_ID"; REMOTE_LIVE="$REMOTE/_live"; SQLANCER_LIVE="$REMOTE_LIVE/sqlancer-logs"
SHQVEL_PID=''; CURRENT_SQL_LOG=''; STARTED=0; FINALIZED=0
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' || true)"; [[ -n "$s" && "$s" != Z* && "$s" != X* ]]; }
lifecycle() { printf '%s %s\n' "$(date --iso-8601=ns)" "$*" >> "$LIVE/runner-lifecycle.log"; }
check_space() {
  local local_kb nfs_kb
  findmnt -T "$MARIADB_NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || mariadb_die "MariaDB result root is no longer on NFS"
  local_kb="$(df -Pk "$SHQVEL_ROOT" | awk 'NR==2{print $4}')"
  nfs_kb="$(df -Pk "$MARIADB_NFS_ROOT" | awk 'NR==2{print $4}')"
  (( local_kb >= ${SHQVEL_MIN_FREE_KB:-5000000} )) || mariadb_die "local space low: ${local_kb}KB"
  (( nfs_kb >= ${SHQVEL_NFS_MIN_FREE_KB:-20000000} )) || mariadb_die "NFS space low: ${nfs_kb}KB"
}
start_epoch() { CURRENT_SQL_LOG="$SQL_DIR/epoch-$(printf '%02d' "$1").log"; "$SHQVEL_ROOT/scripts/start_mariadb_cov.sh" "$LIVE/mariadb-error.log" "$CURRENT_SQL_LOG" >> "$LIVE/mariadb-start-stop.log" 2>&1; mariadb_verify_running > "$LIVE/mariadb-identity-current.txt"; lifecycle "mariadb_started epoch=$1 pid=$(<"$MARIADB_PID_FILE")"; }
cleanup() {
  rc=$?; trap - EXIT INT TERM
  if (( STARTED && ! FINALIZED && rc != 0 )); then
    [[ -z "$SHQVEL_PID" ]] || { kill -CONT -- "-$SHQVEL_PID" 2>/dev/null || true; kill -INT -- "-$SHQVEL_PID" 2>/dev/null || true; }
    "$SHQVEL_ROOT/scripts/stop_mariadb_cov.sh" >> "$LIVE/mariadb-start-stop.log" 2>&1 || true
    printf '{"run_id":"%s","failed_at":"%s","exit":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$rc" > "$LIVE/FAILED"
    [[ ! -d "$REMOTE" ]] || rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/" || true
  fi
  exit "$rc"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
mariadb_assert_managed_paths; "$SHQVEL_ROOT/scripts/preflight_mariadb_cov.sh"; mountpoint -q /app/nfs/chq_data || mariadb_die "NFS unavailable"
check_space; [[ ! -e "$ROOT" && ! -e "$REMOTE" ]] || mariadb_die "run ID exists"; "$SHQVEL_ROOT/scripts/prepare_mariadb_coverage_template.sh"
mkdir -p "$LIVE" "$RUN_WORK" "$SQL_DIR" "$REMOTE_LIVE" "$SQLANCER_LIVE"; ln -s "$SHQVEL_WORK/src" "$RUN_WORK/src"; ln -s "$SHQVEL_WORK/dbconfigs" "$RUN_WORK/dbconfigs"; ln -s "$SQLANCER_LIVE" "$RUN_WORK/logs"
STARTED=1; find "$MARIADB_BUILD" -type f -name '*.gcda' -delete; start_epoch 1
# Match SQLancer's PostgreSQL 5-second statement guard and keep pathological
# generated BENCHMARK expressions from stalling a 24-hour MariaDB run.
export SQLANCER_MARIADB_URL='jdbc:mariadb://{host}:{port}/{database}?user={user}&password={password}&sessionVariables=max_statement_time=5' SQLANCER_MARIADB_HOST=127.0.0.1 SQLANCER_MARIADB_PORT="$MARIADB_PORT" SQLANCER_MARIADB_USER="$MARIADB_USER" SQLANCER_MARIADB_PASSWORD="$MARIADB_PASSWORD" SQLANCER_MARIADB_DATABASE=test
export SHQVEL_PYTHON_LLM_EVENT_LOG="$LIVE/python-llm-events.jsonl" SHQVEL_JAVA_LLM_EVENT_LOG="$LIVE/java-llm-events.jsonl" JAVA_TOOL_OPTIONS='-Xms2g -Xmx8g -XX:+UseG1GC'
server_sha="$(sha256sum "$MARIADB_BIN/mariadbd" | awk '{print $1}')"; jar_sha="$(sha256sum "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" | awk '{print $1}')"
printf '{"run_id":"%s","started_at":"%s","epochs":%s,"epoch_seconds":%s,"mode":"online-learning-and-fuzzing","dbms":"MariaDB 12.2.2","port":%s,"server_sha256":"%s","jar_sha256":"%s","coverage":"cumulative-hourly-graceful-restart","max_statement_time_seconds":5,"threads":1}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$HOURS" "$EPOCH_SECONDS" "$MARIADB_PORT" "$server_sha" "$jar_sha" > "$LIVE/run-manifest.json"
source /usr/local/miniconda3/etc/profile.d/conda.sh; conda activate shqvel; cd "$RUN_WORK"
setsid --wait timeout --signal=INT --kill-after=60 "$RUN_SECONDS" java -jar "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" --enable-extra-features --enable-learning --num-threads 1 --num-tries 2147483647 --num-queries 100000 --log-each-select true --log-execution-time true general --database-engine mariadb --documentation-yaml "$SHQVEL_WORK/dbconfigs/mariadb-url-12.2.yml" --configured-datatypes-only true --enable-function-overview-learning false --enable-statement-learning false --enable-datatype-learning true --enable-expression-learning true --enable-clause-learning false --enable-direct-validation true --learning-interval-seconds 60 --oracle FUZZING --save-learned-fragments "$LIVE/learned-fragments.json" > "$LIVE/shqvel.stdout.log" 2>&1 &
SHQVEL_PID=$!; BEGIN="$(date +%s)"; lifecycle "shqvel_started pid=$SHQVEL_PID"
for ((n=1;n<=HOURS;n++)); do
  deadline=$((BEGIN+n*EPOCH_SECONDS)); while alive "$SHQVEL_PID" && (( $(date +%s)<deadline )); do mariadb_ping >/dev/null 2>&1 || mariadb_die "MariaDB authenticated SQL health check failed"; remain=$((deadline-$(date +%s))); step=30; ((remain<step))&&step=$remain; ((step>0))&&sleep "$step"; done
  epoch="epoch-$(printf '%02d' "$n")"; dir="$ROOT/$epoch"; frozen="$ROOT/coverage-input"; mkdir -p "$dir"/{sql,runtime,learning,coverage}
  boundary="$(date --iso-8601=ns)"; ns="$(date +%s%N)"; paused=false; if alive "$SHQVEL_PID"; then kill -STOP -- "-$SHQVEL_PID"; paused=true; fi
  "$SHQVEL_ROOT/scripts/stop_mariadb_cov.sh" >> "$LIVE/mariadb-start-stop.log" 2>&1; mv "$CURRENT_SQL_LOG" "$dir/sql/mariadb-general.log"; "$SHQVEL_ROOT/scripts/freeze_mariadb_coverage.sh" "$frozen"
  python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$MARIADB_STATE/$RUN_ID-runtime-offsets.json" --output "$dir/runtime"; python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$MARIADB_STATE/$RUN_ID-sqlancer-offsets.json" --output "$dir/runtime/sqlancer"
  [[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$dir/learning/"; [[ ! -d "$SQLANCER_LIVE/general/learner" ]] || cp -a "$SQLANCER_LIVE/general/learner" "$dir/learning/"
  start_epoch "$((n+1))"; [[ "$paused" == false ]] || kill -CONT -- "-$SHQVEL_PID"; downtime=$((($(date +%s%N)-ns)/1000000)); lifecycle "epoch_released epoch=$n downtime_ms=$downtime"
  gzip -9 "$dir/sql/mariadb-general.log"; python3 "$SHQVEL_ROOT/scripts/extract_mysql_general_log.py" --input "$dir/sql/mariadb-general.log.gz" --output "$dir/sql/replay.sql.gz" --summary "$dir/sql/mysql-general-summary.json"
  "$SHQVEL_ROOT/scripts/collect_mariadb_coverage.sh" "$frozen" "$dir/coverage"; find "$frozen" -xdev -depth -delete; python3 "$SHQVEL_ROOT/scripts/analyze_mysql_epoch.py" --epoch "$dir"
  printf 'run_id=%s\nepoch=%s\nboundary=%s\ndowntime_ms=%s\nserver_sha256=%s\n' "$RUN_ID" "$n" "$boundary" "$downtime" "$server_sha" > "$dir/epoch-manifest.txt"; (cd "$dir" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
  "$SHQVEL_ROOT/scripts/upload_mariadb_epoch.sh" "$RUN_ID" "$epoch" "$dir"; find "$dir" -xdev -depth -delete; lifecycle "epoch_complete epoch=$n"; alive "$SHQVEL_PID" || break; check_space
done
set +e; wait "$SHQVEL_PID"; shqvel_rc=$?; set -e; elapsed=$(($(date +%s)-BEGIN)); [[ "$shqvel_rc" -eq 124 ]] || mariadb_die "unexpected ShQveL exit: $shqvel_rc"
"$SHQVEL_ROOT/scripts/stop_mariadb_cov.sh" >> "$LIVE/mariadb-start-stop.log" 2>&1
final="$ROOT/final-artifacts"; mkdir -p "$final"/{runtime,coverage,sql}; [[ ! -f "$CURRENT_SQL_LOG" ]] || { gzip -9 -c "$CURRENT_SQL_LOG" > "$final/sql/mariadb-general.log.gz"; python3 "$SHQVEL_ROOT/scripts/extract_mysql_general_log.py" --input "$final/sql/mariadb-general.log.gz" --output "$final/sql/replay.sql.gz" --summary "$final/sql/mysql-general-summary.json"; }
python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$MARIADB_STATE/$RUN_ID-runtime-offsets.json" --output "$final/runtime"; python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$MARIADB_STATE/$RUN_ID-sqlancer-offsets.json" --output "$final/runtime/sqlancer"; "$SHQVEL_ROOT/scripts/collect_mariadb_coverage.sh" "$final/coverage"
[[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$final/"; printf '{"run_id":"%s","completed_at":"%s","elapsed_seconds":%s,"shqvel_exit":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$elapsed" "$shqvel_rc" > "$final/run-result.json"
(cd "$final" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256); "$SHQVEL_ROOT/scripts/upload_mariadb_epoch.sh" "$RUN_ID" final-artifacts "$final"; find "$final" -xdev -depth -delete
lifecycle run_complete; rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/"; printf '{"run_id":"%s","completed":true,"epochs":%s,"elapsed_seconds":%s}\n' "$RUN_ID" "$HOURS" "$elapsed" > "$REMOTE/run-result.json"; date --iso-8601=seconds > "$REMOTE/COMPLETE"; FINALIZED=1
