#!/usr/bin/env bash
# Wrapper for any /bnma script that needs rjags: loads the `jags` environment
# module first (rjags is installed but fails to link its shared library
# without this -- confirmed: requireNamespace("rjags") is FALSE until
# `module load jags` has run in the same shell), then execs Rscript.
#
# Usage: scripts/run_with_jags.sh <path/to/script.R> [args...]
set -euo pipefail

if [ -f /etc/profile.d/modules.sh ]; then
  source /etc/profile.d/modules.sh
fi

if command -v module >/dev/null 2>&1; then
  module load jags
else
  echo "WARNING: 'module' command not found -- assuming JAGS is already on the library path." >&2
fi

exec /opt/R/4.1.2/bin/Rscript "$@"
