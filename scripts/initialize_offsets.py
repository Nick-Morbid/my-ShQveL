#!/usr/bin/env python3
"""Start byte-chunk capture at the current EOF of every existing file."""
import argparse
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--source", required=True)
p.add_argument("--state", required=True)
a = p.parse_args()
source = Path(a.source)
state = {str(path.relative_to(source)): path.stat().st_size
         for path in source.rglob("*") if path.is_file()}
target = Path(a.state)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(state, indent=2) + "\n")
