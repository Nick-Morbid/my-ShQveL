#!/usr/bin/env bash
set -Eeuo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${SHQVEL_EXPERIMENT_ENV:-$HARNESS_ROOT/config/experiment.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  ENV_FILE="$HARNESS_ROOT/config/experiment.env.example"
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

export HARNESS_ROOT ENV_FILE
export PG_VERSION PG_PORT PG_DATABASE PG_USER PG_PASSWORD PG_SOURCE PG_INSTALL PG_DATA PG_SOCKET
export SHQVEL_REPO CONDA_ENV NFS_ROOT LOCAL_ROOT LCOV_BRANCH_RC EXPERIMENT_HOURS EPOCH_SECONDS

STATE_DIR="$LOCAL_ROOT/state"
SPOOL_DIR="$LOCAL_ROOT/spool"
LOG_DIR="$LOCAL_ROOT/logs"
mkdir -p "$STATE_DIR" "$SPOOL_DIR" "$LOG_DIR" "$PG_SOCKET"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_file() { [[ -f "$1" ]] || die "missing file: $1"; }
require_dir() { [[ -d "$1" ]] || die "missing directory: $1"; }

assert_managed_pgdata() {
  local resolved
  resolved="$(readlink -m "$PG_DATA")"
  [[ "$resolved" == "$LOCAL_ROOT"/postgres/data ]] || die "refusing unmanaged PG_DATA: $resolved"
}

pg_ctl_managed() {
  assert_managed_pgdata
  "$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" "$@"
}

pg_is_running() {
  [[ -f "$PG_DATA/postmaster.pid" ]] && \
    sudo -u postgres "$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" status >/dev/null 2>&1
}

psql_cov() {
  sudo -u postgres env PGPASSWORD="$PG_PASSWORD" "$PG_INSTALL/bin/psql" -X -v ON_ERROR_STOP=1 \
    -h 127.0.0.1 -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" "$@"
}
