import subprocess
import argparse
import os
import signal
import time
import re

CURRENT_DATE = time.strftime("r%m%d", time.localtime())
CURRENT_DIR = os.path.dirname(os.path.realpath(__file__))

FUZZER = "java -jar target/sqlancer-2.0.0.jar --num-threads 4 --num-tries 4 --canonicalize-sql-strings false  --num-statement-kind-retries 10 --use-reducer --reduce-ast general --oracle {} --database-engine {}"

SUPPORT_DBMS = [
    "mysql",
    "postgresql",
    "crate",
    "dolt",
    "cockroachdb",
    "tidb",
    "umbra",
    "mariadb",
    "duckdb",
    "sqlite",
    "risingwave",
    "percona",
    "virtuoso",
    "monetdb",
]


def start_server(dbms: str, tag: str = "latest"):
    # mkdir -p logs/server
    os.makedirs(f"{CURRENT_DIR}/../logs/server", exist_ok=True)
    # Start the server using ./start_dbms.sh
    with open(f"{CURRENT_DIR}/../logs/server/{dbms}.log", "w") as f:
        proc = subprocess.Popen(
            [f"{CURRENT_DIR}/start_dbms.sh", dbms, tag],
            stdout=f,
            stderr=f,
            preexec_fn=os.setsid,
        )
    time.sleep(10)
    return proc


def start_fuzz(dbms: str, oracle:str, timeout: int = 60):
    # mkdir -p logs/routine
    os.makedirs(f"{CURRENT_DIR}/../logs/routine", exist_ok=True)
    # Start the fuzzing program
    with open(f"{CURRENT_DIR}/../logs/routine/{dbms}.log", "w") as f:
        cmd = FUZZER.format(oracle, dbms).split()
        proc = subprocess.Popen(cmd, stdout=f, stderr=f)
    try:
        proc.wait(timeout=timeout)
        code = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        code = 1
    else:
        proc.kill()
    return code


def build_server(dbms: str):
    output = subprocess.run(
        [f"{CURRENT_DIR}/build_dbms.sh", dbms],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return output.stdout.decode("utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dbms", type=str, default="all")
    parser.add_argument("--cache", action="store_true", default=False)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--oracle", type=str, default="WHERE")
    args = parser.parse_args()
    if args.dbms != "all":
        SUPPORT_DBMS = [args.dbms]
    bug_dbms = []
    for dbms in SUPPORT_DBMS:
        print("Building", dbms)
        output = build_server(dbms)
        print(output)
        if output.find("Image is up to date") != -1 and not args.cache:
            continue
        print("Starting", dbms, flush=True)
        proc = start_server(dbms)
        print("Testing", dbms)
        code = start_fuzz(dbms, args.oracle, args.timeout)
        print("Do some cleaning")
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        os.system(f"docker stop {dbms}-test")
        print("Exit code:", code)

        general_logs = os.listdir(f"{CURRENT_DIR}/../logs/general")
        if code != 1 or any([re.match(r"database[0-4]\.log", f) for f in general_logs]):
            # move all logs to logs/bugs/$cur_date
            bugs_dir = f"{CURRENT_DIR}/../logs/bugs/{dbms}/{CURRENT_DATE}"
            os.makedirs(
                bugs_dir, exist_ok=True
            )
            # clean the logs
            os.system(f"rm {bugs_dir}/*.log")
            os.system(
                f"cp {CURRENT_DIR}/../logs/general/*.log {bugs_dir}"
            )
            log_files = os.listdir(bugs_dir)
            if all([f.find("-cur") != -1 for f in log_files]):
                print("WARNING: No logs saved. Please check the server log.")
            bug_dbms.append(dbms)

    if len(bug_dbms) == 0:
        print("No bugs found.")
    else:
        print("Bugs found in", bug_dbms)
        print(f"Please check the logs in logs/bugs/$DBMS/{CURRENT_DATE}")
