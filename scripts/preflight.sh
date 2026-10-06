#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
REPORT="$STATE_DIR/preflight-report.txt"
AVAILABLE_KIB="$(df --output=avail "$LOCAL_ROOT" | tail -1 | tr -d ' ')"
(( AVAILABLE_KIB >= 10 * 1024 * 1024 )) || die "less than 10 GiB local free space"
require_file "$LOCAL_ROOT/work/SQLancerPlusPlus/target/sqlancer-2.0.0.jar"
require_file "$LOCAL_ROOT/work/SQLancerPlusPlus/dbconfigs/postgresql-url.yml"
[[ -L "$LOCAL_ROOT/work/SQLancerPlusPlus/dbconfigs/llm.properties" ]] || die "LLM config link is missing"
python3 - "$NFS_ROOT" <<'PY'
import os, sys, uuid
from pathlib import Path
root = Path(sys.argv[1])
p = root / (".shqvel-preflight-" + uuid.uuid4().hex)
p.write_bytes(b"nfs-write-probe\n")
with p.open("rb") as f:
    assert f.read() == b"nfs-write-probe\n"
    os.fsync(f.fileno())
p.unlink()
PY
{
  date --iso-8601=seconds
  findmnt -T "$NFS_ROOT"
  "$HARNESS_ROOT/scripts/verify_target.sh"
  command -v java python3 lcov genhtml gcov zstd rsync
  df -h "$LOCAL_ROOT" "$NFS_ROOT"
  printf 'local_available_kib=%s\n' "$AVAILABLE_KIB"
  echo 'nfs_write_read_fsync_probe=PASS'
  echo 'llm_config_link_present_without_reading=PASS'
  echo 'PREFLIGHT_OK'
  echo 'READY_FOR_24H=YES'
} | tee "$REPORT"
