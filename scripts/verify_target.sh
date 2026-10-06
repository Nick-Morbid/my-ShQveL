#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
require_file "$PG_DATA/postmaster.pid"
PID="$(head -1 "$PG_DATA/postmaster.pid")"
[[ "$PID" =~ ^[0-9]+$ ]] || die "invalid managed postmaster PID"
EXPECTED_EXE="$(readlink -f "$PG_INSTALL/bin/postgres")"
ACTUAL_EXE="$(readlink -f "/proc/$PID/exe")"
[[ "$ACTUAL_EXE" == "$EXPECTED_EXE" ]] || die "wrong postgres executable: $ACTUAL_EXE"

RESULT="$(psql_cov -Atc "SELECT current_setting('server_version'), inet_server_port(), current_setting('data_directory'), current_database()")"
IFS='|' read -r VERSION PORT DATA DB <<< "$RESULT"
[[ "$VERSION" == "$PG_VERSION"* ]] || die "wrong PostgreSQL version: $VERSION"
[[ "$PORT" == "$PG_PORT" ]] || die "wrong PostgreSQL port: $PORT"
[[ "$(readlink -m "$DATA")" == "$(readlink -m "$PG_DATA")" ]] || die "wrong data_directory: $DATA"
[[ "$DB" == "$PG_DATABASE" ]] || die "wrong database: $DB"

printf 'pid=%s\nexecutable=%s\nversion=%s\nport=%s\ndata_directory=%s\ndatabase=%s\n' \
  "$PID" "$ACTUAL_EXE" "$VERSION" "$PORT" "$DATA" "$DB"

