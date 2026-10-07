#!/usr/bin/env bash
set -Eeuo pipefail

SHQVEL_ROOT=/app/my_ShQveL
TIDB_ROOT="$SHQVEL_ROOT/tidb"
TIDB_SOURCE="$TIDB_ROOT/source"
TIDB_INSTALL="$TIDB_ROOT/install"
TIDB_BIN="$TIDB_INSTALL/bin/tidb-server"
TIDB_DATA="$TIDB_ROOT/data"
TIDB_COVER="$TIDB_ROOT/coverage-runtime"
TIDB_PID_FILE="$TIDB_ROOT/tidb.pid"
TIDB_PORT=4010
TIDB_STATUS_PORT=10181
TIDB_USER=root
TIDB_PASSWORD=123456
TIDB_LOG_DIR="$TIDB_ROOT/logs"
TIDB_GO_ROOT="$TIDB_ROOT/toolchain/go"
TIDB_GO_BIN="$TIDB_GO_ROOT/bin/go"
TIDB_GO_PATH="$TIDB_ROOT/go"
TIDB_GO_CACHE="$TIDB_ROOT/go-cache"
TIDB_STATE="$SHQVEL_ROOT/state"
TIDB_NFS_ROOT=/app/nfs/chq_data/ShQveL/tidb
SHQVEL_WORK="$SHQVEL_ROOT/work/SQLancerPlusPlus"
TIDB_MYSQL_CLIENT="$SHQVEL_ROOT/mariadb/install/bin/mariadb"

tidb_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
tidb_require_file() { [[ -f "$1" ]] || tidb_die "missing file: $1"; }
tidb_require_dir() { [[ -d "$1" ]] || tidb_die "missing directory: $1"; }
tidb_assert_managed_paths() {
  [[ "$(readlink -m "$TIDB_ROOT")" == "$SHQVEL_ROOT/tidb" ]] || tidb_die "unexpected TiDB root"
  [[ "$(readlink -m "$TIDB_SOURCE")" == "$SHQVEL_ROOT/tidb/source" ]] || tidb_die "unexpected source path"
  [[ "$(readlink -m "$TIDB_INSTALL")" == "$SHQVEL_ROOT/tidb/install" ]] || tidb_die "unexpected install path"
  [[ "$(readlink -m "$TIDB_DATA")" == "$SHQVEL_ROOT/tidb/data" ]] || tidb_die "unexpected data path"
  [[ "$(readlink -m "$TIDB_COVER")" == "$SHQVEL_ROOT/tidb/coverage-runtime" ]] || tidb_die "unexpected coverage path"
}
tidb_pid_running() {
  local pid="$1" state
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  state="$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  [[ -n "$state" && "$state" != Z* && "$state" != X* ]]
}
tidb_port_is_free() { ! ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .; }
tidb_assert_no_active_mariadb_experiment() {
  local found
  found="$(ps -eo pid=,args= | awk -v self="$$" '$1 != self && index($0, "/app/my_ShQveL/scripts/run_mariadb_experiment.sh") {print; exit}')"
  [[ -z "$found" ]] || tidb_die "MariaDB experiment is active; refusing TiDB build/start to avoid resource interference: $found"
}
tidb_go() {
  GOROOT="$TIDB_GO_ROOT" GOPATH="$TIDB_GO_PATH" GOCACHE="$TIDB_GO_CACHE" \
    PATH="$TIDB_GO_ROOT/bin:/usr/bin:/bin" "$TIDB_GO_BIN" "$@"
}
tidb_client() {
  MYSQL_PWD="$TIDB_PASSWORD" "$TIDB_MYSQL_CLIENT" --protocol=tcp -h 127.0.0.1 -P "$TIDB_PORT" -u "$TIDB_USER" "$@"
}
tidb_ping() { tidb_client -N -e 'SELECT 1' "$@"; }
tidb_verify_running() {
  tidb_require_file "$TIDB_PID_FILE"
  local pid actual expected row port version
  pid="$(<"$TIDB_PID_FILE")"; tidb_pid_running "$pid" || tidb_die "managed PID is not running: $pid"
  actual="$(readlink -f "/proc/$pid/exe")"; expected="$(readlink -f "$TIDB_BIN")"
  [[ "$actual" == "$expected" ]] || tidb_die "wrong TiDB executable: $actual"
  row="$(tidb_client -N -e 'SELECT @@port, VERSION()')"; IFS=$'\t' read -r port version <<< "$row"
  [[ "$port" == "$TIDB_PORT" ]] || tidb_die "wrong SQL port: $port"
  [[ "$version" == *TiDB* ]] || tidb_die "unexpected server version: $version"
  curl -fsS "http://127.0.0.1:$TIDB_STATUS_PORT/status" >/dev/null || tidb_die "status API unavailable"
  printf 'pid=%s\nexecutable=%s\nversion=%s\nsql_port=%s\nstatus_port=%s\ndata=%s\ncoverage=%s\n' \
    "$pid" "$actual" "$version" "$port" "$TIDB_STATUS_PORT" "$TIDB_DATA" "$TIDB_COVER"
}
