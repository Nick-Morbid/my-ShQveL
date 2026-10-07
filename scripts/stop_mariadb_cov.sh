#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
mariadb_assert_managed_paths; [[ -s "$MARIADB_PID_FILE" ]] || exit 0
pid="$(<"$MARIADB_PID_FILE")"; mariadb_pid_running "$pid" || mariadb_die "stale PID: $pid"
[[ "$(readlink -f "/proc/$pid/exe")" == "$(readlink -f "$MARIADB_BIN/mariadbd")" ]] || mariadb_die "refusing to stop non-Harness process"
mariadb_client -e 'SET GLOBAL general_log=OFF' >/dev/null 2>&1 || true
mariadb_admin shutdown
for _ in {1..90}; do mariadb_pid_running "$pid" || break; sleep 1; done
mariadb_pid_running "$pid" && mariadb_die "managed server did not stop cleanly"
[[ ! -e "$MARIADB_PID_FILE" ]] || mariadb_die "PID file remains after shutdown"
