#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -ge 1 && $# -le 2 ]] || die "usage: $0 RUN_ID [OUTPUT_DIR]"
RUN_ID="$1"
REMOTE_RUN="$NFS_ROOT/$RUN_ID"
OUTPUT="${2:-$LOCAL_ROOT/replay/$RUN_ID}"
require_dir "$REMOTE_RUN"
mkdir -p "$OUTPUT/postgres-logs"
python3 "$HARNESS_ROOT/scripts/reconstruct_postgres_logs.py" \
  --run "$REMOTE_RUN" --output "$OUTPUT/postgres-logs"
python3 "$HARNESS_ROOT/scripts/reconstruct_sql_logs.py" \
  --run "$REMOTE_RUN" --output "$OUTPUT/sqlancer-logs"
python3 "$HARNESS_ROOT/scripts/extract_replay_sql.py" \
  --logs "$OUTPUT/postgres-logs" \
  --output "$OUTPUT/replay.sql" \
  --events "$OUTPUT/execution-events.jsonl" \
  --summary "$OUTPUT/execution-summary.json"
zstd -f -T0 "$OUTPUT/replay.sql" -o "$OUTPUT/replay.sql.zst"
zstd -f -T0 "$OUTPUT/execution-events.jsonl" -o "$OUTPUT/execution-events.jsonl.zst"
printf 'Replay bundle: %s\n' "$OUTPUT"
