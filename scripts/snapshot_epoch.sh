#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -eq 4 ]] || die "usage: $0 RUN_ID EPOCH_NUMBER WORK_REPO LIVE_DIR"
RUN_ID="$1"
EPOCH_NUMBER="$2"
WORK_REPO="$(readlink -m "$3")"
LIVE_DIR="$(readlink -m "$4")"
EPOCH_NAME="$(printf 'epoch-%02d' "$EPOCH_NUMBER")"
EPOCH_DIR="$SPOOL_DIR/$RUN_ID/$EPOCH_NAME"
SNAPSHOT_START="$(date --iso-8601=ns)"
SNAPSHOT_START_NS="$(date +%s%N)"
[[ ! -e "$EPOCH_DIR/COMPLETE" ]] || die "local epoch already complete: $EPOCH_DIR"
mkdir -p "$EPOCH_DIR/sql" "$EPOCH_DIR/runtime" "$EPOCH_DIR/postgres" "$EPOCH_DIR/llm" "$EPOCH_DIR/learning" "$EPOCH_DIR/coverage"

# Close the hour's CSV log before slicing it.  This makes every uploaded SQL
# chunk immutable and lets us safely reclaim the old local log after commit.
psql_cov -Atc "SELECT pg_rotate_logfile();" >/dev/null
sleep 1
ACTIVE_LOG="$(psql_cov -Atc "SELECT pg_current_logfile('csvlog');")"
ACTIVE_LOG="$(basename "$ACTIVE_LOG")"

python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$WORK_REPO/logs/postgresql" \
  --state "$STATE_DIR/$RUN_ID-sql-offsets.json" \
  --output "$EPOCH_DIR/sql"
python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$LIVE_DIR" \
  --state "$STATE_DIR/$RUN_ID-runtime-offsets.json" \
  --output "$EPOCH_DIR/runtime"
python3 "$HARNESS_ROOT/scripts/snapshot_sql_logs.py" \
  --source "$LOCAL_ROOT/postgres/logs" \
  --state "$STATE_DIR/$RUN_ID-postgres-offsets.json" \
  --output "$EPOCH_DIR/postgres" \
  --exclude "$ACTIVE_LOG"

for event_file in "$LIVE_DIR"/*.jsonl; do
  [[ -f "$event_file" ]] || continue
  cp "$event_file" "$EPOCH_DIR/llm/$(basename "$event_file")"
done
for checkpoint in "$LIVE_DIR"/*.json; do
  [[ -f "$checkpoint" ]] || continue
  cp "$checkpoint" "$EPOCH_DIR/learning/$(basename "$checkpoint")"
done
if [[ -d "$WORK_REPO/logs/postgresql/learner" ]]; then
  cp -a "$WORK_REPO/logs/postgresql/learner" "$EPOCH_DIR/learning/"
fi

"$HARNESS_ROOT/scripts/collect_coverage.sh" "$EPOCH_DIR/coverage"
python3 "$HARNESS_ROOT/scripts/analyze_epoch.py" --epoch "$EPOCH_DIR"
{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'epoch=%s\n' "$EPOCH_NUMBER"
  printf 'snapshot_started_at=%s\n' "$SNAPSHOT_START"
  printf 'captured_at=%s\n' "$(date --iso-8601=seconds)"
  printf 'snapshot_elapsed_seconds=%s\n' "$(( ($(date +%s%N) - SNAPSHOT_START_NS) / 1000000000 ))"
  "$HARNESS_ROOT/scripts/verify_target.sh"
} > "$EPOCH_DIR/epoch-manifest.txt"

(cd "$EPOCH_DIR" && find . -type f ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
date --iso-8601=seconds > "$EPOCH_DIR/COMPLETE"
"$HARNESS_ROOT/scripts/upload_epoch.sh" "$RUN_ID" "$EPOCH_NAME" "$EPOCH_DIR"
python3 "$HARNESS_ROOT/scripts/prune_uploaded_epoch.py" \
  --local-root "$LOCAL_ROOT" --run-id "$RUN_ID" --epoch "$EPOCH_NAME" \
  --remote "$NFS_ROOT/$RUN_ID/$EPOCH_NAME" \
  --postgres-logs "$LOCAL_ROOT/postgres/logs" \
  --offset-state "$STATE_DIR/$RUN_ID-postgres-offsets.json" \
  --active-log "$ACTIVE_LOG"
