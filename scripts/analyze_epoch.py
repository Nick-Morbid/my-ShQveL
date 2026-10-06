#!/usr/bin/env python3
import argparse
import csv
import gzip
import io
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--epoch", required=True)
a = p.parse_args()
root = Path(a.epoch)
stats = {
    "supported_fragments": 0,
    "invalid_fragments": 0,
    "removed_fragments": 0,
    "learning_topics_completed": 0,
    "llm_requests": 0,
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0,
    "reported_total_cost": 0.0,
    "llm_metrics_scope": "cumulative_at_snapshot",
    "interval_llm_requests": 0,
    "interval_prompt_tokens": 0,
    "interval_completion_tokens": 0,
    "interval_total_tokens": 0,
    "interval_reported_total_cost": 0.0,
    "latest_executed_queries": None,
    "latest_successful_statement_percent": None,
    "server_statements": 0,
    "server_successful_statements": 0,
    "server_failed_statements": 0,
    "server_success_percent": None,
}

text = ""
for chunk in sorted((root / "runtime").rglob("*.chunk.gz")):
    with gzip.open(chunk, "rt", errors="replace") as f:
        text += f.read()
stats["supported_fragments"] = len(re.findall(r"Fragment .* is supported", text))
stats["invalid_fragments"] = len(re.findall(r"Fragment .* is invalid", text))
stats["removed_fragments"] = len(re.findall(r"^Removed fragment", text, re.M))
stats["learning_topics_completed"] = len(re.findall(r"Processing and loading fragments from learner for type", text))
progress = re.findall(r"Executed (\d+) queries .*successful statements:\s*([0-9.]+)%", text)
if progress:
    stats["latest_executed_queries"] = int(progress[-1][0])
    stats["latest_successful_statement_percent"] = float(progress[-1][1])

for events in (root / "llm").rglob("*.jsonl"):
    for line in events.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        stats["llm_requests"] += 1
        usage = event.get("usage") or event
        for name in ("prompt_tokens", "completion_tokens", "total_tokens"):
            stats[name] += int(usage.get(name) or 0)
        stats["reported_total_cost"] += float(event.get("total_cost") or 0)

# Incremental event chunks provide this epoch's token/call cost rather than
# the cumulative-at-snapshot values above.
for chunk in sorted((root / "runtime").rglob("*llm-events.jsonl*.chunk.gz")):
    try:
        with gzip.open(chunk, "rt", errors="replace") as f:
            for line in f:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                stats["interval_llm_requests"] += 1
                usage = event.get("usage") or event
                stats["interval_prompt_tokens"] += int(usage.get("prompt_tokens") or 0)
                stats["interval_completion_tokens"] += int(usage.get("completion_tokens") or 0)
                stats["interval_total_tokens"] += int(usage.get("total_tokens") or 0)
                stats["interval_reported_total_cost"] += float(event.get("total_cost") or 0)
    except (EOFError, UnicodeDecodeError):
        continue

# Per-epoch authoritative execution rate from PostgreSQL csvlog.  SQLancer's
# own progress line remains above for comparison, but may not be printed in a
# short epoch. JDBC statements use the "execute <unnamed>:" prefix.
active = {}
for chunk in sorted((root / "postgres").rglob("*.chunk.gz")):
    if ".csv.bytes-" not in chunk.name and ".csv.csv.bytes-" not in chunk.name:
        continue
    try:
        with gzip.open(chunk, "rb") as raw:
            reader = csv.reader(io.TextIOWrapper(raw, errors="replace", newline=""))
            for row in reader:
                if len(row) < 23 or row[22] != "ShQveL-24h":
                    continue
                message, session, severity = row[13], row[5], row[11]
                is_statement = message.startswith("statement: ") or (
                    message.startswith("execute ") and ":" in message)
                if is_statement:
                    stats["server_statements"] += 1
                    stats["server_successful_statements"] += 1
                    active[session] = True
                elif severity in {"ERROR", "FATAL", "PANIC"} and active.get(session):
                    stats["server_successful_statements"] -= 1
                    stats["server_failed_statements"] += 1
                    active[session] = False
    except (csv.Error, EOFError, UnicodeDecodeError):
        # A snapshot can end while the active csvlog is writing its last row.
        # The complete row appears in the following byte chunk.
        continue
if stats["server_statements"]:
    stats["server_success_percent"] = round(
        100 * stats["server_successful_statements"] / stats["server_statements"], 6)

(root / "metrics.json").write_text(json.dumps(stats, indent=2) + "\n")
