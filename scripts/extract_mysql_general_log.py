#!/usr/bin/env python3
"""Turn a MySQL FILE general log into a deterministic replay stream."""
import argparse
import gzip
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--input", required=True)
parser.add_argument("--output", required=True)
parser.add_argument("--summary", required=True)
args = parser.parse_args()

header = re.compile(
    r"^(?P<timestamp>\d{4}-\d\d-\d\dT\S+)\s+"
    r"(?P<thread>\d+)\s+(?P<command>[A-Za-z ]+?)\t(?P<argument>.*)$"
)
events = []
current = None
databases = {}

def finish():
    global current
    if current is None:
        return
    current["argument"] = current["argument"].rstrip("\n")
    events.append(current)
    current = None

source = Path(args.input)
opener = gzip.open if source.suffix == ".gz" else open
with opener(source, "rt", errors="replace") as stream:
    for line in stream:
        match = header.match(line)
        if match:
            finish()
            current = match.groupdict()
            current["thread"] = int(current["thread"])
        elif current is not None:
            current["argument"] += "\n" + line.rstrip("\n")
finish()

statement_commands = {"Query", "Execute", "Prepare"}
statement_count = 0
connect_count = 0
replay_database = None
with gzip.open(args.output, "wt") as replay:
    for event in events:
        command = event["command"].strip()
        thread = event["thread"]
        argument = event["argument"]
        if command == "Connect":
            connect_count += 1
            match = re.search(r"\son\s+(\S+)\s+using\s+", argument)
            if match:
                databases[thread] = match.group(1)
        elif command == "Init DB":
            databases[thread] = argument.strip()
        elif command == "Quit":
            databases.pop(thread, None)
        elif command in statement_commands and argument.strip():
            statement_count += 1
            database = databases.get(thread)
            replay.write(
                f"-- {event['timestamp']} thread={thread} command={command}"
                f" database={database or 'unknown'}\n"
            )
            if database and database != replay_database:
                replay.write(f"USE `{database.replace('`', '``')}`;\n")
                replay_database = database
            sql = argument.rstrip()
            replay.write(sql)
            if not sql.endswith(";"):
                replay.write(";")
            replay.write("\n")

Path(args.summary).write_text(json.dumps({
    "source": str(source),
    "general_log_events": len(events),
    "server_observed_statements": statement_count,
    "connections": connect_count,
    "outcomes_available": False,
    "outcomes_note": "MySQL FILE general_log records received statements but not their result status; use ShQveL progress metrics for the reported success percentage.",
}, indent=2) + "\n")
