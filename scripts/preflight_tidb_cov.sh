#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
tidb_assert_managed_paths; tidb_require_file "$TIDB_BIN"; tidb_require_file "$TIDB_STATE/tidb-cov-build-manifest.json"; tidb_require_file "$TIDB_GO_BIN"
tidb_require_file "$SHQVEL_WORK/target/sqlancer-2.0.0.jar"; tidb_require_file "$SHQVEL_WORK/dbconfigs/tidb-url-8.5.yml"; tidb_require_file "$TIDB_MYSQL_CLIENT"
[[ -L "$SHQVEL_WORK/dbconfigs/llm.properties" ]] || tidb_die "LLM configuration link missing"
python3 - "$TIDB_STATE/tidb-cov-build-manifest.json" "$(sha256sum "$TIDB_BIN" | awk '{print $1}')" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d['tidb_version']=='v8.5.5'; assert d['server_sha256']==sys.argv[2]
assert d['source']=='/app/my_ShQveL/tidb/source'; assert d['install']=='/app/my_ShQveL/tidb/install'
assert d['coverage']=='/app/my_ShQveL/tidb/coverage-runtime'; assert d['covermode']=='atomic'; assert d['coverpkg']=='./...'
PY
tidb_port_is_free "$TIDB_PORT" || tidb_die "SQL port $TIDB_PORT is occupied"; tidb_port_is_free "$TIDB_STATUS_PORT" || tidb_die "status port $TIDB_STATUS_PORT is occupied"
[[ ! -e "$TIDB_PID_FILE" ]] || tidb_die "managed PID file exists"
printf 'PREFLIGHT_OK tidb=v8.5.5 sql_port=%s status_port=%s sha256=%s\n' "$TIDB_PORT" "$TIDB_STATUS_PORT" "$(sha256sum "$TIDB_BIN" | awk '{print $1}')"
