#!/usr/bin/env bash
set -Eeuo pipefail
trap '' HUP
source "$(dirname "$0")/tidb_common.sh"
RUN_ID=${SHQVEL_RUN_ID:-shqvel-tidb-24h-$(date +%Y%m%d_%H%M%S)}
EPOCHS=${1:-24}; EPOCH_SECONDS=${2:-3600}
[[ "$EPOCHS" =~ ^[1-9][0-9]*$ && "$EPOCH_SECONDS" =~ ^[1-9][0-9]*$ ]] || tidb_die "positive integer arguments required"
[[ "$RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]] || tidb_die "unsafe run ID"
RUN_SECONDS=$((EPOCHS*EPOCH_SECONDS)); ROOT="$SHQVEL_ROOT/spool/$RUN_ID"; LIVE="$ROOT/live"; RUN_WORK="$ROOT/work"
SERVER_LOGS="$ROOT/tidb-server"; REMOTE="$TIDB_NFS_ROOT/$RUN_ID"; REMOTE_LIVE="$REMOTE/_live"; SQLANCER_LIVE="$REMOTE_LIVE/sqlancer-logs"
SHQVEL_PID=''; CURRENT_SERVER_DIR=''; STARTED=0; FINALIZED=0
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' || true)"; [[ -n "$s" && "$s" != Z* && "$s" != X* ]]; }
lifecycle() { printf '%s %s\n' "$(date --iso-8601=ns)" "$*" >> "$LIVE/runner-lifecycle.log"; }
check_space() {
  local local_kb nfs_kb
  findmnt -T "$TIDB_NFS_ROOT" -n -o FSTYPE | grep -q '^nfs' || tidb_die "TiDB result root is no longer on NFS"
  local_kb="$(df -Pk "$SHQVEL_ROOT" | awk 'NR==2{print $4}')"; nfs_kb="$(df -Pk "$TIDB_NFS_ROOT" | awk 'NR==2{print $4}')"
  (( local_kb >= ${SHQVEL_MIN_FREE_KB:-10000000} )) || tidb_die "local space low: ${local_kb}KB"
  (( nfs_kb >= ${SHQVEL_NFS_MIN_FREE_KB:-20000000} )) || tidb_die "NFS space low: ${nfs_kb}KB"
}
start_epoch() {
  CURRENT_SERVER_DIR="$SERVER_LOGS/epoch-$(printf '%02d' "$1")"; mkdir -p "$CURRENT_SERVER_DIR"
  "$SHQVEL_ROOT/scripts/start_tidb_cov.sh" "$CURRENT_SERVER_DIR/tidb.log" >> "$LIVE/tidb-start-stop.log" 2>&1
  tidb_verify_running > "$LIVE/tidb-identity-current.txt"; lifecycle "tidb_started epoch=$1 pid=$(<"$TIDB_PID_FILE")"
}
cleanup() {
  rc=$?; trap - EXIT INT TERM
  if (( STARTED && ! FINALIZED && rc != 0 )); then
    [[ -z "$SHQVEL_PID" ]] || { kill -CONT -- "-$SHQVEL_PID" 2>/dev/null || true; kill -INT -- "-$SHQVEL_PID" 2>/dev/null || true; }
    "$SHQVEL_ROOT/scripts/stop_tidb_cov.sh" >> "$LIVE/tidb-start-stop.log" 2>&1 || true
    printf '{"run_id":"%s","failed_at":"%s","exit":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$rc" > "$LIVE/FAILED"
    [[ ! -d "$REMOTE" ]] || rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/" || true
  fi
  exit "$rc"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
tidb_assert_managed_paths; tidb_assert_no_active_mariadb_experiment; "$SHQVEL_ROOT/scripts/preflight_tidb_cov.sh"; mountpoint -q /app/nfs/chq_data || tidb_die "NFS unavailable"
mkdir -p "$TIDB_NFS_ROOT"; check_space
[[ ! -e "$ROOT" && ! -e "$REMOTE" ]] || tidb_die "run ID exists"; mkdir -p "$LIVE" "$RUN_WORK" "$SERVER_LOGS" "$REMOTE_LIVE" "$SQLANCER_LIVE"
ln -s "$SHQVEL_WORK/src" "$RUN_WORK/src"; ln -s "$SHQVEL_WORK/dbconfigs" "$RUN_WORK/dbconfigs"; ln -s "$SQLANCER_LIVE" "$RUN_WORK/logs"
STARTED=1; "$SHQVEL_ROOT/scripts/reset_tidb_coverage.sh"; start_epoch 1
export SQLANCER_TIDB_URL='jdbc:mysql://{host}:{port}/{database}?user={user}&password={password}&useSSL=false&allowPublicKeyRetrieval=true' SQLANCER_TIDB_HOST=127.0.0.1 SQLANCER_TIDB_PORT="$TIDB_PORT" SQLANCER_TIDB_USER="$TIDB_USER" SQLANCER_TIDB_PASSWORD="$TIDB_PASSWORD" SQLANCER_TIDB_DATABASE=test
export SHQVEL_PYTHON_LLM_EVENT_LOG="$LIVE/python-llm-events.jsonl" SHQVEL_JAVA_LLM_EVENT_LOG="$LIVE/java-llm-events.jsonl" JAVA_TOOL_OPTIONS='-Xms2g -Xmx8g -XX:+UseG1GC'
server_sha="$(sha256sum "$TIDB_BIN" | awk '{print $1}')"; jar_sha="$(sha256sum "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" | awk '{print $1}')"
printf '{"run_id":"%s","started_at":"%s","epochs":%s,"epoch_seconds":%s,"mode":"online-learning-and-fuzzing","dbms":"TiDB v8.5.5","sql_port":%s,"status_port":%s,"server_sha256":"%s","jar_sha256":"%s","coverage":"cumulative-hourly-go-covdata-via-sigterm-graceful-shutdown","threads":1}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$EPOCHS" "$EPOCH_SECONDS" "$TIDB_PORT" "$TIDB_STATUS_PORT" "$server_sha" "$jar_sha" > "$LIVE/run-manifest.json"
source /usr/local/miniconda3/etc/profile.d/conda.sh; conda activate shqvel; cd "$RUN_WORK"
setsid --wait timeout --signal=INT --kill-after=60 "$RUN_SECONDS" java -jar "$SHQVEL_WORK/target/sqlancer-2.0.0.jar" --enable-extra-features --enable-learning --num-threads 1 --num-tries 2147483647 --num-queries 100000 --log-each-select true --log-execution-time true general --database-engine tidb --documentation-yaml "$SHQVEL_WORK/dbconfigs/tidb-url-8.5.yml" --configured-datatypes-only true --enable-function-overview-learning false --enable-statement-learning false --enable-datatype-learning true --enable-expression-learning true --enable-clause-learning false --enable-direct-validation true --learning-interval-seconds 60 --oracle FUZZING --save-learned-fragments "$LIVE/learned-fragments.json" > "$LIVE/shqvel.stdout.log" 2>&1 &
SHQVEL_PID=$!; BEGIN="$(date +%s)"; lifecycle "shqvel_started pid=$SHQVEL_PID"
for ((n=1;n<=EPOCHS;n++)); do
  deadline=$((BEGIN+n*EPOCH_SECONDS)); while alive "$SHQVEL_PID" && (( $(date +%s)<deadline )); do tidb_ping >/dev/null 2>&1 || tidb_die "TiDB authenticated SQL health check failed"; remain=$((deadline-$(date +%s))); step=30; ((remain<step))&&step=$remain; ((step>0))&&sleep "$step"; done
  # At the final boundary, let timeout finish Java before stopping the DB. This
  # avoids a short interval in which a resumed fuzzer would see no server.
  if (( n == EPOCHS )); then
    for _ in {1..90}; do
      alive "$SHQVEL_PID" || break
      tidb_ping >/dev/null 2>&1 || tidb_die "TiDB failed while awaiting final ShQveL shutdown"
      sleep 1
    done
    alive "$SHQVEL_PID" && tidb_die "ShQveL did not stop after its configured timeout"
  fi
  epoch="epoch-$(printf '%02d' "$n")"; dir="$ROOT/$epoch"; frozen="$ROOT/coverage-input"; mkdir -p "$dir"/{server,runtime,learning,coverage}
  boundary="$(date --iso-8601=ns)"; ns="$(date +%s%N)"; paused=false; if alive "$SHQVEL_PID"; then kill -STOP -- "-$SHQVEL_PID"; paused=true; fi
  "$SHQVEL_ROOT/scripts/stop_tidb_cov.sh" >> "$LIVE/tidb-start-stop.log" 2>&1; mv "$CURRENT_SERVER_DIR" "$dir/server/raw"; "$SHQVEL_ROOT/scripts/freeze_tidb_coverage.sh" "$frozen"
  python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$TIDB_STATE/$RUN_ID-runtime-offsets.json" --output "$dir/runtime"; python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$TIDB_STATE/$RUN_ID-sqlancer-offsets.json" --output "$dir/runtime/sqlancer"
  [[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$dir/learning/"; [[ ! -d "$SQLANCER_LIVE/general/learner" ]] || cp -a "$SQLANCER_LIVE/general/learner" "$dir/learning/"
  if (( n < EPOCHS )) && alive "$SHQVEL_PID"; then
    start_epoch "$((n+1))"
  fi
  [[ "$paused" == false ]] || kill -CONT -- "-$SHQVEL_PID"
  downtime=$((($(date +%s%N)-ns)/1000000)); lifecycle "epoch_released epoch=$n downtime_ms=$downtime"
  tar -C "$dir/server/raw" -czf "$dir/server/tidb-server-raw.tar.gz" .; find "$dir/server/raw" -xdev -depth -delete
  "$SHQVEL_ROOT/scripts/collect_tidb_coverage.sh" "$frozen" "$dir/coverage"; find "$frozen" -xdev -depth -delete; python3 "$SHQVEL_ROOT/scripts/analyze_mysql_epoch.py" --epoch "$dir"
  printf 'run_id=%s\nepoch=%s\nboundary=%s\ndowntime_ms=%s\nserver_sha256=%s\n' "$RUN_ID" "$n" "$boundary" "$downtime" "$server_sha" > "$dir/epoch-manifest.txt"; (cd "$dir" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
  "$SHQVEL_ROOT/scripts/upload_tidb_epoch.sh" "$RUN_ID" "$epoch" "$dir"; find "$dir" -xdev -depth -delete; lifecycle "epoch_complete epoch=$n"; alive "$SHQVEL_PID" || break; check_space
done
set +e; wait "$SHQVEL_PID"; shqvel_rc=$?; set -e; elapsed=$(($(date +%s)-BEGIN)); [[ "$shqvel_rc" -eq 124 ]] || tidb_die "unexpected ShQveL exit: $shqvel_rc"
"$SHQVEL_ROOT/scripts/stop_tidb_cov.sh" >> "$LIVE/tidb-start-stop.log" 2>&1; final_input="$ROOT/coverage-input"; "$SHQVEL_ROOT/scripts/freeze_tidb_coverage.sh" "$final_input"
final="$ROOT/final-artifacts"; mkdir -p "$final"/{runtime,coverage,server}; [[ ! -d "$CURRENT_SERVER_DIR" ]] || { tar -C "$CURRENT_SERVER_DIR" -czf "$final/server/tidb-server-raw.tar.gz" .; }
python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$LIVE" --state "$TIDB_STATE/$RUN_ID-runtime-offsets.json" --output "$final/runtime"; python3 "$SHQVEL_ROOT/scripts/snapshot_sql_logs.py" --source "$SQLANCER_LIVE" --state "$TIDB_STATE/$RUN_ID-sqlancer-offsets.json" --output "$final/runtime/sqlancer"; "$SHQVEL_ROOT/scripts/collect_tidb_coverage.sh" "$final_input" "$final/coverage"
[[ ! -f "$LIVE/learned-fragments.json" ]] || cp "$LIVE/learned-fragments.json" "$final/"; printf '{"run_id":"%s","completed_at":"%s","elapsed_seconds":%s,"shqvel_exit":%s}\n' "$RUN_ID" "$(date --iso-8601=seconds)" "$elapsed" "$shqvel_rc" > "$final/run-result.json"
(cd "$final" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256); "$SHQVEL_ROOT/scripts/upload_tidb_epoch.sh" "$RUN_ID" final-artifacts "$final"; find "$final" -xdev -depth -delete; find "$final_input" -xdev -depth -delete
lifecycle run_complete; rsync -rlt --no-owner --no-group --no-perms "$LIVE/" "$REMOTE_LIVE/harness/"; printf '{"run_id":"%s","completed":true,"epochs":%s,"elapsed_seconds":%s}\n' "$RUN_ID" "$EPOCHS" "$elapsed" > "$REMOTE/run-result.json"; date --iso-8601=seconds > "$REMOTE/COMPLETE"; FINALIZED=1
