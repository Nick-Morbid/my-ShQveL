#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
tidb_assert_managed_paths; [[ -s "$TIDB_PID_FILE" ]] || exit 0
pid="$(<"$TIDB_PID_FILE")"; tidb_pid_running "$pid" || tidb_die "stale managed PID: $pid"
[[ "$(readlink -f "/proc/$pid/exe")" == "$(readlink -f "$TIDB_BIN")" ]] || tidb_die "refusing to stop non-Harness process"
kill -TERM "$pid"
for _ in {1..120}; do tidb_pid_running "$pid" || break; sleep 1; done
tidb_pid_running "$pid" && tidb_die "TiDB did not complete signal-driven graceful shutdown; refusing forced kill because coverage would be lost"
unlink "$TIDB_PID_FILE" 2>/dev/null || true
tidb_port_is_free "$TIDB_PORT" || tidb_die "SQL port remains occupied"
tidb_port_is_free "$TIDB_STATUS_PORT" || tidb_die "status port remains occupied"
