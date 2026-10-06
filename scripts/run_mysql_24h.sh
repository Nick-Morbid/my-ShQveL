#!/usr/bin/env bash
set -Eeuo pipefail

# Deliberately expose no duration arguments: this is the canonical formal-run
# entry point, while run_mysql_experiment.sh remains useful for short probes.
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/preflight_mysql_cov.sh" --require-probe
export SHQVEL_RUN_ID="${SHQVEL_RUN_ID:-shqvel-mysql-24h-$(date +%Y%m%d_%H%M%S)}"
exec "$root/scripts/run_mysql_experiment.sh" 24 3600
