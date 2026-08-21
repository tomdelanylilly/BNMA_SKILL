#!/usr/bin/env Rscript
# Standalone pooled-placebo model, for the --effect absolute baseline in
# make_forest_plot.R. Adopted 2026-08-20 from the real production package's
# own pooled-placebo feature (EliLillyCo/CMH.BNMA, R/pooled_placebo_model_utils.R
# `jags_placebo_module()`/`define_placebo_model()`) -- a SEPARATE, standalone
# hierarchical random-effects meta-analysis fit only on placebo arms
# (mu[i]~dnorm(m, sigma_m^2)), not derived from the main BNMA model's own
# phi[i] nodes at all.
#
# This replaces the 2026-08-19 fix that averaged phi[i] across only the
# real-placebo studies from model_simultaneous.txt's own fit -- that fix was
# already correct in spirit (excluding no-placebo studies' contaminated
# phi[i]), but this is architecturally cleaner: a genuinely independent fit
# that only ever sees placebo data, works with ANY model_type (rand_effect/
# fixed_effect included -- those have no pooled baseline of their own at
# all, so this is what actually enables --effect absolute for them, not
# just model_simultaneous.txt/model_simultaneous_fixed.txt).
#
# MCMC settings match the production package's own (lighter than the main
# model's canonical 10k/10k/20k/thin-10, since this model has far fewer
# parameters): n.adapt 1,000, burn-in 5,000, sampling 10,000, thin 10.
#
# Usage:
#   scripts/run_with_jags.sh scripts/fit_pooled_placebo_model.R \
#     --arm-rows <arm_rows.rds> --cache <placebo_samples.rds> [--force]
#
# No --effect-col/--se-col flag -- arm_rows.rds (Step 5's --arm-rows-out)
# already normalizes to plain y/se columns regardless of this run's own
# effect_col/se_col manifest fields (build_batman_data.R's transmute() does
# that rename), so this script never needs to know the original QA/PRD
# column names at all. Confirmed 2026-08-21: an earlier version of this
# comment claimed those flags existed; parse_args() below never defined
# them, so passing either errored with "Unknown argument."
#
# --arm-rows is Step 5's --arm-rows-out output -- the real (non-phantom),
# manifest-filtered study-level arm rows. Using this (not the raw merged
# data) means the placebo arms fed here already reflect every naming/pooling
# resolution, study include/exclude, and relabel from this run's manifest,
# same set of studies the main model itself was fit on.

suppressPackageStartupMessages({
  library(rjags)
  library(dplyr)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  arm_rows  = list(required = TRUE),
  cache     = list(required = TRUE),
  force     = list(flag = TRUE, default = FALSE),
  n_adapt   = list(default = "1000"),
  n_burnin  = list(default = "5000"),
  n_iter    = list(default = "10000"),
  thin      = list(default = "10"),
  seed      = list(default = "2026")
))

arm_rows <- readRDS(args$arm_rows)

placebo_rows <- arm_rows %>% filter(compound == "placebo", !is.na(y), !is.na(se), se > 0)
if (nrow(placebo_rows) == 0) {
  stop("No usable placebo rows (compound=='placebo', numeric y/se) found in ", args$arm_rows)
}

# Remap to a contiguous 1..ns_bl study index for JAGS -- study_ind from
# arm_rows spans every study in the run, not just placebo-bearing ones.
study_map <- data.frame(
  study_ind = sort(unique(placebo_rows$study_ind)),
  study_idx = seq_along(unique(placebo_rows$study_ind))
)
placebo_rows <- placebo_rows %>% left_join(study_map, by = "study_ind")

cat("Pooled placebo model: ", nrow(placebo_rows), " placebo row(s) across ", nrow(study_map), " study/ies.\n", sep = "")

jags_data <- list(
  y_pct = placebo_rows$y,
  se_pct = placebo_rows$se,
  n_obs = nrow(placebo_rows),
  ns_bl = nrow(study_map),
  study_idx = placebo_rows$study_idx
)

if (file.exists(args$cache) && !args$force) {
  cat("Loading cached placebo-model MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))

  init_fun <- function() {
    list(
      m = rnorm(1, mean(jags_data$y_pct, na.rm = TRUE), 0.5),
      sigma_m = runif(1, 0.3, 1),
      mu = rnorm(jags_data$ns_bl, mean(jags_data$y_pct, na.rm = TRUE), 0.5)
    )
  }

  model_path <- file.path(dirname(script_dir), "model_placebo_random.txt")
  cat("Compiling JAGS model from", model_path, "\n")
  jags_model <- jags.model(
    model_path, jags_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = init_fun
  )

  cat("Burn-in (", args$n_burnin, "iterations)...\n")
  update(jags_model, as.integer(args$n_burnin))

  cat("Sampling (", args$n_iter, "iterations, thin =", args$thin, ")...\n")
  samples <- coda.samples(
    jags_model,
    variable.names = c("m", "sigma_m", "mu", "mu_new"),
    n.iter = as.integer(args$n_iter),
    thin = as.integer(args$thin)
  )

  saveRDS(samples, args$cache)
  cat("Saved:", args$cache, "\n")
}

s <- summary(samples)
m_row <- s$statistics["m", "Mean"]
m_ci <- s$quantiles["m", c("2.5%", "97.5%")]
sigma_row <- s$statistics["sigma_m", "Mean"]
cat("Pooled placebo baseline: m =", round(m_row, 3),
    " (95% CrI", round(m_ci[1], 3), ",", round(m_ci[2], 3), ")",
    " sigma_m =", round(sigma_row, 3), "\n")

diag <- compute_convergence_diagnostics(samples)
print_convergence_diagnostics(diag)
