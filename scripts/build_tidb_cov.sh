#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
tidb_assert_managed_paths
tidb_assert_no_active_mariadb_experiment
mkdir -p "$TIDB_ROOT" "$TIDB_INSTALL/bin" "$TIDB_LOG_DIR" "$TIDB_STATE" "$TIDB_GO_PATH" "$TIDB_GO_CACHE"
tidb_port_is_free "$TIDB_PORT" || tidb_die "SQL port $TIDB_PORT is occupied"
tidb_port_is_free "$TIDB_STATUS_PORT" || tidb_die "status port $TIDB_STATUS_PORT is occupied"
[[ ! -e "$TIDB_PID_FILE" ]] || tidb_die "managed PID file exists"
if [[ ! -x "$TIDB_GO_BIN" ]]; then
  archive="$TIDB_ROOT/go1.25.5.linux-amd64.tar.gz"
  [[ -f "$archive" ]] || curl -fL --retry 3 -o "$archive" https://go.dev/dl/go1.25.5.linux-amd64.tar.gz
  mkdir -p "$TIDB_ROOT/toolchain"; tar -xzf "$archive" -C "$TIDB_ROOT/toolchain"
fi
[[ "$(tidb_go version)" == 'go version go1.25.5 linux/amd64' ]] || tidb_die "unexpected Go toolchain"
if [[ ! -f "$TIDB_SOURCE/go.mod" ]]; then
  git clone --branch v8.5.5 --depth 1 https://github.com/pingcap/tidb.git "$TIDB_SOURCE"
fi
[[ "$(git -C "$TIDB_SOURCE" describe --tags --exact-match 2>/dev/null)" == v8.5.5 ]] || tidb_die "source is not exact v8.5.5 tag"
export GOPROXY="${TIDB_GOPROXY:-https://proxy.golang.org,direct}"
jobs="${TIDB_BUILD_JOBS:-4}"; [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || tidb_die "invalid build job count"
(cd "$TIDB_SOURCE" && GOMAXPROCS="$jobs" tidb_go build -cover -covermode=atomic -coverpkg=./... -o "$TIDB_BIN" ./cmd/tidb-server) 2>&1 | tee "$TIDB_LOG_DIR/build.log"
tidb_require_file "$TIDB_BIN"; "$TIDB_BIN" -V > "$TIDB_LOG_DIR/version.txt" 2>&1 || true
go_version="$(tidb_go version)"; server_sha="$(sha256sum "$TIDB_BIN" | awk '{print $1}')"
printf '{"built_at":"%s","tidb_version":"v8.5.5","source":"%s","install":"%s","data":"%s","coverage":"%s","sql_port":%s,"status_port":%s,"server_sha256":"%s","go_version":"%s","covermode":"atomic","coverpkg":"./..."}\n' \
  "$(date --iso-8601=seconds)" "$TIDB_SOURCE" "$TIDB_INSTALL" "$TIDB_DATA" "$TIDB_COVER" "$TIDB_PORT" "$TIDB_STATUS_PORT" "$server_sha" "$go_version" > "$TIDB_STATE/tidb-cov-build-manifest.json"
printf 'TIDB_COVERAGE_BUILD_OK sha256=%s\n' "$server_sha"
