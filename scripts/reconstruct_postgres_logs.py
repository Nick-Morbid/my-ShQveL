#!/usr/bin/env python3
import argparse
import gzip
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--run", required=True)
p.add_argument("--output", required=True)
a = p.parse_args()
run = Path(a.run)
out = Path(a.output)
out.mkdir(parents=True, exist_ok=True)
expected = {}
epochs = sorted(run.glob("epoch-*"))
if (run / "final-artifacts").is_dir():
    epochs.append(run / "final-artifacts")
for epoch in epochs:
    manifest = epoch / "postgres" / "chunks.json"
    if not manifest.exists():
        continue
    for item in json.loads(manifest.read_text()):
        rel = item["source"]
        # A run deliberately baselines pre-existing log bytes, so its first
        # captured chunk may start at a non-zero EOF. Only gaps *between this
        # run's chunks* are errors.
        if rel in expected and item["start"] != expected[rel]:
            raise SystemExit(f"non-contiguous PostgreSQL chunk for {rel}: {item}")
        target = out / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        mode = "ab" if rel in expected else "wb"
        with target.open(mode) as dst, gzip.open(epoch / "postgres" / item["chunk"], "rb") as src:
            while data := src.read(1024 * 1024):
                dst.write(data)
        expected[rel] = item["end"]
