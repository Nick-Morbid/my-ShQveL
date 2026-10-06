#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
assert_managed_pgdata
require_file "$PG_INSTALL/bin/postgres"
if pg_is_running; then
  printf 'Managed PostgreSQL is already running.\n'
  exit 0
fi
if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$PG_PORT$"; then
  die "port $PG_PORT is occupied by another process"
fi
mkdir -p "$PG_SOCKET" "$LOCAL_ROOT/postgres/logs"
chown postgres:postgres "$PG_SOCKET" "$LOCAL_ROOT/postgres/logs"
sudo -u postgres "$PG_INSTALL/bin/pg_ctl" -D "$PG_DATA" \
  -l "$LOCAL_ROOT/postgres/logs/pg_ctl.log" \
  -o "-p $PG_PORT -k $PG_SOCKET" -w start

