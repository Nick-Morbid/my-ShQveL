#!/usr/bin/env python3
"""Run a command in a dedicated session and expose its process-group id."""
import argparse
import os
import subprocess
import sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--pid-file", required=True)
p.add_argument("command", nargs=argparse.REMAINDER)
a = p.parse_args()
if a.command and a.command[0] == "--":
    a.command = a.command[1:]
if not a.command:
    raise SystemExit("missing command")
proc = subprocess.Popen(a.command, start_new_session=True)
target = Path(a.pid_file)
tmp = target.with_suffix(target.suffix + ".tmp")
tmp.write_text(f"{proc.pid}\n")
os.replace(tmp, target)
try:
    raise SystemExit(proc.wait())
except KeyboardInterrupt:
    # The harness owns termination of the dedicated process group.
    raise SystemExit(130)
