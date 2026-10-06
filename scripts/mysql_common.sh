#!/usr/bin/env bash
set -Eeuo pipefail

SHQVEL_ROOT=/app/my_ShQveL
MYSQL_ROOT="$SHQVEL_ROOT/mysql"
MYSQL_SOURCE="$MYSQL_ROOT/source"
MYSQL_BUILD="$MYSQL_SOURCE/build"
MYSQL_INSTALL="$MYSQL_ROOT/install"
MYSQL_DATA="$MYSQL_ROOT/data"
MYSQL_SOCKET="$MYSQL_ROOT/mysql.sock"
MYSQL_PORT=3308
MYSQL_USER=root
MYSQL_PASSWORD=123456
MYSQL_BIN="$MYSQL_INSTALL/bin"
MYSQL_LOG_DIR="$MYSQL_ROOT/logs"
SHQVEL_WORK="$SHQVEL_ROOT/work/SQLancerPlusPlus"
MYSQL_STATE="$SHQVEL_ROOT/state"
MYSQL_NFS_ROOT="/app/nfs/chq_data/ShQveL/mysql"
MYSQL_COVERAGE_TEMPLATE="$MYSQL_ROOT/coverage-template"

mysql_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mysql_require_file() { [[ -f "$1" ]] || mysql_die "missing file: $1"; }
mysql_require_dir() { [[ -d "$1" ]] || mysql_die "missing directory: $1"; }

mysql_assert_managed_paths() {
  [[ "$(readlink -m "$MYSQL_ROOT")" == "$SHQVEL_ROOT/mysql" ]] || mysql_die "unexpected MySQL root"
  [[ "$(readlink -m "$MYSQL_INSTALL")" == "$SHQVEL_ROOT/mysql/install" ]] || mysql_die "refusing unexpected install path"
  [[ "$(readlink -m "$MYSQL_DATA")" == "$SHQVEL_ROOT/mysql/data" ]] || mysql_die "refusing unexpected data path"
  [[ "$(readlink -m "$MYSQL_BUILD")" == "$SHQVEL_ROOT/mysql/source/build" ]] || mysql_die "refusing unexpected build path"
}

mysql_port_is_free() {
  ! ss -H -ltn "sport = :$MYSQL_PORT" 2>/dev/null | grep -q .
}

mysql_pid_running() {
  local pid="$1" state
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -n "$state" && "$state" != Z* && "$state" != X* ]]
}

mysql_client() {
  MYSQL_PWD="$MYSQL_PASSWORD" "$MYSQL_BIN/mysql" --protocol=tcp -h 127.0.0.1 -P "$MYSQL_PORT" -u "$MYSQL_USER" "$@"
}

mysql_admin() {
  MYSQL_PWD="$MYSQL_PASSWORD" "$MYSQL_BIN/mysqladmin" --protocol=tcp -h 127.0.0.1 -P "$MYSQL_PORT" -u "$MYSQL_USER" "$@"
}

mysql_verify_running() {
  mysql_require_file "$MYSQL_DATA/mysqld.pid"
  local pid actual expected row
  pid="$(<"$MYSQL_DATA/mysqld.pid")"
  mysql_pid_running "$pid" || mysql_die "managed MySQL PID is not running: $pid"
  actual="$(readlink -f "/proc/$pid/exe")"
  expected="$(readlink -f "$MYSQL_BIN/mysqld")"
  [[ "$actual" == "$expected" ]] || mysql_die "wrong mysqld executable: $actual"
  row="$(mysql_client -N -e 'SELECT @@port, @@basedir, @@datadir, VERSION()')"
  IFS=$'\t' read -r port basedir datadir version <<< "$row"
  [[ "$port" == "$MYSQL_PORT" ]] || mysql_die "wrong MySQL port: $port"
  [[ "$(readlink -m "$basedir")" == "$(readlink -m "$MYSQL_INSTALL")" ]] || mysql_die "wrong basedir: $basedir"
  [[ "$(readlink -m "$datadir")" == "$(readlink -m "$MYSQL_DATA")" ]] || mysql_die "wrong datadir: $datadir"
  [[ "$version" == 8.4.8* ]] || mysql_die "wrong MySQL version: $version"
  printf 'pid=%s\nexecutable=%s\nversion=%s\nport=%s\nbasedir=%s\ndatadir=%s\n' \
    "$pid" "$actual" "$version" "$port" "$basedir" "$datadir"
}

