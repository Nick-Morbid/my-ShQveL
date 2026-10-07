#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
error_log="$(readlink -m "${1:-$MARIADB_LOG_DIR/error.log}")"; general_log=${2:-}
mariadb_assert_managed_paths; mariadb_port_is_free || mariadb_die "port occupied"; [[ ! -e "$MARIADB_PID_FILE" ]] || mariadb_die "PID file exists"
mkdir -p "$(dirname "$error_log")"
setsid -f "$MARIADB_BIN/mariadbd" --no-defaults --basedir="$MARIADB_INSTALL" --datadir="$MARIADB_DATA" --socket="$MARIADB_SOCKET" \
  --port="$MARIADB_PORT" --bind-address=127.0.0.1 --pid-file="$MARIADB_PID_FILE" --user=root --log-error="$error_log" \
  </dev/null >>"$MARIADB_LOG_DIR/server-stdout.log" 2>&1
for _ in {1..60}; do
  mariadb_ping >/dev/null 2>&1 && break
  if [[ -S "$MARIADB_SOCKET" ]] && "$MARIADB_BIN/mariadb-admin" --no-defaults --protocol=socket --socket="$MARIADB_SOCKET" -u root ping >/dev/null 2>&1; then
    "$MARIADB_BIN/mariadb" --no-defaults --protocol=socket --socket="$MARIADB_SOCKET" -u root >>"$MARIADB_LOG_DIR/bootstrap-account.log" 2>&1 <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MARIADB_PASSWORD';
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY '$MARIADB_PASSWORD';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$MARIADB_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    MYSQL_PWD="$MARIADB_PASSWORD" "$MARIADB_BIN/mariadb" --no-defaults --protocol=socket --socket="$MARIADB_SOCKET" -u root -e 'SELECT 1' \
      >>"$MARIADB_LOG_DIR/bootstrap-account.log" 2>&1 || mariadb_die "root account bootstrap did not take effect"
  fi
  if [[ -s "$MARIADB_PID_FILE" ]]; then
    server_pid="$(<"$MARIADB_PID_FILE")"
    mariadb_pid_running "$server_pid" || { tail -100 "$error_log" >&2; mariadb_die "server exited during startup"; }
  fi
  sleep 1
done
mariadb_ping >/dev/null 2>&1 || mariadb_die "server did not become ready with authenticated SQL"
mariadb_verify_running
mariadb_client -e 'CREATE DATABASE IF NOT EXISTS test;'
if [[ -n "$general_log" ]]; then
  general_log="$(readlink -m "$general_log")"
  mkdir -p "$(dirname "$general_log")"
  mariadb_client -e "SET GLOBAL log_output='FILE'; SET GLOBAL general_log=OFF; SET GLOBAL general_log_file='$general_log'; SET GLOBAL general_log=ON;"
fi
