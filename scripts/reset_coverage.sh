#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
require_dir "$PG_SOURCE"
find "$PG_SOURCE" -type f \( -name '*.gcda' -o -name '*.gcov' \) -delete
lcov --directory "$PG_SOURCE" --zerocounters --rc "$LCOV_BRANCH_RC" 2>&1 | tee "$LOG_DIR/reset-coverage.log"

