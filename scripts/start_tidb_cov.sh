#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
log_file="${1:-$TIDB_LOG_DIR/tidb.log}"
tidb_assert_managed_paths; tidb_assert_no_active_mariadb_experiment; tidb_port_is_free "$TIDB_PORT" || tidb_die "SQL port occupied"; tidb_port_is_free "$TIDB_STATUS_PORT" || tidb_die "status port occupied"
[[ ! -e "$TIDB_PID_FILE" ]] || tidb_die "managed PID file exists"
setsid -f "$SHQVEL_ROOT/scripts/tidb_server_exec.sh" "$log_file"
for _ in {1..120}; do
  tidb_ping >/dev/null 2>&1 && break
  if tidb_port_is_free "$TIDB_PORT"; then
    :
  elif "$TIDB_MYSQL_CLIENT" --protocol=tcp -h 127.0.0.1 -P "$TIDB_PORT" -u root -N -e 'SELECT 1' >/dev/null 2>&1; then
    "$TIDB_MYSQL_CLIENT" --protocol=tcp -h 127.0.0.1 -P "$TIDB_PORT" -u root <<SQL
ALTER USER 'root'@'%' IDENTIFIED BY '$TIDB_PASSWORD';
CREATE DATABASE IF NOT EXISTS test;
SQL
    tidb_ping >/dev/null 2>&1 || tidb_die "TiDB root account bootstrap did not take effect"
  fi
  if [[ -s "$TIDB_PID_FILE" ]]; then pid="$(<"$TIDB_PID_FILE")"; tidb_pid_running "$pid" || { tail -100 "$log_file" >&2; tidb_die "TiDB exited during startup"; }; fi
  sleep 1
done
tidb_ping >/dev/null 2>&1 || tidb_die "TiDB did not become ready"
tidb_verify_running
tidb_client -e "ALTER USER 'root'@'%' IDENTIFIED BY '$TIDB_PASSWORD'; CREATE DATABASE IF NOT EXISTS test; SET GLOBAL tidb_general_log=1;" >/dev/null
