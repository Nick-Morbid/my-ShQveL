#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/mysql_common.sh"

probe_seconds="${SHQVEL_PROBE_SECONDS:-120}"
[[ "$probe_seconds" =~ ^[1-9][0-9]*$ ]] || mysql_die "SHQVEL_PROBE_SECONDS must be a positive integer"

mysql_assert_managed_paths
"$SHQVEL_ROOT/scripts/preflight_mysql_cov.sh"
mysql_port_is_free || mysql_die "port $MYSQL_PORT is occupied; refusing to probe a different server"
[[ ! -f "$MYSQL_DATA/mysqld.pid" ]] || mysql_die "stale/live PID file exists; inspect it before probing"

stamp="$(date +%Y%m%dT%H%M%S%z)"
out="$SHQVEL_ROOT/validation/mysql-coverage-probe-$stamp"
snapshot_root="$SHQVEL_ROOT/spool/mysql-coverage-probe-$stamp"
snapshot="$snapshot_root/coverage-input"
mkdir -p "$out" "$MYSQL_STATE"
server_sha="$(sha256sum "$MYSQL_BIN/mysqld" | awk '{print $1}')"
server_pid=""
probe_status=FAIL

finish_probe() {
  rc=$?
  trap - EXIT
  if [[ -n "$server_pid" ]] && mysql_pid_running "$server_pid"; then
    mysql_admin shutdown >> "$out/shutdown.log" 2>&1 || true
    for _ in {1..30}; do
      mysql_pid_running "$server_pid" || break
      sleep 1
    done
  fi
  if [[ -f "$MYSQL_DATA/mysqld.pid" ]]; then
    pid="$(<"$MYSQL_DATA/mysqld.pid")"
    if mysql_pid_running "$pid"; then
      printf 'ERROR: isolated server PID %s did not stop cleanly; not killing it broadly\n' "$pid" >&2
      rc=1
    fi
  fi
  # Frozen gcov input is only an intermediate hard-link/counter snapshot.  The
  # durable raw traces and logs live in the validation directory and on NFS.
  [[ ! -e "$snapshot_root" ]] || find "$snapshot_root" -xdev -depth -delete 2>/dev/null || true
  if (( rc == 0 )) && [[ "$probe_status" == PASS ]]; then
    printf '{"status":"PASS","checked_at":"%s","server_sha256":"%s","port":%s,"data":"%s","validation_dir":"%s"}\n' \
      "$(date --iso-8601=seconds)" "$server_sha" "$MYSQL_PORT" "$MYSQL_DATA" "$out" > "$MYSQL_STATE/mysql-cov-probe.json"
    event_file="$out/java-llm-events.jsonl"
    if [[ -s "$event_file" ]] && python3 - "$event_file" "$out/shqvel.stdout.log" "$out/learned-fragments.json" "$MYSQL_STATE/mysql-learning-probe.json" <<'PY'
import json, re, sys
from pathlib import Path
events = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines() if line.strip()]
successful = [event for event in events
              if event.get("kind") == "fragment_synthesis"
              and event.get("response", {}).get("choices", [{}])[0].get("message", {}).get("content", "").strip()]
log = Path(sys.argv[2]).read_text(errors="replace")
validated = len(re.findall(r"^Fragment .+ is supported$", log, flags=re.MULTILINE))
assert successful, "no successful Java fragment-synthesis response was recorded"
assert validated > 0, "no learned fragment was accepted by direct validation on the target DBMS"
checkpoint_path = Path(sys.argv[3])
checkpoint = None
if checkpoint_path.is_file():
    fragments = json.loads(checkpoint_path.read_text())
    assert isinstance(fragments, dict) and fragments, "learned-fragments checkpoint is empty"
    checkpoint = str(checkpoint_path)
Path(sys.argv[4]).write_text(json.dumps({
    "status": "PASS",
    "checked_at": __import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds"),
    "server_sha256": __import__("os").environ.get("MYSQL_SERVER_SHA256", ""),
    "event_count": len(successful),
    "validated_fragment_count": validated,
    "checkpoint": checkpoint,
    "validation_dir": str(Path(sys.argv[2]).parent),
    "evidence": "successful_fragment_synthesis_and_target_dbms_validation"
}, indent=2) + "\n")
PY
    then
      python3 - "$MYSQL_STATE/mysql-learning-probe.json" "$server_sha" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
d = json.loads(p.read_text())
d["server_sha256"] = sys.argv[2]
p.write_text(json.dumps(d, indent=2) + "\n")
PY
    else
      reason='no successful fragment synthesis and target-DBMS validation evidence'
      if rg -q '429.*(余额不足|无可用资源包)' "$out/shqvel.stdout.log"; then
        reason='provider returned HTTP 429: insufficient balance or no available quota'
      fi
      printf '{"status":"FAIL","checked_at":"%s","reason":"%s","validation_dir":"%s"}\n' \
        "$(date --iso-8601=seconds)" "$reason" "$out" > "$MYSQL_STATE/mysql-learning-probe.json"
    fi
    (cd "$out" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
    printf '%s\n' "$(date --iso-8601=seconds)" > "$out/COMPLETE"
    remote="/app/nfs/chq_data/ShQveL/mysql/harness-validation/$(basename "$out")"
    if mountpoint -q /app/nfs/chq_data && [[ ! -e "$remote" ]]; then
      mkdir -p "$(dirname "$remote")"
      rsync -a --no-owner --no-group "$out/" "$remote/"
      (cd "$remote" && sha256sum -c checksums.sha256 > checksum-verification.txt)
      date --iso-8601=seconds > "$remote/COMPLETE"
    else
      printf 'WARNING: NFS probe artifact upload skipped (mount missing or destination exists)\n' >&2
    fi
    learning_status="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status", "FAIL"))' "$MYSQL_STATE/mysql-learning-probe.json")"
    printf 'MYSQL_COVERAGE_PROBE=PASS\nMYSQL_LEARNING_PROBE=%s\n' "$learning_status"
  else
    printf '{"status":"FAIL","checked_at":"%s","server_sha256":"%s","validation_dir":"%s","exit_code":%s}\n' \
      "$(date --iso-8601=seconds)" "$server_sha" "$out" "$rc" > "$out/FAILED"
    rm -f "$MYSQL_STATE/mysql-cov-probe.json"
    rm -f "$MYSQL_STATE/mysql-learning-probe.json"
    printf 'MYSQL_COVERAGE_PROBE=FAIL; inspect %s\n' "$out" >&2
  fi
  exit "$rc"
}
trap finish_probe EXIT

# Reset only runtime counters belonging to this Harness-owned build tree.
find "$MYSQL_BUILD" -type f -name '*.gcda' -delete

"$MYSQL_BIN/mysqld" \
  --basedir="$MYSQL_INSTALL" --datadir="$MYSQL_DATA" \
  --socket="$MYSQL_SOCKET" --port="$MYSQL_PORT" --bind-address=127.0.0.1 \
  --pid-file="$MYSQL_DATA/mysqld.pid" --user=root \
  --log-error="$out/mysql-error.log" --daemonize

for _ in {1..60}; do
  if mysql_admin ping >/dev/null 2>&1; then break; fi
  sleep 1
done
mysql_admin ping > "$out/mysql-ping.txt" 2>&1 || mysql_die "coverage MySQL did not become ready"
server_pid="$(<"$MYSQL_DATA/mysqld.pid")"
[[ "$server_pid" =~ ^[0-9]+$ ]] || mysql_die "invalid managed mysqld PID"
exe="$(readlink -f "/proc/$server_pid/exe")"
[[ "$exe" == "$(readlink -f "$MYSQL_BIN/mysqld")" ]] || mysql_die "live server executable is not the instrumented Harness binary: $exe"

mysql_client -N -e 'SELECT @@port, @@basedir, @@datadir, VERSION()' > "$out/server-identity.tsv"
grep -q $'^3308\t' "$out/server-identity.tsv" || mysql_die "live server reports a different port"
grep -Fq "$MYSQL_INSTALL" "$out/server-identity.tsv" || mysql_die "live server reports a different basedir"
grep -Fq "$MYSQL_DATA" "$out/server-identity.tsv" || mysql_die "live server reports a different datadir"
mysql_client -e "SET GLOBAL log_output='FILE'; SET GLOBAL general_log_file='$out/mysql-general.log'; SET GLOBAL general_log=ON;" \
  > "$out/general-log-enable.log" 2>&1
mysql_client -e 'CREATE DATABASE IF NOT EXISTS test;' > "$out/create-test-database.log" 2>&1
mysql_client --database=test -e 'CREATE TEMPORARY TABLE shqvel_cov_probe (v INT); INSERT INTO shqvel_cov_probe VALUES (2),(3); SELECT SUM(v) FROM shqvel_cov_probe; DROP TEMPORARY TABLE shqvel_cov_probe;' \
  > "$out/direct-sql-smoke.log" 2>&1

source /usr/local/miniconda3/etc/profile.d/conda.sh
conda activate shqvel
export SQLANCER_MYSQL_HOST=127.0.0.1 SQLANCER_MYSQL_PORT="$MYSQL_PORT" \
  SQLANCER_MYSQL_USER="$MYSQL_USER" SQLANCER_MYSQL_PASSWORD="$MYSQL_PASSWORD" SQLANCER_MYSQL_DATABASE=test
export SHQVEL_PYTHON_LLM_EVENT_LOG="$out/python-llm-events.jsonl"
export SHQVEL_JAVA_LLM_EVENT_LOG="$out/java-llm-events.jsonl"
export JAVA_TOOL_OPTIONS='-Xms1g -Xmx4g -XX:+UseG1GC'
cd "$SHQVEL_WORK"
set +e
timeout --signal=INT --kill-after=30 "$probe_seconds" java -jar target/sqlancer-2.0.0.jar \
  --enable-extra-features --enable-learning --num-threads 1 --num-tries 1000000 \
  --num-queries 100000 --log-each-select true --log-execution-time true general \
  --database-engine mysql --documentation-yaml mysql-url-8.4.yml \
  --configured-datatypes-only true --enable-function-overview-learning false \
  --enable-statement-learning false --enable-datatype-learning true \
  --enable-expression-learning true --enable-clause-learning false \
  --enable-direct-validation true --learning-interval-seconds 60 --oracle FUZZING \
  --save-learned-fragments "$out/learned-fragments.json" \
  > "$out/shqvel.stdout.log" 2>&1
shqvel_rc=$?
set -e
printf '%s\n' "$shqvel_rc" > "$out/shqvel-exit-status.txt"
[[ "$shqvel_rc" -eq 0 || "$shqvel_rc" -eq 124 || "$shqvel_rc" -eq 130 ]] || mysql_die "ShQveL smoke exited unexpectedly: $shqvel_rc"
grep -Eq 'Executed [1-9][0-9]* queries' "$out/shqvel.stdout.log" || mysql_die "ShQveL did not report executing any queries"

mysql_client -e 'SET GLOBAL general_log=OFF' > "$out/general-log-disable.log" 2>&1
mysql_admin shutdown > "$out/shutdown.log" 2>&1
for _ in {1..60}; do
  mysql_pid_running "$server_pid" || break
  sleep 1
done
mysql_pid_running "$server_pid" && mysql_die "managed mysqld did not exit after graceful shutdown"
server_pid=""

gcda_count="$(find "$MYSQL_BUILD" -type f -name '*.gcda' | wc -l)"
(( gcda_count > 0 )) || mysql_die "instrumented server produced no .gcda files after graceful shutdown"
grep -Eiq 'select|create|insert|drop' "$out/mysql-general.log" || mysql_die "MySQL general log did not capture SQL"

"$SHQVEL_ROOT/scripts/prepare_mysql_coverage_template.sh"
mkdir -p "$snapshot_root"
"$SHQVEL_ROOT/scripts/freeze_mysql_coverage.sh" "$snapshot"
"$SHQVEL_ROOT/scripts/collect_mysql_coverage.sh" "$snapshot" "$out/coverage"
grep -q '^SF:' "$out/coverage/raw-full.info" || mysql_die "lcov tracefile contains no source records"
grep -Eq '^SF:.*/(sql|storage|include)/' "$out/coverage/raw.info" || mysql_die "no SQL/storage/include source records were extracted"
gzip -t "$out/coverage/raw-full.info.gz" "$out/coverage/raw.info.gz"
printf 'server_sha256=%s\ngcda_count=%s\nshqvel_exit=%s\n' \
  "$server_sha" "$gcda_count" "$shqvel_rc" > "$out/validation-summary.txt"
(cd "$out" && find . -type f ! -name checksums.sha256 ! -name COMPLETE -print0 | sort -z | xargs -0 sha256sum > checksums.sha256)
probe_status=PASS
