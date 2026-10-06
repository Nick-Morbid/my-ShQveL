#!/usr/bin/env bash
set -Eeuo pipefail
run_id=${1:?run ID required}
root=/app/my_ShQveL
local_dir="$root/spool/$run_id/mysql-sql"
remote_dir="/app/nfs/chq_data/ShQveL/mysql/$run_id/sql"
pid_file="$root/state/$run_id.pid"
client="$root/mysql/install/bin/mysql"
mkdir -p "$local_dir" "$remote_dir"
sql() { "$client" -h127.0.0.1 -P3308 -uroot -p123456 -N -e "$1" >/dev/null 2>&1; }
proc_state() { ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' || true; }
if [[ ! -f "$local_dir/started_at.txt" ]]; then
  sql "SET GLOBAL log_output='FILE'; SET GLOBAL general_log=OFF; SET GLOBAL general_log_file='$local_dir/current.log'; SET GLOBAL general_log=ON;"
  date --iso-8601=seconds > "$local_dir/started_at.txt"
fi
segment=0
elapsed=0
while [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; do
  sleep 30
  elapsed=$((elapsed+30))
  state="$(proc_state "$(<"$pid_file")")"
  [[ -n "$state" && "$state" != Z* && "$state" != X* ]] || break
  (( elapsed >= 600 )) || continue
  elapsed=0
  segment=$((segment+1))
  name=$(printf 'segment-%04d' "$segment")
  if sql 'SET GLOBAL general_log=OFF'; then
    [[ -f "$local_dir/current.log" ]] && mv "$local_dir/current.log" "$local_dir/$name.log"
    sql "SET GLOBAL general_log_file='$local_dir/current.log'; SET GLOBAL general_log=ON;" || true
  fi
  if [[ -f "$local_dir/$name.log" ]]; then
    gzip -c "$local_dir/$name.log" > "$remote_dir/$name.log.gz.part"
    mv "$remote_dir/$name.log.gz.part" "$remote_dir/$name.log.gz"
    sha256sum "$remote_dir/$name.log.gz" > "$remote_dir/$name.log.gz.sha256"
    gzip -t "$remote_dir/$name.log.gz"
    rm "$local_dir/$name.log"
  fi
done
sql 'SET GLOBAL general_log=OFF' || true
if [[ -s "$local_dir/current.log" ]]; then
  gzip -c "$local_dir/current.log" > "$remote_dir/final.log.gz.part"
  mv "$remote_dir/final.log.gz.part" "$remote_dir/final.log.gz"
  sha256sum "$remote_dir/final.log.gz" > "$remote_dir/final.log.gz.sha256"
  gzip -t "$remote_dir/final.log.gz"
fi
date --iso-8601=seconds > "$remote_dir/COMPLETE"
