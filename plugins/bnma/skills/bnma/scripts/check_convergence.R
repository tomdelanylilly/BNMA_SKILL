#!/usr/bin/env Rscript
# Standalone re-check of MCMC convergence diagnostics on a samples.rds --
# fit_bnma_model.R already runs this automatically after every fit (see
# lib_common.R's compute_convergence_diagnostics()), so you normally won't
# need to call this directly. Useful for re-checking an older cached run
# without refitting, or after changing thresholds.
#
# Thresholds: see lib_common.R's CONVERGENCE_THRESHOLDS -- borrowed from the
# BayesianAgent plugin's model-diagnostics skill (its JAGS/R2jags bar).
#
# Usage:
#   scripts/run_r.sh scripts/check_convergence.R --samples <samples.rds> --out <diagnostics.yaml>

suppressPackageStartupMessages({
  library(coda)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples = list(required = TRUE),
  out     = list(required = TRUE)
))

samples <- readRDS(args$samples)
diag <- compute_convergence_diagnostics(samples)
print_convergence_diagnostics(diag)

write_yaml(
  c(
    list(generated_at = as.character(Sys.time()),
         samples_file = normalizePath(args$samples, mustWork = FALSE)),
    diag
  ),
  args$out
)
cat("Diagnostics written to:", args$out, "\n")
