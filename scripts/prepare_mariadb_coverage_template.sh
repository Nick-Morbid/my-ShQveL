#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
mariadb_assert_managed_paths
expected="$(find "$MARIADB_BUILD" -type f -name '*.gcno' | wc -l)"; (( expected > 500 )) || mariadb_die "too few gcno files"
server_sha="$(sha256sum "$MARIADB_BIN/mariadbd" | awk '{print $1}')"
if [[ -f "$MARIADB_COVERAGE_TEMPLATE/manifest.txt" ]]; then
  actual="$(find "$MARIADB_COVERAGE_TEMPLATE" -type f -name '*.gcno' | wc -l)"
  template_sha="$(sed -n 's/^server_sha256=//p' "$MARIADB_COVERAGE_TEMPLATE/manifest.txt")"
  [[ "$actual" == "$expected" && "$template_sha" == "$server_sha" ]] && exit 0
fi
tmp="$MARIADB_ROOT/.coverage-template.preparing"; [[ ! -e "$tmp" ]] || find "$tmp" -xdev -depth -delete
mkdir -p "$tmp"
(cd "$MARIADB_BUILD" && find . -type f -name '*.gcno' -print0 | tar --null -T - -cf -) | (cd "$tmp" && tar -xf -)
actual="$(find "$tmp" -type f -name '*.gcno' | wc -l)"; [[ "$actual" == "$expected" ]] || mariadb_die "incomplete template"
printf 'gcno_count=%s\nprepared_at=%s\nbuild=%s\nserver_sha256=%s\n' "$actual" "$(date --iso-8601=ns)" "$MARIADB_BUILD" "$server_sha" > "$tmp/manifest.txt"
[[ ! -e "$MARIADB_COVERAGE_TEMPLATE" ]] || find "$MARIADB_COVERAGE_TEMPLATE" -xdev -depth -delete
mv "$tmp" "$MARIADB_COVERAGE_TEMPLATE"
