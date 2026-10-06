#!/usr/bin/env bash
set -Eeuo pipefail
# The experiment is intended to survive terminal/session disconnects.  If the
# invoking shell sends SIGHUP, keep the scheduler and its child process group
# alive so hourly snapshots continue to run.
trap '' HUP
source "$(dirname "$0")/common.sh"

HOURS="${1:-$EXPERIMENT_HOURS}"
EPOCH_LENGTH="${2:-$EPOCH_SECONDS}"
[[ "$HOURS" =~ ^[0-9]+$ && "$HOURS" -gt 0 ]] || die "hours must be a positive integer"
[[ "$EPOCH_LENGTH" =~ ^[0-9]+$ && "$EPOCH_LENGTH" -gt 0 ]] || die "epoch seconds must be positive"
RUN_SECONDS=$((HOURS * EPOCH_LENGTH))
RUN_ID="${SHQVEL_RUN_ID:-$(date +%Y%m%d_%H%M%S)-glm53-flash-online}"
WORK_REPO="$LOCAL_ROOT/work/SQLancerPlusPlus"
LIVE_DIR="$SPOOL_DIR/$RUN_ID/live"
[[ ! -e "$SPOOL_DIR/$RUN_ID" ]] || die "local run id already exists: $RUN_ID"
[[ ! -e "$NFS_ROOT/$RUN_ID" ]] || die "remote run id already exists: $RUN_ID"
mkdir -p "$LIVE_DIR" "$NFS_ROOT/$RUN_ID"
SHQVEL_PID=""
SHQVEL_PGID=""
cleanup_failed_run() {
  local rc=$?
  if (( rc != 0 )); then
    if [[ "$SHQVEL_PGID" =~ ^[0-9]+$ ]] && kill -0 -- "-$SHQVEL_PGID" 2>/dev/null; then
      kill -TERM -- "-$SHQVEL_PGID" 2>/dev/null || true
      for _ in {1..10}; do
        kill -0 -- "-$SHQVEL_PGID" 2>/dev/null || break
        sleep 1
      done
      kill -KILL -- "-$SHQVEL_PGID" 2>/dev/null || true
    fi
    [[ "$SHQVEL_PID" =~ ^[0-9]+$ ]] && wait "$SHQVEL_PID" 2>/dev/null || true
    # A failure during final stopped-server coverage must not leave the
    # dedicated replay target down. Never manages any other PostgreSQL.
    if ! pg_is_running; then
      "$HARNESS_ROOT/scripts/start_postgres_cov.sh" >/dev/null 2>&1 || true
    fi
    printf '{"run_id":"%s","harness_exit":%s,"aborted_at":"%s"}\n' \
      "$RUN_ID" "$rc" "$(date --iso-8601=seconds)" > "$LIVE_DIR/harness-abort.json"
  fi
}
trap cleanup_failed_run EXIT
require_file "$WORK_REPO/target/sqlancer-2.0.0.jar"
"$HARNESS_ROOT/scripts/verify_target.sh" > "$LIVE_DIR/target-verification.txt"

# A formal run starts coverage from a clean server lifetime. This only manages
# the instance whose PGDATA is below /app/my_ShQveL.
"$HARNESS_ROOT/scripts/stop_postgres_cov.sh"
"$HARNESS_ROOT/scripts/reset_coverage.sh"
"$HARNESS_ROOT/scripts/start_postgres_cov.sh"
"$HARNESS_ROOT/scripts/verify_target.sh" >> "$LIVE_DIR/target-verification.txt"
# Exclude server logs left by earlier runs without deleting them.  Subsequent
# snapshots contain only bytes produced by this RUN_ID.
python3 "$HARNESS_ROOT/scripts/initialize_offsets.py" \
  --source "$LOCAL_ROOT/postgres/logs" \
  --state "$STATE_DIR/$RUN_ID-postgres-offsets.json"

if [[ -d "$WORK_REPO/logs/postgresql" ]]; then
  mv "$WORK_REPO/logs/postgresql" "$WORK_REPO/logs/postgresql.before-$RUN_ID"
fi
mkdir -p "$WORK_REPO/logs/postgresql"

export SQLANCER_POSTGRESQL_URL="jdbc:postgresql://127.0.0.1:$PG_PORT/$PG_DATABASE?user=$PG_USER&password=$PG_PASSWORD&ApplicationName=ShQveL-24h"
export SHQVEL_PYTHON_LLM_EVENT_LOG="$LIVE_DIR/python-llm-events.jsonl"
export SHQVEL_JAVA_LLM_EVENT_LOG="$LIVE_DIR/java-llm-events.jsonl"

SOURCE_HASH="$(sha256sum "$WORK_REPO/target/sqlancer-2.0.0.jar" | awk '{print $1}')"
cat > "$LIVE_DIR/run-manifest.json" <<EOF
{"run_id":"$RUN_ID","started_at":"$(date --iso-8601=seconds)","hours":$HOURS,"epoch_seconds":$EPOCH_LENGTH,"mode":"online-learning-and-fuzzing","postgres_version":"$PG_VERSION","postgres_port":$PG_PORT,"postgres_data":"$PG_DATA","sqlancer_jar_sha256":"$SOURCE_HASH","configured_datatypes_only":true,"statement_learning":false,"datatype_learning":true,"expression_learning":true,"clause_learning":false,"direct_validation":true,"learning_interval_seconds":60,"num_queries_per_database":100000,"threads":1}
EOF

source /usr/local/miniconda3/etc/profile.d/conda.sh
conda activate "$CONDA_ENV"
GROUP_PID_FILE="$STATE_DIR/$RUN_ID-shqvel-group.pid"
(
  cd "$WORK_REPO"
  exec python3 "$HARNESS_ROOT/scripts/run_process_group.py" --pid-file "$GROUP_PID_FILE" -- \
    timeout --signal=INT --kill-after=60 "$RUN_SECONDS" \
    java -jar target/sqlancer-2.0.0.jar \
      --enable-extra-features --enable-learning --num-threads 1 \
      --num-tries 1000000 --num-queries 100000 --log-each-select true --log-execution-time true \
      general --database-engine postgresql --documentation-yaml postgresql-url.yml \
      --configured-datatypes-only true --enable-function-overview-learning false \
      --enable-statement-learning false --enable-datatype-learning true \
      --enable-expression-learning true --enable-clause-learning false \
      --enable-direct-validation true --learning-interval-seconds 60 --oracle FUZZING \
      --save-learned-fragments "$LIVE_DIR/learned-fragments.json"
) > "$LIVE_DIR/shqvel.stdout.log" 2>&1 &
SHQVEL_PID=$!
printf '%s\n' "$SHQVEL_PID" > "$STATE_DIR/$RUN_ID-shqvel-launcher.pid"
for _ in {1..100}; do
  [[ -s "$GROUP_PID_FILE" ]] && break
  kill -0 "$SHQVEL_PID" 2>/dev/null || break
  sleep 0.1
done
require_file "$GROUP_PID_FILE"
SHQVEL_PGID="$(<"$GROUP_PID_FILE")"
[[ "$SHQVEL_PGID" =~ ^[0-9]+$ ]] || die "invalid ShQveL process-group id"

START_EPOCH="$(date +%s)"
for ((epoch=1; epoch<=HOURS; epoch++)); do
  deadline=$((START_EPOCH + epoch * EPOCH_LENGTH))
  while kill -0 "$SHQVEL_PID" 2>/dev/null; do
    now="$(date +%s)"
    (( now >= deadline )) && break
    sleep_for=$((deadline - now))
    (( sleep_for > 30 )) && sleep_for=30
    sleep "$sleep_for"
  done
  "$HARNESS_ROOT/scripts/snapshot_epoch.sh" "$RUN_ID" "$epoch" "$WORK_REPO" "$LIVE_DIR"
  kill -0 "$SHQVEL_PID" 2>/dev/null || break
done

wait "$SHQVEL_PID" || STATUS=$?
STATUS="${STATUS:-0}"
printf '%s\n' "$STATUS" > "$LIVE_DIR/exit-status.txt"
cat > "$LIVE_DIR/run-result.json" <<EOF
{"run_id":"$RUN_ID","ended_at":"$(date --iso-8601=seconds)","process_status":$STATUS,"expected_timeout_status":124,"completed_scheduled_duration":$([[ "$STATUS" -eq 124 ]] && echo true || echo false)}
EOF

# Capture bytes created after the last hourly boundary, including the final
# checkpoint, exit status and any SQL racing with the timeout boundary.
"$HARNESS_ROOT/scripts/snapshot_final_artifacts.sh" "$RUN_ID" "$WORK_REPO" "$LIVE_DIR"

# Final graceful stop flushes counters held by the postmaster/background
# processes. The database is restarted after final capture for later replay.
"$HARNESS_ROOT/scripts/stop_postgres_cov.sh"
FINAL_DIR="$SPOOL_DIR/$RUN_ID/final-coverage"
"$HARNESS_ROOT/scripts/collect_coverage.sh" "$FINAL_DIR"
"$HARNESS_ROOT/scripts/start_postgres_cov.sh"
(cd "$FINAL_DIR" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
date --iso-8601=seconds > "$FINAL_DIR/COMPLETE"
"$HARNESS_ROOT/scripts/upload_epoch.sh" "$RUN_ID" final-coverage "$FINAL_DIR"
printf 'run_id=%s status=%s\n' "$RUN_ID" "$STATUS"
