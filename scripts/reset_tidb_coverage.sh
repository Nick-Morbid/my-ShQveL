#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
tidb_assert_managed_paths; [[ ! -e "$TIDB_PID_FILE" ]] || tidb_die "stop managed TiDB before reset"
[[ ! -e "$TIDB_COVER" ]] || find "$TIDB_COVER" -mindepth 1 -xdev -depth -delete
mkdir -p "$TIDB_COVER"; printf 'TIDB_COVERAGE_RESET_OK\n'
