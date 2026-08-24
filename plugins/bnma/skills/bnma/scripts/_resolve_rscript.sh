#!/usr/bin/env bash
# Shared Rscript resolution, sourced by run_r.sh and run_with_jags.sh.
# Not meant to be run directly. Sets RSCRIPT_BIN.
#
# Resolution order: explicit override, PATH, `module load R` (whichever
# version this session tags default) then PATH again. Neither "on PATH" nor
# "one fixed install path" can be assumed across different analysts'
# Positron sessions -- confirmed by testing: Rscript is NOT on PATH by
# default in at least one real session here, and R itself is provisioned
# via `module load R/<version>` there, same as JAGS.

if [ -f /etc/profile.d/modules.sh ]; then
  source /etc/profile.d/modules.sh
fi

RSCRIPT_BIN="${BNMA_RSCRIPT:-}"
if [ -z "$RSCRIPT_BIN" ]; then
  RSCRIPT_BIN="$(command -v Rscript || true)"
fi
if [ -z "$RSCRIPT_BIN" ] && command -v module >/dev/null 2>&1; then
  module load R >/dev/null 2>&1 || true
  RSCRIPT_BIN="$(command -v Rscript || true)"
fi
if [ -z "$RSCRIPT_BIN" ]; then
  echo "ERROR: no Rscript found on PATH, and 'module load R' didn't put one there." >&2
  echo "Set BNMA_RSCRIPT=/path/to/Rscript to pin a specific install." >&2
  exit 1
fi
