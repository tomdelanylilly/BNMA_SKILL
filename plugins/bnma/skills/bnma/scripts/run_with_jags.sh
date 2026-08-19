#!/usr/bin/env bash
# Wrapper for any /bnma script that needs rjags: resolves Rscript (see
# _resolve_rscript.sh), loads the `jags` environment module (rjags is
# installed but fails to link its shared library without this -- confirmed:
# requireNamespace("rjags") is FALSE until `module load jags` has run in the
# same shell), then execs Rscript.
#
# Usage: scripts/run_with_jags.sh <path/to/script.R> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_resolve_rscript.sh"

if command -v module >/dev/null 2>&1; then
  if module avail jags 2>&1 | grep -qi jags; then
    module load jags
  else
    echo "WARNING: environment modules are available here but no 'jags' module was found." >&2
    echo "  rjags will likely fail to load unless JAGS is on the library path some other way." >&2
    echo "  Run 'module avail' to check what this session actually calls it." >&2
  fi
else
  echo "NOTE: no 'module' command in this session -- assuming JAGS is already reachable" >&2
  echo "  (either not needed here, or provisioned some other way than environment modules)." >&2
fi

exec "$RSCRIPT_BIN" "$@"
