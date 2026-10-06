#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
assert_managed_pgdata
if pg_is_running; then
  sudo -u postgres "$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" -m fast -w stop
fi

