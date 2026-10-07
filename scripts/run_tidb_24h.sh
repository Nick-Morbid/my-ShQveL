#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/preflight_tidb_cov.sh"
export SHQVEL_RUN_ID="${SHQVEL_RUN_ID:-shqvel-tidb-24h-$(date +%Y%m%d_%H%M%S)}"
exec "$root/scripts/run_tidb_experiment.sh" 24 3600
