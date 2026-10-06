#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

mysql_assert_managed_paths
mysql_require_dir "$MYSQL_SOURCE"
mysql_require_file "$MYSQL_SOURCE/CMakeLists.txt"
mysql_require_dir "$MYSQL_SOURCE/extra/boost/boost_1_84_0/boost"
mkdir -p "$MYSQL_LOG_DIR" "$MYSQL_STATE"

if [[ -f "$MYSQL_BUILD/CMakeCache.txt" ]]; then
  cached_source="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$MYSQL_BUILD/CMakeCache.txt")"
  [[ "$cached_source" == "$MYSQL_SOURCE" ]] || mysql_die "stale build tree belongs to $cached_source; archive and remove this generated tree before rebuilding"
fi

if ! mysql_port_is_free; then
  mysql_die "port $MYSQL_PORT is occupied; refusing to stop or modify any MySQL instance"
fi
if [[ -f "$MYSQL_DATA/mysqld.pid" ]]; then
  pid="$(<"$MYSQL_DATA/mysqld.pid")"
  if mysql_pid_running "$pid"; then
    mysql_die "managed data directory has a live mysqld PID $pid; stop it explicitly before rebuilding"
  fi
fi

version_major="$(sed -n 's/^MYSQL_VERSION_MAJOR=//p' "$MYSQL_SOURCE/MYSQL_VERSION")"
version_minor="$(sed -n 's/^MYSQL_VERSION_MINOR=//p' "$MYSQL_SOURCE/MYSQL_VERSION")"
version_patch="$(sed -n 's/^MYSQL_VERSION_PATCH=//p' "$MYSQL_SOURCE/MYSQL_VERSION")"
SOURCE_VERSION="$version_major.$version_minor.$version_patch"
[[ "$SOURCE_VERSION" == 8.4.8 ]] || mysql_die "expected MySQL 8.4.8 source, found $SOURCE_VERSION"

write_build_manifest() {
  local server_sha build_sha gcno_count
  server_sha="$(sha256sum "$MYSQL_INSTALL/bin/mysqld" | awk '{print $1}')"
  build_sha="$(sha256sum "$MYSQL_BUILD/runtime_output_directory/mysqld" | awk '{print $1}')"
  gcno_count="$(find "$MYSQL_BUILD" -type f -name '*.gcno' | wc -l)"
  cat > "$MYSQL_STATE/mysql-cov-build-manifest.json" <<EOF
{"built_at":"$(date --iso-8601=seconds)","mysql_version":"$SOURCE_VERSION","source":"$MYSQL_SOURCE","build":"$MYSQL_BUILD","install":"$MYSQL_INSTALL","data":"$MYSQL_DATA","port":$MYSQL_PORT,"server_sha256":"$server_sha","build_mysqld_sha256":"$build_sha","gcno_count":$gcno_count,"c_flags":"-DNDEBUG -fprofile-arcs -ftest-coverage -fprofile-update=atomic -fPIC -O0 -g","cxx_flags":"-DNDEBUG -fprofile-arcs -ftest-coverage -fprofile-update=atomic -fPIC -O0 -g","linker_flags":"-fprofile-arcs -ftest-coverage -lgcov","profile_update":"atomic"}
EOF
}

# Recover cleanly if a previous invocation completed build+install but was
# interrupted while writing the manifest. CMake installation adjusts RPATH,
# so the installed executable is verified by its install manifest and gcov
# runtime symbols, not by byte-for-byte equality with the build-tree binary.
if [[ -x "$MYSQL_INSTALL/bin/mysqld" && -x "$MYSQL_BUILD/runtime_output_directory/mysqld" && -f "$MYSQL_BUILD/install_manifest.txt" ]] \
  && grep -Fxq "$MYSQL_INSTALL/bin/mysqld" "$MYSQL_BUILD/install_manifest.txt" \
  && grep -Eq '^CMAKE_HOME_DIRECTORY:INTERNAL=/app/my_ShQveL/mysql/source$' "$MYSQL_BUILD/CMakeCache.txt" \
  && grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" \
  && grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" \
  && grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" \
  && grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" \
  && ! ldd "$MYSQL_INSTALL/bin/mysqld" | grep -q libasan \
  && nm -a "$MYSQL_INSTALL/bin/mysqld" 2>/dev/null | grep '__gcov_init' >/dev/null \
  && [[ "$(find "$MYSQL_BUILD" -type f -name '*.gcno' | wc -l)" -gt 1000 ]]; then
  write_build_manifest
  "$SHQVEL_ROOT/scripts/preflight_mysql_cov.sh"
  echo 'Existing coverage build was verified; no rebuild was needed.'
  exit 0
fi

{
  date --iso-8601=seconds
  printf 'source=%s\nbuild=%s\ninstall=%s\ndata=%s\n' "$MYSQL_SOURCE" "$MYSQL_BUILD" "$MYSQL_INSTALL" "$MYSQL_DATA"
  printf 'previous_build_flags:\n'
  rg '^(CMAKE_(C|CXX)_FLAGS|CMAKE_(EXE|SHARED)_LINKER_FLAGS|CMAKE_INSTALL_PREFIX):' "$MYSQL_BUILD/CMakeCache.txt" 2>/dev/null || true
} > "$MYSQL_LOG_DIR/mysql-cov-build-previous.txt"

# Reconfigure the harness-owned build tree to gcov before cleaning generated
# objects.  The active system MySQL and /usr/local/mysql848 are never targets.
cmake -S "$MYSQL_SOURCE" -B "$MYSQL_BUILD" \
  -DCMAKE_INSTALL_PREFIX="$MYSQL_INSTALL" \
  -DCMAKE_BUILD_TYPE= \
  -DCMAKE_C_FLAGS='-DNDEBUG -fprofile-arcs -ftest-coverage -fprofile-update=atomic -fPIC -O0 -g' \
  -DCMAKE_CXX_FLAGS='-DNDEBUG -fprofile-arcs -ftest-coverage -fprofile-update=atomic -fPIC -O0 -g' \
  -DCMAKE_EXE_LINKER_FLAGS='-fprofile-arcs -ftest-coverage -lgcov' \
  -DCMAKE_SHARED_LINKER_FLAGS='-fprofile-arcs -ftest-coverage -lgcov' \
  -DWITH_UNIT_TESTS=OFF \
  -DWITH_DEBUG=OFF \
  -DFORCE_INSOURCE_BUILD=OFF \
  2>&1 | tee "$MYSQL_LOG_DIR/mysql-cov-cmake.log"

grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "CMake C flags are not gcov-instrumented"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "CMake C++ flags are not gcov-instrumented"
grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C gcov counters are not atomic"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C++ gcov counters are not atomic"
grep -Eq '^CMAKE_EXE_LINKER_FLAGS:STRING=.*-lgcov' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "CMake executable linker flags omit libgcov"
grep -Eq '^CMAKE_INSTALL_PREFIX:PATH=/app/my_ShQveL/mysql/install$' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "CMake install prefix escaped the isolated harness"

# The generated objects belong only to this isolated harness build. Clear
# stale notes/counters so the later probe proves the new compiler flags ran.
cmake --build "$MYSQL_BUILD" --target clean 2>&1 | tee "$MYSQL_LOG_DIR/mysql-cov-clean.log"
find "$MYSQL_BUILD" -type f \( -name '*.gcno' -o -name '*.gcda' \) -delete

JOBS="${MYSQL_BUILD_JOBS:-$(nproc)}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || mysql_die "MYSQL_BUILD_JOBS must be a positive integer"
cmake --build "$MYSQL_BUILD" --parallel "$JOBS" 2>&1 | tee "$MYSQL_LOG_DIR/mysql-cov-build.log"
cmake --install "$MYSQL_BUILD" 2>&1 | tee "$MYSQL_LOG_DIR/mysql-cov-install.log"

mysql_require_file "$MYSQL_INSTALL/bin/mysqld"
mysql_require_file "$MYSQL_BUILD/runtime_output_directory/mysqld"
grep -Fxq "$MYSQL_INSTALL/bin/mysqld" "$MYSQL_BUILD/install_manifest.txt" || mysql_die "CMake did not install the server at the Harness path"
if ldd "$MYSQL_INSTALL/bin/mysqld" | grep -q 'libasan'; then
  mysql_die "installed mysqld still links AddressSanitizer"
fi
nm -a "$MYSQL_INSTALL/bin/mysqld" 2>/dev/null | grep '__gcov_init' >/dev/null || mysql_die "installed mysqld does not contain the gcov runtime"
GCNO_COUNT="$(find "$MYSQL_BUILD" -type f -name '*.gcno' | wc -l)"
(( GCNO_COUNT > 1000 )) || mysql_die "too few gcov note files after build: $GCNO_COUNT"

SERVER_SHA="$(sha256sum "$MYSQL_INSTALL/bin/mysqld" | awk '{print $1}')"
write_build_manifest
printf 'Coverage-instrumented MySQL built and installed at %s\n' "$MYSQL_INSTALL"
printf 'mysqld_sha256=%s\ngcno_count=%s\n' "$SERVER_SHA" "$GCNO_COUNT"

