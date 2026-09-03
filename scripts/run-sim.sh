#!/usr/bin/env bash
# Build, install and launch the app on the simulator. Usage: scripts/run-sim.sh ["iPhone 17 Pro"]
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-iPhone 17 Pro}"
make run SIM="$SIM"
