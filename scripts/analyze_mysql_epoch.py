#!/usr/bin/env python3
import argparse
import gzip
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--epoch", required=True)
a = p.parse_args()
root = Path(a.epoch)
texts = []
for chunk in sorted((root / "runtime").rglob("*.chunk.gz")):
    try:
        with gzip.open(chunk, "rt", errors="replace") as stream:
            texts.append(stream.read())
    except (OSError, EOFError):
        continue
combined = "\n".join(texts)
progress = re.findall(r"Executed (\d+) queries .*successful statements:\s*([0-9.]+)%", combined)
metrics = {
    "latest_executed_queries": int(progress[-1][0]) if progress else None,
    "latest_successful_statement_percent": float(progress[-1][1]) if progress else None,
    "successful_llm_requests": 0,
    "prompt_tokens": 0,
    "completion_tokens": 0,
    "total_tokens": 0,
    "server_observed_statements": None,
    "server_outcomes_available": False,
}
for chunk in sorted((root / "runtime").rglob("*llm-events*.chunk.gz")):
    try:
        with gzip.open(chunk, "rt", errors="replace") as stream:
            for line in stream:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                metrics["successful_llm_requests"] += 1
                usage = event.get("usage") or {}
                for name in ("prompt_tokens", "completion_tokens", "total_tokens"):
                    # Java fragment-synthesis events nest token counts under
                    # `usage`; Python documentation-summary events store them
                    # at the top level. Count both event formats.
                    value = usage.get(name)
                    if value is None:
                        value = event.get(name)
                    metrics[name] += int(value or 0)
    except (OSError, EOFError):
        continue
summary = root / "sql" / "mysql-general-summary.json"
if summary.is_file():
    general = json.loads(summary.read_text())
    metrics["server_observed_statements"] = general.get("server_observed_statements")
    metrics["server_outcomes_available"] = bool(general.get("outcomes_available"))
(root / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
