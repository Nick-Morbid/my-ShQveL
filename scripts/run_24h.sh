#!/usr/bin/env bash
set -Eeuo pipefail
exec "$(dirname "$0")/run_experiment.sh" 24 3600

