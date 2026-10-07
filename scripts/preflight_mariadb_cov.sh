#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
require_probe=0; [[ "${1:-}" == --require-probe ]] && require_probe=1
mariadb_assert_managed_paths
mariadb_require_file "$MARIADB_BUILD/CMakeCache.txt"; mariadb_require_file "$MARIADB_STATE/mariadb-cov-build-manifest.json"
mariadb_require_file "$MARIADB_BIN/mariadbd"; mariadb_require_file "$MARIADB_BIN/mariadb"
mariadb_require_file "$SHQVEL_WORK/target/sqlancer-2.0.0.jar"; mariadb_require_file "$SHQVEL_WORK/dbconfigs/mariadb-url-12.2.yml"
[[ -L "$SHQVEL_WORK/dbconfigs/llm.properties" ]] || mariadb_die "LLM configuration link missing"
grep -Eq '^CMAKE_HOME_DIRECTORY:INTERNAL=/app/my_ShQveL/mariadb/source$' "$MARIADB_BUILD/CMakeCache.txt" || mariadb_die "wrong source tree"
grep -Eq '^CMAKE_INSTALL_PREFIX:PATH=/app/my_ShQveL/mariadb/install$' "$MARIADB_BUILD/CMakeCache.txt" || mariadb_die "non-isolated install"
grep -Eq '^CMAKE_CXX_FLAGS:STRING=.*--coverage.*-fprofile-update=atomic' "$MARIADB_BUILD/CMakeCache.txt" || mariadb_die "coverage flags missing"
version="$($MARIADB_BIN/mariadbd --version)"; [[ "$version" == *'12.2.2-MariaDB'* ]] || mariadb_die "wrong version"
gcno="$(find "$MARIADB_BUILD" -type f -name '*.gcno' | wc -l)"; (( gcno > 500 )) || mariadb_die "too few gcno files"
[[ -d "$MARIADB_DATA/mysql" ]] || mariadb_die "data directory not initialized"
mariadb_port_is_free || mariadb_die "port $MARIADB_PORT is occupied"
if (( require_probe )); then
  mariadb_require_file "$MARIADB_STATE/mariadb-readiness.json"
  python3 - "$MARIADB_STATE/mariadb-readiness.json" "$(sha256sum "$MARIADB_BIN/mariadbd" | awk '{print $1}')" <<'PY'
import datetime as dt, json, sys
from pathlib import Path
p = Path(sys.argv[1]); d = json.loads(p.read_text())
assert d.get("status") == "PASS", "readiness certificate did not pass"
assert d.get("server_sha256") == sys.argv[2], "readiness certificate belongs to another server binary"
assert int(d.get("epoch_count", 0)) >= 2, "readiness certificate has too few epochs"
assert int(d.get("server_observed_statements", 0)) > 0, "readiness certificate has no SQL"
assert int(d.get("successful_llm_requests", 0)) > 0, "readiness certificate has no successful LLM requests"
assert int(d.get("total_tokens", 0)) > 0, "readiness certificate has no token usage"
assert d.get("coverage_monotonic") is True and d.get("checksums_verified") is True
assert Path(d["validation_run"], "COMPLETE").is_file(), "certified NFS run is unavailable"
when = dt.datetime.fromisoformat(d["certified_at"])
age = (dt.datetime.now().astimezone() - when).total_seconds()
assert 0 <= age <= 7 * 24 * 3600, f"readiness certificate is stale ({age:.0f}s)"
PY
fi
printf 'PREFLIGHT_OK mariadb=12.2.2 port=%s gcno=%s sha256=%s\n' "$MARIADB_PORT" "$gcno" "$(sha256sum "$MARIADB_BIN/mariadbd" | awk '{print $1}')"
(( require_probe == 0 )) || echo 'MARIADB_READINESS_CERTIFICATE=PASS'
