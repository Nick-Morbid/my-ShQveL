#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
mariadb_assert_managed_paths
[[ ! -e "$MARIADB_PID_FILE" ]] || mariadb_die "stop the managed server before resetting coverage"
find "$MARIADB_BUILD" -type f \( -name '*.gcda' -o -name '*.gcov' \) -delete
printf 'MARIADB_COVERAGE_RESET_OK\n'
