#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
[[ $# -eq 1 ]] || die "usage: $0 OUTPUT_DIR"
OUTPUT_DIR="$(readlink -m "$1")"
mkdir -p "$OUTPUT_DIR"
RAW_FULL="$OUTPUT_DIR/raw-full.info"
RAW="$OUTPUT_DIR/raw.info"
STARTED_AT="$(date --iso-8601=ns)"
START_NS="$(date +%s%N)"

capture_ok=false
for attempt in 1 2 3; do
  printf 'capture_attempt=%s\n' "$attempt" >> "$OUTPUT_DIR/collect.log"
  if lcov --capture --directory "$PG_SOURCE" --output-file "$RAW_FULL" \
      --rc "$LCOV_BRANCH_RC" >> "$OUTPUT_DIR/collect.log" 2>&1; then
    capture_ok=true
    break
  fi
  sleep 2
done
[[ "$capture_ok" == true ]] || die "lcov capture failed after 3 attempts"
lcov --extract "$RAW_FULL" "$PG_SOURCE/*" --output-file "$RAW" \
  --rc "$LCOV_BRANCH_RC" >> "$OUTPUT_DIR/collect.log" 2>&1
lcov --summary "$RAW" --rc "$LCOV_BRANCH_RC" > "$OUTPUT_DIR/summary.txt" 2>&1
genhtml "$RAW" --output-directory "$OUTPUT_DIR/html" --branch-coverage --function-coverage \
  > "$OUTPUT_DIR/genhtml.log" 2>&1
cp "$OUTPUT_DIR/html/index.html" "$OUTPUT_DIR/index.html"
find "$OUTPUT_DIR/html" -depth -delete
zstd -q -f -T0 "$RAW_FULL" -o "$RAW_FULL.zst"
zstd -q -f -T0 "$RAW" -o "$RAW.zst"
(cd "$OUTPUT_DIR" && sha256sum raw-full.info raw-full.info.zst raw.info raw.info.zst summary.txt index.html \
  > checksums.sha256)
END_NS="$(date +%s%N)"
cat > "$OUTPUT_DIR/timing.json" <<EOF
{"started_at":"$STARTED_AT","completed_at":"$(date --iso-8601=ns)","elapsed_seconds":$(( (END_NS - START_NS) / 1000000000 ))}
EOF
