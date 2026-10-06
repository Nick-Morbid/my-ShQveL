#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"

TARBALL="$LOCAL_ROOT/postgres/source/postgresql-$PG_VERSION.tar.gz"
SOURCE_PARENT="$LOCAL_ROOT/postgres/source"
DOWNLOAD_URL="https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.gz"

[[ "$PG_PORT" != 5432 && "$PG_PORT" != 5433 ]] || die "coverage PostgreSQL must not use 5432 or 5433"
if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$PG_PORT$"; then
  die "port $PG_PORT is already in use"
fi

mkdir -p "$SOURCE_PARENT" "$(dirname "$PG_INSTALL")" "$PG_SOCKET"
if [[ ! -f "$TARBALL" ]]; then
  curl -fL --retry 3 -o "$TARBALL.part" "$DOWNLOAD_URL"
  mv "$TARBALL.part" "$TARBALL"
fi
if [[ ! -d "$PG_SOURCE" ]]; then
  tar -xzf "$TARBALL" -C "$SOURCE_PARENT"
fi

chown -R postgres:postgres "$PG_SOURCE" "$(dirname "$PG_INSTALL")" "$PG_SOCKET"
sudo -u postgres bash -Eeuo pipefail <<EOF
cd "$PG_SOURCE"
./configure \
  --prefix="$PG_INSTALL" \
  --with-pgport="$PG_PORT" \
  --enable-debug \
  --enable-cassert \
  --enable-coverage \
  --without-icu
make -j"\$(nproc)"
make install
EOF

if [[ ! -f "$PG_DATA/PG_VERSION" ]]; then
  mkdir -p "$PG_DATA"
  chown postgres:postgres "$PG_DATA"
  sudo -u postgres "$PG_INSTALL/bin/initdb" -D "$PG_DATA" --auth-local=trust --auth-host=scram-sha-256
fi

cat >> "$PG_DATA/postgresql.auto.conf" <<EOF
port = $PG_PORT
listen_addresses = '127.0.0.1'
unix_socket_directories = '$PG_SOCKET'
logging_collector = on
log_destination = 'csvlog'
log_directory = '$LOCAL_ROOT/postgres/logs'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S'
log_connections = on
log_disconnections = on
log_min_error_statement = error
log_line_prefix = '%m [%p] %a %u@%d '
shared_preload_libraries = ''
log_statement = 'all'
log_rotation_age = 60
log_rotation_size = 0
log_truncate_on_rotation = off
EOF
chown postgres:postgres "$PG_DATA/postgresql.auto.conf"
mkdir -p "$LOCAL_ROOT/postgres/logs"
chown postgres:postgres "$LOCAL_ROOT/postgres/logs"

"$HARNESS_ROOT/scripts/start_postgres_cov.sh"
sudo -u postgres "$PG_INSTALL/bin/psql" -X -v ON_ERROR_STOP=1 \
  -h "$PG_SOCKET" -p "$PG_PORT" -U postgres -d postgres <<SQL
ALTER USER postgres PASSWORD '$PG_PASSWORD';
SELECT 'CREATE DATABASE $PG_DATABASE' WHERE NOT EXISTS
  (SELECT FROM pg_database WHERE datname = '$PG_DATABASE')\\gexec
SQL

printf 'PostgreSQL coverage build ready at %s on port %s\n' "$PG_INSTALL" "$PG_PORT"
