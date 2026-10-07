#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
[[ $# -eq 1 ]] || mariadb_die "usage: $0 SNAPSHOT_DIR"
snapshot="$(readlink -m "$1")"
[[ "$snapshot" == "$SHQVEL_ROOT"/spool/*/coverage-input ]] || mariadb_die "snapshot must be run-local"
[[ ! -e "$snapshot" ]] || mariadb_die "snapshot exists"
mariadb_require_file "$MARIADB_COVERAGE_TEMPLATE/manifest.txt"
cp -al "$MARIADB_COVERAGE_TEMPLATE" "$snapshot"
(cd "$MARIADB_BUILD" && find . -type f -name '*.gcda' -print0 | tar --null -T - -cf -) | (cd "$snapshot" && tar -xf -)
gcno="$(find "$snapshot" -type f -name '*.gcno' | wc -l)"; gcda="$(find "$snapshot" -type f -name '*.gcda' | wc -l)"
(( gcno > 500 && gcda > 0 )) || mariadb_die "incomplete frozen input: gcno=$gcno gcda=$gcda"
printf 'gcno_count=%s\ngcda_count=%s\nfrozen_at=%s\n' "$gcno" "$gcda" "$(date --iso-8601=ns)" > "$snapshot/manifest.txt"
