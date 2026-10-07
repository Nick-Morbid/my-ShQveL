#!/usr/bin/env bash
set -Eeuo pipefail

# Canonical formal-run entry point. Duration arguments are intentionally not
# accepted; use run_mariadb_experiment.sh only for validation runs.
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/preflight_mariadb_cov.sh" --require-probe
export SHQVEL_RUN_ID="${SHQVEL_RUN_ID:-shqvel-mariadb-24h-$(date +%Y%m%d_%H%M%S)}"
exec "$root/scripts/run_mariadb_experiment.sh" 24 3600
