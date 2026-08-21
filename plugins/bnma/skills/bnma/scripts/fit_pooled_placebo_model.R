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
#     --arm-rows <arm_rows.rds> --cache <placebo_samples.rds> \
#     [--placebo-data-out <placebo_data.rds>] [--force]
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
#
# --placebo-data-out (optional) persists the per-study placebo rows actually
# used for this fit (study_name/study_idx/y/se) -- make_placebo_forest_plot.R
# needs this to label each posterior mu[i] with its real study name, since
# the JAGS samples themselves only carry the numeric study_idx. Cross-
# validated 2026-08-21 against a colleague's independent implementation
# (the `godwill-bnma` branch, which re-derives this same placebo subset from
# scratch via its own build_placebo_data.R) -- adopted the persist-and-reuse
# approach here instead, since arm_rows.rds already reflects this run's full
# manifest filtering and re-deriving that logic in a second script is a
# needless duplication risk if build_batman_data.R's own filtering ever
# changes.

suppressPackageStartupMessages({
  library(rjags)
  library(dplyr)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  arm_rows        = list(required = TRUE),
  cache           = list(required = TRUE),
  placebo_data_out = list(default = NULL),
  force           = list(flag = TRUE, default = FALSE),
  n_adapt         = list(default = "1000"),
  n_burnin        = list(default = "5000"),
  n_iter          = list(default = "10000"),
  thin            = list(default = "10"),
  seed            = list(default = "2026")
))

arm_rows <- readRDS(args$arm_rows)

placebo_rows <- arm_rows %>% filter(compound == "placebo", !is.na(y), !is.na(se), se > 0, is.finite(se))
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

# A hierarchical random-effects meta-analysis needs at least 2 groups to say
# anything about between-study variance at all -- the exact same
# identifiability problem compute_heterogeneity_estimability() already
# checks for the main model's own delta[i,j] heterogeneity, just here for
# sigma_m instead of sigma. Confirmed by testing (colleague's godwill-bnma
# branch, 2026-08-21): with 1 study, sigma_m's posterior is pure prior
# (dunif(0,10)), not a data-driven estimate -- stop rather than silently
# fitting a meaningless model.
if (nrow(study_map) < 2) {
  stop(
    "Not enough studies with a usable placebo arm for a pooled-placebo model ",
    "(need >= 2; found ", nrow(study_map), "). With only one study, sigma_m ",
    "has nothing to be estimated from -- check the manifest's study selection ",
    "and route/evidence/compound/region filters."
  )
}

if (!is.null(args$placebo_data_out)) {
  saveRDS(placebo_rows, args$placebo_data_out)
}

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
  base_seed <- as.integer(args$seed) * 1000
  y_mean <- mean(jags_data$y_pct, na.rm = TRUE)

  # Deterministic per-chain RNG (.RNG.seed/.RNG.name), matching
  # fit_bnma_model.R's own established convention for the main model's fit
  # -- a plain single set.seed() call (this script's own original approach)
  # doesn't guarantee reproducibility across JAGS's separately-spawned chain
  # RNG streams the way an explicit per-chain seed does.
  inits.list <- lapply(1:3, function(chain_num) {
    list(
      .RNG.seed = base_seed + chain_num, .RNG.name = "base::Wichmann-Hill",
      m = rnorm(1, y_mean, 0.5),
      sigma_m = runif(1, 0.3, 1),
      mu = rnorm(jags_data$ns_bl, y_mean, 0.5)
    )
  })

  model_path <- file.path(dirname(script_dir), "model_placebo_random.txt")
  cat("Compiling JAGS model from", model_path, "\n")
  jags_model <- jags.model(
    model_path, jags_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = inits.list
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

# Convergence diagnostics -- always run, never skipped, same rule as every
# other gate in this skill, AND persisted to disk (<cache>_diagnostics.yaml)
# same as fit_bnma_model.R's own fit -- confirmed 2026-08-21 this file's
# earlier version only printed the diagnostics, never wrote them, the one
# fit in this skill that didn't leave a diagnostics artifact next to its cache.
diag <- compute_convergence_diagnostics(samples)
print_convergence_diagnostics(diag)
diagnostics_path <- sub("\\.rds$", "_diagnostics.yaml", args$cache)
yaml::write_yaml(
  c(
    list(generated_at = as.character(Sys.time()),
         samples_file = normalizePath(args$cache, mustWork = FALSE)),
    diag
  ),
  diagnostics_path
)
cat("Diagnostics written to:", diagnostics_path, "\n")

