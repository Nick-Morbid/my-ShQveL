#!/usr/bin/env bash
set -Eeuo pipefail
trap '' HUP
RUN_ID=${1:?run id required}
EPOCH=${2:-3600}
ROOT=/app/my_ShQveL
LIVE=$ROOT/spool/$RUN_ID/live
REMOTE=/app/nfs/chq_data/ShQveL/mysql/$RUN_ID
PID_FILE=$ROOT/state/$RUN_ID.pid
MYSQL_LOGS=$ROOT/mysql/logs

epoch_done() {
  local n d
  n=$1
  d="$REMOTE/epoch-$(printf '%02d' "$n")"
  mkdir -p "$d/mysql-logs"
  rsync -a --no-owner --no-group --exclude COMPLETE "$LIVE/" "$d/"
  rsync -a --no-owner --no-group "$MYSQL_LOGS/" "$d/mysql-logs/" 2>/dev/null || true
  (cd "$d" && find . -type f ! -name COMPLETE ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
  date --iso-8601=seconds > "$d/COMPLETE"
}

start=$(date +%s)
[[ -d "$REMOTE/epoch-01" && ! -f "$REMOTE/epoch-01/COMPLETE" ]] && start=$((start-EPOCH))
next=1
while true; do
  now=$(date +%s)
  target=$((start + next * EPOCH))
  wait_for=$((target-now)); (( wait_for > 0 )) && sleep "$wait_for" || true
  epoch_done "$next"
  next=$((next+1))
  if [[ ! -f "$PID_FILE" ]] || ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    break
  fi
done

mkdir -p "$REMOTE/final"
rsync -a --no-owner --no-group "$LIVE/" "$REMOTE/final/"
(cd "$REMOTE/final" && find . -type f ! -name COMPLETE ! -name checksums.sha256 -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
date --iso-8601=seconds > "$REMOTE/final/COMPLETE"
