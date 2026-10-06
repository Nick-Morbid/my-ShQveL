#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

mysql_assert_managed_paths
[[ -s "$MYSQL_DATA/mysqld.pid" ]] || exit 0
pid="$(<"$MYSQL_DATA/mysqld.pid")"
mysql_pid_running "$pid" || mysql_die "stale managed MySQL PID file: $pid"
[[ "$(readlink -f "/proc/$pid/exe")" == "$(readlink -f "$MYSQL_BIN/mysqld")" ]] || \
  mysql_die "refusing to stop a non-Harness mysqld"
mysql_client -e 'SET GLOBAL general_log=OFF;' >/dev/null 2>&1 || true
mysql_admin shutdown
for _ in {1..60}; do
  mysql_pid_running "$pid" || break
  sleep 1
done
mysql_pid_running "$pid" && mysql_die "managed MySQL did not stop cleanly"
[[ ! -e "$MYSQL_DATA/mysqld.pid" ]] || mysql_die "managed PID file remains after shutdown"
