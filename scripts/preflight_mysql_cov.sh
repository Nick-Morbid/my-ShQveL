#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

require_probe=0
[[ "${1:-}" == --require-probe ]] && require_probe=1
mysql_assert_managed_paths
mysql_require_file "$MYSQL_BUILD/CMakeCache.txt"
mysql_require_file "$MYSQL_STATE/mysql-cov-build-manifest.json"
mysql_require_file "$MYSQL_INSTALL/bin/mysqld"
mysql_require_file "$MYSQL_INSTALL/bin/mysql"
mysql_require_file "$SHQVEL_WORK/target/sqlancer-2.0.0.jar"
mysql_require_file "$SHQVEL_WORK/dbconfigs/mysql-url-8.4.yml"
[[ -L "$SHQVEL_WORK/dbconfigs/llm.properties" ]] || mysql_die "LLM configuration link is missing"

grep -Eq '^CMAKE_HOME_DIRECTORY:INTERNAL=/app/my_ShQveL/mysql/source$' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "build tree is for a different source directory"
grep -Eq '^CMAKE_INSTALL_PREFIX:PATH=/app/my_ShQveL/mysql/install$' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "build tree has a non-isolated install prefix"
grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C flags lack gcov instrumentation"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-arcs.*-ftest-coverage' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C++ flags lack gcov instrumentation"
grep -Eq '^CMAKE_C_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C gcov counters are not atomic"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*-fprofile-update=atomic' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "C++ gcov counters are not atomic"
grep -Eq '^CMAKE_EXE_LINKER_FLAGS:STRING=.*-lgcov' "$MYSQL_BUILD/CMakeCache.txt" || mysql_die "executable link flags lack libgcov"
if ldd "$MYSQL_INSTALL/bin/mysqld" | grep -q 'libasan'; then mysql_die "installed server links AddressSanitizer"; fi

build_sha="$(sha256sum "$MYSQL_BUILD/runtime_output_directory/mysqld" | awk '{print $1}')"
install_sha="$(sha256sum "$MYSQL_INSTALL/bin/mysqld" | awk '{print $1}')"
grep -Fxq "$MYSQL_INSTALL/bin/mysqld" "$MYSQL_BUILD/install_manifest.txt" || mysql_die "CMake install manifest does not include the Harness mysqld"
nm -a "$MYSQL_INSTALL/bin/mysqld" 2>/dev/null | grep '__gcov_init' >/dev/null || mysql_die "installed mysqld has no gcov runtime symbols"
python3 - "$MYSQL_STATE/mysql-cov-build-manifest.json" "$install_sha" "$build_sha" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
assert d.get("mysql_version") == "8.4.8", "build manifest is not MySQL 8.4.8"
assert d.get("server_sha256") == sys.argv[2], "installed mysqld differs from build manifest"
assert d.get("build_mysqld_sha256") == sys.argv[3], "build-tree mysqld differs from build manifest"
assert d.get("install") == "/app/my_ShQveL/mysql/install", "manifest points outside Harness install"
assert int(d.get("gcno_count", 0)) > 1000, "manifest records too few gcov note files"
assert d.get("profile_update") == "atomic", "build manifest does not require atomic gcov updates"
PY
version="$("$MYSQL_INSTALL/bin/mysqld" --version)"
[[ "$version" == *"8.4.8"* ]] || mysql_die "unexpected installed server version: $version"
gcno_count="$(find "$MYSQL_BUILD" -type f -name '*.gcno' | wc -l)"
(( gcno_count > 1000 )) || mysql_die "only $gcno_count .gcno files found"
mysql_port_is_free || mysql_die "port $MYSQL_PORT is already listening; refusing to reuse another server"
[[ -d "$MYSQL_DATA/mysql" ]] || mysql_die "managed MySQL data directory is not initialized"

if (( require_probe )); then
  mysql_require_file "$MYSQL_STATE/mysql-cov-probe.json"
  python3 - "$MYSQL_STATE/mysql-cov-probe.json" "$install_sha" <<'PY'
import json, sys, time
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
assert d.get("status") == "PASS", "latest coverage probe did not pass"
assert d.get("server_sha256") == sys.argv[2], "probe uses a different mysqld binary"
age = time.time() - p.stat().st_mtime
assert 0 <= age <= 7 * 24 * 3600, f"coverage probe is stale ({age:.0f}s old)"
PY
  mysql_require_file "$MYSQL_STATE/mysql-learning-probe.json"
  python3 - "$MYSQL_STATE/mysql-learning-probe.json" "$install_sha" <<'PY'
import json, sys, time
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
assert d.get("status") == "PASS", d.get("reason", "learning probe did not pass")
assert d.get("server_sha256") == sys.argv[2], "learning probe used a different mysqld binary"
assert int(d.get("event_count", 0)) > 0, "learning probe recorded no successful LLM response"
assert int(d.get("validated_fragment_count", 0)) > 0, "learning probe validated no learned fragments on the target DBMS"
checkpoint_value = d.get("checkpoint")
if checkpoint_value:
    checkpoint = Path(checkpoint_value)
    assert checkpoint.is_file() and json.loads(checkpoint.read_text()), "learning checkpoint is present but empty or unreadable"
age = time.time() - p.stat().st_mtime
assert 0 <= age <= 7 * 24 * 3600, f"learning probe is stale ({age:.0f}s old)"
PY
fi

printf 'PREFLIGHT_OK mysql_version=8.4.8 port=%s gcno=%s mysqld_sha256=%s\n' "$MYSQL_PORT" "$gcno_count" "$install_sha"
(( require_probe == 0 )) || echo 'COVERAGE_AND_LEARNING_PROBES=PASS'

