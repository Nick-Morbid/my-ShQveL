#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
[[ $# -eq 1 ]] || tidb_die "usage: $0 SNAPSHOT_DIR"
snapshot="$(readlink -m "$1")"; [[ "$snapshot" == "$SHQVEL_ROOT"/spool/*/coverage-input ]] || tidb_die "snapshot must be run-local"
[[ ! -e "$TIDB_PID_FILE" ]] || tidb_die "TiDB must be gracefully stopped before freezing coverage"
[[ ! -e "$snapshot" ]] || tidb_die "snapshot exists"; tidb_require_dir "$TIDB_COVER"; mkdir -p "$snapshot"
cp -a "$TIDB_COVER/." "$snapshot/"
meta="$(find "$snapshot" -type f -name 'covmeta.*' | wc -l)"; counters="$(find "$snapshot" -type f -name 'covcounters.*' | wc -l)"
(( meta > 0 && counters > 0 )) || tidb_die "incomplete Go coverage snapshot: meta=$meta counters=$counters"
printf 'meta_files=%s\ncounter_files=%s\nfrozen_at=%s\n' "$meta" "$counters" "$(date --iso-8601=ns)" > "$snapshot/manifest.txt"
