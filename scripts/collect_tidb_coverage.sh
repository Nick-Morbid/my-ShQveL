#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/tidb_common.sh"
[[ $# -eq 2 ]] || tidb_die "usage: $0 FROZEN_INPUT OUTPUT_DIR"
input="$(readlink -m "$1")"; out="$(readlink -m "$2")"; tidb_require_dir "$input"; mkdir -p "$out/merged"
meta="$(find "$input" -type f -name 'covmeta.*' | wc -l)"; counters="$(find "$input" -type f -name 'covcounters.*' | wc -l)"; (( meta > 0 && counters > 0 )) || tidb_die "empty covdata input"
tidb_go tool covdata merge -i="$input" -o="$out/merged" > "$out/collect.log" 2>&1
tidb_go tool covdata textfmt -i="$out/merged" -o="$out/raw.out" >> "$out/collect.log" 2>&1
tidb_go tool covdata percent -i="$out/merged" > "$out/summary.txt" 2>> "$out/collect.log"
tidb_go tool cover -func="$out/raw.out" > "$out/functions.txt" 2>> "$out/collect.log"
grep -q '^mode: atomic' "$out/raw.out" || tidb_die "coverage profile is missing atomic mode"
tar -C "$input" -czf "$out/covdata.raw.tar.gz" .
tar -C "$out/merged" -czf "$out/covdata.merged.tar.gz" .
gzip -9 -c "$out/raw.out" > "$out/raw.out.gz"; gzip -t "$out/covdata.raw.tar.gz" "$out/covdata.merged.tar.gz" "$out/raw.out.gz"
printf '{"captured_at":"%s","meta_files":%s,"counter_files":%s}\n' "$(date --iso-8601=ns)" "$meta" "$counters" > "$out/timing.json"
printf 'TIDB_COVERAGE_CAPTURE_OK meta=%s counters=%s\n' "$meta" "$counters"
