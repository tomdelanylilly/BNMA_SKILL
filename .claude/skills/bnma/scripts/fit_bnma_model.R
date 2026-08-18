#!/usr/bin/env Rscript
# Step 5 of the /bnma skill: fit (or load a cached fit of) the BATMAN/JAGS
# random-effects NMA model. Reuses the existing model_simultaneous.txt
# structure and MCMC settings already proven in efficacy_bnma_v3_gzmu_misc5.R
# (10k adapt, 10k burn-in, 20k sampled thinned to 10) -- no new statistics,
# no fixed-effects variant (heterogeneity is already handled by this model's
# sigma/tau2 term, which is what was actually needed, not a fixed-effect
# model).
#
# model_random.txt/model_fixed.txt (the recommended defaults -- see SKILL.md)
# are copied verbatim from the real production BNMA Shiny app
# (BNMA_forest_plot-main.zip, confirmed 2026-08-17): non-hierarchical
# phi[i]~dnorm(0,0.0001) baseline per Dias 2013's "separate model" (matching
# the NMA Output Review Process Guide's stated standard), sigma~dunif(0,8).
# model_simultaneous.txt (hierarchical/exchangeable phi, sigma~dunif(0,100))
# stays as a legacy option -- it's the only one with a pooled baseline `m`
# node, needed for effect_type: absolute.
#
# Must be run via scripts/run_with_jags.sh, not Rscript directly -- rjags
# needs the `jags` environment module loaded first in this environment.
#
# Usage:
#   scripts/run_with_jags.sh scripts/fit_bnma_model.R --batman <batman.rds> \
#     --model <model_random.txt|model_fixed.txt|model_simultaneous.txt> --cache <samples.rds> [--force]

suppressPackageStartupMessages(library(rjags))

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  batman   = list(required = TRUE),
  model    = list(required = TRUE),
  cache    = list(required = TRUE),
  force    = list(flag = TRUE, default = FALSE),
  n_adapt  = list(default = "10000"),
  n_burnin = list(default = "10000"),
  n_iter   = list(default = "20000"),
  thin     = list(default = "10"),
  seed     = list(default = "2026")
))

batman_data <- readRDS(args$batman)

if (file.exists(args$cache) && !args$force) {
  cat("Loading cached MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))
  base_seed <- as.integer(args$seed) * 1000
  inits.list <- lapply(1:3, function(i) {
    list(.RNG.seed = base_seed + i, .RNG.name = "base::Wichmann-Hill")
  })

  cat("Compiling JAGS model from", args$model, "\n")
  jags_model <- jags.model(
    args$model, batman_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = inits.list
  )

  cat("Burn-in (", args$n_burnin, "iterations)...\n")
  update(jags_model, as.integer(args$n_burnin))

  # model_simultaneous.txt is the only model file with a pooled baseline (m,
  # sigma_m, mu_new) -- model_random.txt/model_fixed.txt (the real
  # production models) use a separate phi[i] per study with no pooling, so
  # those nodes don't exist there and monitoring them would error at
  # compile/sample time. Keyed off the model file itself (not a manifest
  # field) so every existing caller that already passes an explicit --model
  # path keeps working with zero changes.
  variable_names <- if (basename(args$model) == "model_simultaneous.txt") {
    c("d", "phi", "delta", "m", "sigma_m", "mu_new")
  } else {
    c("d", "phi", "delta")
  }

  cat("Sampling (", args$n_iter, "iterations, thin =", args$thin, ")...\n")
  samples <- coda.samples(
    jags_model, as.integer(args$n_iter),
    variable.names = variable_names,
    thin = as.integer(args$thin)
  )
  saveRDS(samples, args$cache)
  cat("Samples saved to", args$cache, "\n")
}

cat("Posterior summary (d[] treatment-effect nodes):\n")
s <- summary(samples)
d_rows <- grepl("^d\\[", rownames(s[[1]]))
print(round(cbind(s[[1]][d_rows, "Mean", drop = FALSE], s[[2]][d_rows, c("2.5%", "97.5%")]), 2))
