#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

error_log=${1:-$MYSQL_LOG_DIR/error.log}
general_log=${2:-}
mysql_assert_managed_paths
mysql_port_is_free || mysql_die "port $MYSQL_PORT is already occupied"
[[ ! -e "$MYSQL_DATA/mysqld.pid" ]] || mysql_die "managed MySQL PID file already exists"
mkdir -p "$(dirname "$error_log")"
"$MYSQL_BIN/mysqld" --basedir="$MYSQL_INSTALL" --datadir="$MYSQL_DATA" \
  --socket="$MYSQL_SOCKET" --port="$MYSQL_PORT" --bind-address=127.0.0.1 \
  --pid-file="$MYSQL_DATA/mysqld.pid" --user=root --log-error="$error_log" --daemonize
for _ in {1..60}; do
  mysql_admin ping >/dev/null 2>&1 && break
  sleep 1
done
mysql_admin ping >/dev/null 2>&1 || mysql_die "managed MySQL did not become ready"
mysql_verify_running
mysql_client -e 'CREATE DATABASE IF NOT EXISTS test;'
if [[ -n "$general_log" ]]; then
  mkdir -p "$(dirname "$general_log")"
  mysql_client -e "SET GLOBAL log_output='FILE'; SET GLOBAL general_log=OFF; SET GLOBAL general_log_file='$general_log'; SET GLOBAL general_log=ON;"
fi
