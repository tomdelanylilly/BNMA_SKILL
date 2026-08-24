#!/usr/bin/env bash
# Wrapper for any /bnma script that does NOT need rjags/JAGS -- resolves
# Rscript portably (see _resolve_rscript.sh) and execs it. Use
# run_with_jags.sh instead for fit_bnma_model.R.
#
# Usage: scripts/run_r.sh <path/to/script.R> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_resolve_rscript.sh"

exec "$RSCRIPT_BIN" "$@"
