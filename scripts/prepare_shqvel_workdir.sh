#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.sh"
require_dir "$SHQVEL_REPO"
WORK_REPO="$LOCAL_ROOT/work/SQLancerPlusPlus"
mkdir -p "$WORK_REPO"
rsync -a --delete \
  --exclude='.git/' --exclude='logs/' --exclude='src/__pycache__/' \
  --exclude='dbconfigs/llm.properties' \
  "$SHQVEL_REPO/" "$WORK_REPO/"
ln -sfn "$SHQVEL_REPO/dbconfigs/llm.properties" "$WORK_REPO/dbconfigs/llm.properties"
(cd "$WORK_REPO" && mvn -q -DskipTests package)
printf '%s\n' "$WORK_REPO"

