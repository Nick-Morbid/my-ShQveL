#!/usr/bin/env python3
import argparse
import gzip
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--source", required=True)
p.add_argument("--state", required=True)
p.add_argument("--output", required=True)
p.add_argument("--exclude", action="append", default=[], help="source-relative file to leave untouched")
a = p.parse_args()
source = Path(a.source)
state_path = Path(a.state)
output = Path(a.output)
output.mkdir(parents=True, exist_ok=True)
state = json.loads(state_path.read_text()) if state_path.exists() else {}
manifest = []

for path in sorted(x for x in source.rglob("*") if x.is_file()):
    rel = str(path.relative_to(source))
    if rel in a.exclude:
        continue
    start = int(state.get(rel, 0))
    size = path.stat().st_size
    if size < start:  # a newly-created file reused an old name
        start = 0
    if size == start:
        continue
    chunk_rel = Path(rel + f".bytes-{start}-{size}.chunk.gz")
    chunk_path = output / chunk_rel
    chunk_path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("rb") as src, gzip.open(chunk_path, "wb", compresslevel=6) as dst:
        src.seek(start)
        digest = hashlib.sha256()
        while remaining := src.read(1024 * 1024):
            dst.write(remaining)
            digest.update(remaining)
    manifest.append({"source": rel, "start": start, "end": size,
                     "chunk": str(chunk_rel), "raw_sha256": digest.hexdigest()})
    state[rel] = size

(output / "chunks.json").write_text(json.dumps(manifest, indent=2) + "\n")
state_path.parent.mkdir(parents=True, exist_ok=True)
state_path.write_text(json.dumps(state, indent=2) + "\n")
