#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
mariadb_assert_managed_paths
mkdir -p "$MARIADB_ROOT" "$MARIADB_LOG_DIR" "$MARIADB_STATE"
mariadb_port_is_free || mariadb_die "port $MARIADB_PORT is occupied"
[[ ! -e "$MARIADB_PID_FILE" ]] || mariadb_die "managed PID file exists"
if [[ ! -f "$MARIADB_SOURCE/CMakeLists.txt" ]]; then
  git clone --branch mariadb-12.2.2 --depth 1 https://github.com/MariaDB/server.git "$MARIADB_SOURCE"
fi
version="$(sed -n 's/^MYSQL_VERSION_MAJOR=//p' "$MARIADB_SOURCE/VERSION").$(sed -n 's/^MYSQL_VERSION_MINOR=//p' "$MARIADB_SOURCE/VERSION").$(sed -n 's/^MYSQL_VERSION_PATCH=//p' "$MARIADB_SOURCE/VERSION")"
[[ "$version" == 12.2.2 ]] || mariadb_die "expected 12.2.2 source, found $version"
cmake -S "$MARIADB_SOURCE" -B "$MARIADB_BUILD" \
  -DCMAKE_INSTALL_PREFIX="$MARIADB_INSTALL" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DWITH_DEBUG=OFF \
  -DCMAKE_C_FLAGS='--coverage -fprofile-update=atomic -O0 -g -fno-inline -fno-inline-functions' \
  -DCMAKE_CXX_FLAGS='--coverage -fprofile-update=atomic -O0 -g -fno-inline -fno-inline-functions' \
  -DCMAKE_EXE_LINKER_FLAGS='--coverage' -DCMAKE_SHARED_LINKER_FLAGS='--coverage' \
  -DWITH_UNIT_TESTS=OFF -DWITH_LIBFMT=bundled -DPLUGIN_TOKUDB=NO -DPLUGIN_ROCKSDB=NO \
  -DWITH_SSL=system -DWITH_ZLIB=system 2>&1 | tee "$MARIADB_LOG_DIR/cmake.log"
grep -Eq '^CMAKE_INSTALL_PREFIX:PATH=/app/my_ShQveL/mariadb/install$' "$MARIADB_BUILD/CMakeCache.txt" || mariadb_die "install prefix escaped Harness"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*--coverage.*-fprofile-update=atomic' "$MARIADB_BUILD/CMakeCache.txt" || mariadb_die "coverage/atomic flags missing"
jobs="${MARIADB_BUILD_JOBS:-$(nproc)}"; [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || mariadb_die "invalid job count"
cmake --build "$MARIADB_BUILD" --parallel "$jobs" 2>&1 | tee "$MARIADB_LOG_DIR/build.log"
cmake --install "$MARIADB_BUILD" 2>&1 | tee "$MARIADB_LOG_DIR/install.log"
mariadb_require_file "$MARIADB_BIN/mariadbd"
symbols="$MARIADB_ROOT/.mariadbd-symbols.txt"
nm -a "$MARIADB_BIN/mariadbd" > "$symbols" 2>/dev/null
grep -q '__gcov_init' "$symbols" || mariadb_die "installed server lacks gcov runtime"
rm -f "$symbols"
gcno_count="$(find "$MARIADB_BUILD" -type f -name '*.gcno' | wc -l)"; (( gcno_count > 500 )) || mariadb_die "too few gcno files: $gcno_count"
if [[ ! -d "$MARIADB_DATA/mysql" ]]; then
  mkdir -p "$MARIADB_DATA"
  "$MARIADB_INSTALL/scripts/mariadb-install-db" --no-defaults --basedir="$MARIADB_INSTALL" --datadir="$MARIADB_DATA" --auth-root-authentication-method=normal --user=root
fi
sha="$(sha256sum "$MARIADB_BIN/mariadbd" | awk '{print $1}')"
printf '{"built_at":"%s","version":"12.2.2","source":"%s","build":"%s","install":"%s","data":"%s","port":%s,"server_sha256":"%s","gcno_count":%s,"profile_update":"atomic"}\n' "$(date --iso-8601=seconds)" "$MARIADB_SOURCE" "$MARIADB_BUILD" "$MARIADB_INSTALL" "$MARIADB_DATA" "$MARIADB_PORT" "$sha" "$gcno_count" > "$MARIADB_STATE/mariadb-cov-build-manifest.json"
printf 'MARIADB_COVERAGE_BUILD_OK gcno=%s sha256=%s\n' "$gcno_count" "$sha"
