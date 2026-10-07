#!/usr/bin/env python3
"""Certify a completed multi-epoch MariaDB Harness validation run."""
import argparse
import datetime as dt
import gzip
import hashlib
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--run", required=True)
p.add_argument("--server", required=True)
p.add_argument("--output", required=True)
a = p.parse_args()
run = Path(a.run).resolve()
server = Path(a.server).resolve()
assert str(run).startswith("/app/nfs/chq_data/ShQveL/mariadb/"), "validation run is outside MariaDB NFS root"
assert (run / "COMPLETE").is_file(), "run has no top-level COMPLETE"
epochs = sorted(x for x in run.glob("epoch-*") if x.is_dir())
assert len(epochs) >= 2, "at least two completed epochs are required"
assert (run / "final-artifacts" / "COMPLETE").is_file(), "final artifacts are incomplete"

def verify_checksums(root: Path):
    manifest = root / "checksums.sha256"
    assert manifest.is_file(), f"missing checksum manifest: {root}"
    for line in manifest.read_text().splitlines():
        expected, relative = line.split(maxsplit=1)
        target = root / relative.lstrip("* ")
        assert target.is_file(), f"missing checksummed file: {target}"
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        assert actual == expected, f"checksum mismatch: {target}"

def coverage(root: Path):
    text = (root / "coverage" / "summary.txt").read_text()
    values = {}
    for name in ("lines", "functions", "branches"):
        m = re.search(rf"{name}\.+:\s+([0-9.]+)%\s+\((\d+) of (\d+)", text)
        assert m, f"missing {name} coverage in {root}"
        values[name] = {"percent": float(m.group(1)), "hit": int(m.group(2)), "total": int(m.group(3))}
    return values

previous = None
total_llm = total_tokens = total_sql = 0
details = []
for epoch in epochs:
    assert (epoch / "COMPLETE").is_file(), f"incomplete epoch: {epoch.name}"
    verify_checksums(epoch)
    for required in ("raw.info", "raw-full.info", "raw.info.gz", "raw-full.info.gz"):
        assert (epoch / "coverage" / required).is_file(), f"missing coverage artifact: {epoch.name}/{required}"
    metrics = json.loads((epoch / "metrics.json").read_text())
    summary = json.loads((epoch / "sql" / "mysql-general-summary.json").read_text())
    sql_count = int(summary.get("server_observed_statements") or 0)
    assert sql_count > 0, f"no server-observed SQL in {epoch.name}"
    replay_path = epoch / "sql" / "replay.sql.gz"
    assert replay_path.stat().st_size > 0, f"empty replay in {epoch.name}"
    replay_events = leaked_headers = 0
    with gzip.open(replay_path, "rt", errors="replace") as stream:
        for line in stream:
            replay_events += bool(re.match(r"^-- .* command=(Query|Execute|Prepare)", line))
            leaked_headers += bool(re.match(r"^\d{6} .*\b(Connect|Quit|Query)\b", line))
    assert replay_events == sql_count, f"replay event count differs from general log in {epoch.name}"
    assert leaked_headers == 0, f"raw MariaDB log headers leaked into replay in {epoch.name}"
    cov = coverage(epoch)
    if previous is not None:
        for name in cov:
            assert cov[name]["hit"] >= previous[name]["hit"], f"{name} coverage regressed in {epoch.name}"
            assert cov[name]["total"] == previous[name]["total"], f"{name} denominator changed in {epoch.name}"
    previous = cov
    total_llm += int(metrics.get("successful_llm_requests") or 0)
    total_tokens += int(metrics.get("total_tokens") or 0)
    total_sql += sql_count
    details.append({"epoch": epoch.name, "sql": sql_count, "replay_events": replay_events, "coverage": cov, "metrics": metrics})

verify_checksums(run / "final-artifacts")
assert total_llm > 0, "validation run has no successful LLM events"
assert total_tokens > 0, "validation run has no token usage"
server_sha = hashlib.sha256(server.read_bytes()).hexdigest()
result = {
    "status": "PASS",
    "certified_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
    "validation_run": str(run),
    "server": str(server),
    "server_sha256": server_sha,
    "epoch_count": len(epochs),
    "server_observed_statements": total_sql,
    "successful_llm_requests": total_llm,
    "total_tokens": total_tokens,
    "coverage_monotonic": True,
    "checksums_verified": True,
    "epochs": details,
}
Path(a.output).write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ("status", "epoch_count", "server_observed_statements", "successful_llm_requests", "total_tokens")}))
