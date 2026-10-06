#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

mysql_assert_managed_paths
expected="$(find "$MYSQL_BUILD" -type f -name '*.gcno' | wc -l)"
server_sha="$(sha256sum "$MYSQL_BIN/mysqld" | awk '{print $1}')"
(( expected > 1000 )) || mysql_die "too few gcno files in MySQL build: $expected"
if [[ -f "$MYSQL_COVERAGE_TEMPLATE/manifest.txt" ]]; then
  actual="$(find "$MYSQL_COVERAGE_TEMPLATE" -type f -name '*.gcno' | wc -l)"
  template_sha="$(sed -n 's/^server_sha256=//p' "$MYSQL_COVERAGE_TEMPLATE/manifest.txt")"
  [[ "$actual" == "$expected" && "$template_sha" == "$server_sha" ]] && exit 0
fi
tmp="$MYSQL_ROOT/.coverage-template.preparing"
[[ ! -e "$tmp" ]] || find "$tmp" -xdev -depth -delete
mkdir -p "$tmp"
(cd "$MYSQL_BUILD" && find . -type f -name '*.gcno' -print0 | tar --null -T - -cf -) | \
  (cd "$tmp" && tar -xf -)
actual="$(find "$tmp" -type f -name '*.gcno' | wc -l)"
[[ "$actual" == "$expected" ]] || mysql_die "coverage template is incomplete: $actual of $expected"
printf 'gcno_count=%s\nprepared_at=%s\nbuild=%s\nserver_sha256=%s\n' "$actual" "$(date --iso-8601=ns)" "$MYSQL_BUILD" "$server_sha" > "$tmp/manifest.txt"
[[ ! -e "$MYSQL_COVERAGE_TEMPLATE" ]] || find "$MYSQL_COVERAGE_TEMPLATE" -xdev -depth -delete
mv "$tmp" "$MYSQL_COVERAGE_TEMPLATE"
