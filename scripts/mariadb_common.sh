#!/usr/bin/env bash
set -Eeuo pipefail

SHQVEL_ROOT=/app/my_ShQveL
MARIADB_ROOT="$SHQVEL_ROOT/mariadb"
MARIADB_SOURCE="$MARIADB_ROOT/source"
MARIADB_BUILD="$MARIADB_SOURCE/build"
MARIADB_INSTALL="$MARIADB_ROOT/install"
MARIADB_DATA="$MARIADB_ROOT/data"
MARIADB_SOCKET="$MARIADB_ROOT/mariadb.sock"
MARIADB_PID_FILE="$MARIADB_DATA/mariadb.pid"
MARIADB_PORT=3310
MARIADB_USER=root
MARIADB_PASSWORD=123456
MARIADB_BIN="$MARIADB_INSTALL/bin"
MARIADB_LOG_DIR="$MARIADB_ROOT/logs"
MARIADB_STATE="$SHQVEL_ROOT/state"
MARIADB_NFS_ROOT=/app/nfs/chq_data/ShQveL/mariadb
MARIADB_COVERAGE_TEMPLATE="$MARIADB_ROOT/coverage-template"
SHQVEL_WORK="$SHQVEL_ROOT/work/SQLancerPlusPlus"

mariadb_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
mariadb_require_file() { [[ -f "$1" ]] || mariadb_die "missing file: $1"; }
mariadb_require_dir() { [[ -d "$1" ]] || mariadb_die "missing directory: $1"; }
mariadb_assert_managed_paths() {
  [[ "$(readlink -m "$MARIADB_ROOT")" == "$SHQVEL_ROOT/mariadb" ]] || mariadb_die "unexpected MariaDB root"
  [[ "$(readlink -m "$MARIADB_BUILD")" == "$SHQVEL_ROOT/mariadb/source/build" ]] || mariadb_die "unexpected build path"
  [[ "$(readlink -m "$MARIADB_INSTALL")" == "$SHQVEL_ROOT/mariadb/install" ]] || mariadb_die "unexpected install path"
  [[ "$(readlink -m "$MARIADB_DATA")" == "$SHQVEL_ROOT/mariadb/data" ]] || mariadb_die "unexpected data path"
  [[ "$(readlink -m "$MARIADB_SOCKET")" == "$SHQVEL_ROOT/mariadb/mariadb.sock" ]] || mariadb_die "unexpected socket path"
}
mariadb_pid_running() {
  local pid="$1" state
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -n "$state" && "$state" != Z* && "$state" != X* ]]
}
mariadb_port_is_free() { ! ss -H -ltn "sport = :$MARIADB_PORT" 2>/dev/null | grep -q .; }
mariadb_client() {
  MYSQL_PWD="$MARIADB_PASSWORD" "$MARIADB_BIN/mariadb" --protocol=tcp -h 127.0.0.1 -P "$MARIADB_PORT" -u "$MARIADB_USER" "$@"
}
mariadb_admin() {
  MYSQL_PWD="$MARIADB_PASSWORD" "$MARIADB_BIN/mariadb-admin" --protocol=tcp -h 127.0.0.1 -P "$MARIADB_PORT" -u "$MARIADB_USER" "$@"
}
mariadb_ping() { mariadb_client -N -e 'SELECT 1' "$@"; }
mariadb_verify_running() {
  mariadb_require_file "$MARIADB_PID_FILE"
  local pid actual expected row port basedir datadir version
  pid="$(<"$MARIADB_PID_FILE")"; mariadb_pid_running "$pid" || mariadb_die "managed PID is not running: $pid"
  actual="$(readlink -f "/proc/$pid/exe")"; expected="$(readlink -f "$MARIADB_BIN/mariadbd")"
  [[ "$actual" == "$expected" ]] || mariadb_die "wrong mariadbd executable: $actual"
  row="$(mariadb_client -N -e 'SELECT @@port, @@basedir, @@datadir, VERSION()')"
  IFS=$'\t' read -r port basedir datadir version <<< "$row"
  [[ "$port" == "$MARIADB_PORT" ]] || mariadb_die "wrong port: $port"
  [[ "$(readlink -m "$basedir")" == "$(readlink -m "$MARIADB_INSTALL")" ]] || mariadb_die "wrong basedir: $basedir"
  [[ "$(readlink -m "$datadir")" == "$(readlink -m "$MARIADB_DATA")" ]] || mariadb_die "wrong datadir: $datadir"
  [[ "$version" == 12.2.2-MariaDB* ]] || mariadb_die "wrong version: $version"
  printf 'pid=%s\nexecutable=%s\nversion=%s\nport=%s\nbasedir=%s\ndatadir=%s\n' "$pid" "$actual" "$version" "$port" "$basedir" "$datadir"
}
