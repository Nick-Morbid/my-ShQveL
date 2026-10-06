#!/usr/bin/env bash
set -Eeuo pipefail
run_id=${1:?run ID required}
root=/app/my_ShQveL
live="$root/spool/$run_id/live"
pid_file="$root/state/$run_id.pid"
mysql_bin="$root/mysql/install/bin"
error_log="$root/mysql/logs/error.log"
mkdir -p "$live/mysql-crashes"
while [[ -f "$pid_file" ]] && kill -0 "$(<"$pid_file")" 2>/dev/null; do
  if ! "$mysql_bin/mysqladmin" -h127.0.0.1 -P3308 -uroot -p123456 ping >/dev/null 2>&1; then
    stamp=$(date +%Y%m%dT%H%M%S%z)
    cp "$error_log" "$live/mysql-crashes/error-$stamp.log" || true
    printf '%s mysql 3308 unavailable; restarting isolated instance\n' "$(date --iso-8601=seconds)" >> "$live/mysql-watchdog.log"
    "$mysql_bin/mysqld" \
      --basedir="$root/mysql/install" --datadir="$root/mysql/data" \
      --socket="$root/mysql/mysql.sock" --port=3308 --bind-address=127.0.0.1 \
      --pid-file="$root/mysql/data/mysqld.pid" --user=root \
      --log-error="$error_log" --daemonize >> "$live/mysql-watchdog.log" 2>&1 || true
    if [[ -d "$root/spool/$run_id/mysql-sql" ]]; then
      "$mysql_bin/mysql" -h127.0.0.1 -P3308 -uroot -p123456 -e \
        "SET GLOBAL log_output='FILE'; SET GLOBAL general_log_file='$root/spool/$run_id/mysql-sql/current.log'; SET GLOBAL general_log=ON;" \
        >> "$live/mysql-watchdog.log" 2>&1 || true
    fi
  fi
  sleep 30
done
