#!/usr/bin/env python3
"""Extract server-observed SQL and execution outcomes from PostgreSQL CSV logs."""
import argparse
import csv
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--logs", required=True)
p.add_argument("--output", required=True)
p.add_argument("--application", default="ShQveL-24h")
p.add_argument("--events", help="optional JSONL with SQL, success/error and provenance")
p.add_argument("--summary", help="optional aggregate JSON summary")
a = p.parse_args()

# PostgreSQL csvlog columns: timestamp,user,db,pid,client,session_id,
# session_line,command_tag,session_start,vxid,xid,severity,sqlstate,message,
# detail,hint,internal_query,internal_pos,context,query,pos,location,
# application_name,backend_type,leader_pid,query_id.
rows = []
for path in sorted(Path(a.logs).glob("*.csv")):
    with path.open(newline="", errors="replace") as f:
        for row in csv.reader(f):
            if len(row) < 23 or row[22] != a.application:
                continue
            rows.append((row[0], row[5], int(row[6] or 0), row[2], row[11], row[12], row[13], path.name))
rows.sort(key=lambda r: (r[0], r[1], r[2]))

# log_statement emits "statement:" for the simple protocol and
# "execute <name>:" for JDBC's extended protocol.  Errors in the same session
# after a statement and before its next statement describe that execution.
events = []
active = {}
execute_re = re.compile(r"^execute (?:<[^>]*>|[^:]+):\s?(.*)$", re.S)
for timestamp, session, line, database, severity, sqlstate, message, source in rows:
    sql = None
    protocol = None
    if message.startswith("statement: "):
        sql, protocol = message[len("statement: "):], "simple"
    else:
        match = execute_re.match(message)
        if match:
            sql, protocol = match.group(1), "extended"
    if sql is not None:
        event = {"timestamp": timestamp, "session": session, "session_line": line,
                 "database": database, "protocol": protocol, "sql": sql,
                 "success": True, "sqlstate": None, "error": None, "source": source}
        events.append(event)
        active[session] = event
    elif severity in {"ERROR", "FATAL", "PANIC"} and session in active:
        event = active[session]
        event["success"] = False
        event["sqlstate"] = sqlstate
        event["error"] = message

with Path(a.output).open("w") as f:
    for event in events:
        timestamp, session, line, database, sql = (event[k] for k in
            ("timestamp", "session", "session_line", "database", "sql"))
        result = "success" if event["success"] else f"error sqlstate={event['sqlstate']}"
        f.write(f"-- {timestamp} database={database} session={session} line={line} result={result}\n")
        f.write(sql.rstrip())
        if not sql.rstrip().endswith(";"):
            f.write(";")
        f.write("\n")

if a.events:
    with Path(a.events).open("w") as f:
        for event in events:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
if a.summary:
    successful = sum(e["success"] for e in events)
    by_database = {}
    for event in events:
        item = by_database.setdefault(event["database"], {"total": 0, "successful": 0})
        item["total"] += 1
        item["successful"] += int(event["success"])
    summary = {"application": a.application, "total": len(events), "successful": successful,
               "failed": len(events) - successful,
               "success_percent": round(100 * successful / len(events), 6) if events else None,
               "by_database": by_database}
    Path(a.summary).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
