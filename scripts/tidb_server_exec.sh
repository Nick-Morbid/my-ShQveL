#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
[[ $# -eq 1 ]] || tidb_die "usage: $0 LOG_FILE"
log_file="$(readlink -m "$1")"; mkdir -p "$(dirname "$log_file")" "$TIDB_COVER" "$TIDB_DATA"
printf '%s\n' "$$" > "$TIDB_PID_FILE"
export GOCOVERDIR="$TIDB_COVER"
exec "$TIDB_BIN" --store=unistore --path="$TIDB_DATA" --host=127.0.0.1 \
  -P "$TIDB_PORT" --status="$TIDB_STATUS_PORT" --log-file="$log_file" --log-general="$log_file.general" --log-level=error
