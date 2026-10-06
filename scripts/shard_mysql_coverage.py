#!/usr/bin/env python3
import argparse
import os
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--input", required=True)
p.add_argument("--output", required=True)
p.add_argument("--shards", type=int, default=8)
a = p.parse_args()
source = Path(a.input)
root = Path(a.output)
files = sorted(source.rglob("*.gcda"))
if not files:
    raise SystemExit("no gcda files to shard")
for index, gcda in enumerate(files):
    shard = root / f"shard-{index % a.shards:02d}"
    relative = gcda.relative_to(source)
    target = shard / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    os.link(gcda, target)
    gcno = gcda.with_suffix(".gcno")
    if not gcno.is_file():
        raise SystemExit(f"missing gcno companion for {gcda}")
    os.link(gcno, target.with_suffix(".gcno"))
