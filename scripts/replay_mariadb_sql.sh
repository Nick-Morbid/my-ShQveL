#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mariadb_common.sh"
[[ $# -eq 2 ]] || mariadb_die "usage: $0 REPLAY_SQL[.gz] OUTPUT_DIR"
input="$(readlink -m "$1")"; out="$(readlink -m "$2")"; mariadb_require_file "$input"; mkdir -p "$out"
mariadb_verify_running > "$out/server-identity.txt"
timeout_seconds="${MARIADB_REPLAY_TIMEOUT_SECONDS:-21600}"; statement_seconds="${MARIADB_REPLAY_STATEMENT_SECONDS:-5}"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ && "$statement_seconds" =~ ^[1-9][0-9]*$ ]] || mariadb_die "replay timeouts must be positive integers"
marker="replay_$(date +%s)_$$"; started="$(date --iso-8601=ns)"; start_ns="$(date +%s%N)"
mariadb_client -e 'CREATE DATABASE IF NOT EXISTS shqvel_replay_control; CREATE TABLE IF NOT EXISTS shqvel_replay_control.completed_markers (marker VARCHAR(128) PRIMARY KEY, completed_at TIMESTAMP(6));'
set +e
{
  if [[ "$input" == *.gz ]]; then gzip -cd "$input"; else sed -n '1,$p' "$input"; fi
  printf "CREATE DATABASE IF NOT EXISTS shqvel_replay_control;\n"
  printf "CREATE TABLE IF NOT EXISTS shqvel_replay_control.completed_markers (marker VARCHAR(128) PRIMARY KEY, completed_at TIMESTAMP(6));\n"
  printf "REPLACE INTO shqvel_replay_control.completed_markers VALUES ('%s', CURRENT_TIMESTAMP(6));\n" "$marker"
} | timeout --signal=TERM --kill-after=30 "$timeout_seconds" env MYSQL_PWD="$MARIADB_PASSWORD" \
    "$MARIADB_BIN/mariadb" --force --protocol=tcp -h 127.0.0.1 -P "$MARIADB_PORT" -u "$MARIADB_USER" \
    --init-command="SET SESSION max_statement_time=$statement_seconds" test \
    > /dev/null 2> "$out/client.stderr"
statuses=("${PIPESTATUS[@]}"); client_rc="${statuses[1]}"
set -e
[[ "$client_rc" -ne 124 && "$client_rc" -ne 137 ]] || mariadb_die "replay exceeded ${timeout_seconds}s"
observed="$(mariadb_client -N -e "SELECT COUNT(*) FROM shqvel_replay_control.completed_markers WHERE marker='$marker'")"
[[ "$observed" == 1 ]] || mariadb_die "replay client did not reach end-of-file marker"
error_count="$(rg -c '^ERROR ' "$out/client.stderr" 2>/dev/null || true)"; error_count="${error_count:-0}"
gzip -9 "$out/client.stderr"
end_ns="$(date +%s%N)"
printf '{"status":"PASS","started_at":"%s","completed_at":"%s","elapsed_seconds":%s,"input":"%s","input_sha256":"%s","client_exit_with_expected_errors":%s,"error_count":%s,"statement_timeout_seconds":%s,"overall_timeout_seconds":%s,"eof_marker":"%s"}\n' \
  "$started" "$(date --iso-8601=ns)" "$(((end_ns-start_ns)/1000000000))" "$input" "$(sha256sum "$input" | awk '{print $1}')" "$client_rc" "$error_count" "$statement_seconds" "$timeout_seconds" "$marker" > "$out/replay-result.json"
printf 'MARIADB_REPLAY=PASS elapsed_seconds=%s expected_errors=%s client_exit=%s\n' "$(((end_ns-start_ns)/1000000000))" "$error_count" "$client_rc"
