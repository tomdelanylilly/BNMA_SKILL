#!/usr/bin/env Rscript
# Step 5 of the /bnma skill: fit (or load a cached fit of) the BATMAN/JAGS
# random-effects NMA model.
#
# MCMC settings: canonical source is the real production package's own
# documentation (EliLillyCo/CMH.BNMA, provided by the user 2026-08-20,
# installed via `pak::pak("EliLillyCo/CMH.BNMA")`) -- this SUPERSEDES the
# NMA Output Review Process Guide-derived settings this file used before
# (burn-in 20,000/iter 50,000/thin 5), since it's the actual package's own
# stated behavior rather than a documentation guide being interpreted
# against unrelated internal scripts. CMH.BNMA states, verbatim:
#   "Models are fitted with JAGS (via rjags) using 3 MCMC chains: Adapt:
#   10,000 iterations. Burn-in: 10,000 iterations. Sampling: 20,000
#   iterations, thinned by 10."
# -> n.adapt 10,000 (unchanged), n.burnin 10,000 (was 20,000), n.iter 20,000
# (was 50,000), thin 10 (was 5), n.chains 3 (unchanged). Anyone needing the
# Guide's heavier 100k/200k sampling can still pass --n_iter directly.
#
# CMH.BNMA also confirms, matching this skill's own existing design (no
# code change needed, noted here only as independent cross-validation):
#   - "Two model specifications are available: Fixed effects (common
#     treatment effects across studies) / Random effects (study-level
#     heterogeneity via a half-uniform prior on sigma)" -- matches
#     model_fixed.txt/model_random.txt exactly (sigma~dunif(0,8) IS a
#     half-uniform prior on the between-study SD).
#   - "Posterior samples are cached to disk so repeat visits... load
#     instantly" -- matches this script's own cache-by-path behavior below.
#
# Chain initialization (not covered by the CMH.BNMA excerpt above, so the
# Guide-derived procedure below still stands unchanged):
#   - Chain 1 gets deterministic zero initial values for the baseline (phi,
#     and m for model_simultaneous.txt/model_simultaneous_fixed.txt) and
#     treatment-effect (d) nodes;
#     chains 2+ get random draws from those same nodes' own vague priors
#     (Normal(0, SD=100)) -- verbatim per the Guide's stated procedure.
#     Heterogeneity nodes (sigma/sigma_m) are deliberately left to JAGS's
#     own default init -- the Guide's own scope for explicit inits is "the
#     study-specific baseline term (alpha) and treatment terms (beta)" only,
#     and forcing chain 1's sigma to exactly 0 would divide-by-zero in this
#     model's tau2 <- 1/sigma2 node.
#
# model_random.txt/model_fixed.txt (the recommended defaults -- see SKILL.md)
# are copied verbatim from the real production BNMA Shiny app
# (BNMA_forest_plot-main.zip, confirmed 2026-08-17): non-hierarchical
# phi[i]~dnorm(0,0.0001) baseline per Dias 2013's "separate model" (matching
# the NMA Output Review Process Guide's stated standard), sigma~dunif(0,8) --
# also matching the Guide's explicit "between trial SD... uniform 0 to 8"
# spec for random-effects models. model_simultaneous.txt (hierarchical/
# exchangeable phi) stays as a legacy option for effect_type: absolute; its
# own sigma~dunif(0,8) (baseline heterogeneity, matches the Guide's "separate
# baseline risk models" spec) was already correct, but its treatment-effect
# heterogeneity prior was dunif(0,100) -- 12.5x the Guide's stated 0-8 for
# that exact parameter, with no other internal source supporting 100 --
# corrected 2026-08-19.
#
# model_simultaneous_fixed.txt (added 2026-08-19): same hierarchical/pooled
# phi as model_simultaneous.txt (needed for effect_type: absolute's baseline),
# but delta[i,j] is DETERMINISTIC (no sigma), matching model_fixed.txt's own
# delta block. Found by testing: fitting a star network (every treatment node
# single-study -- see compute_heterogeneity_estimability()) through
# model_simultaneous.txt's random delta[i,j]~dnorm(..., tau2) inflates every
# credible interval hugely, because with zero replication per node, sigma is
# almost entirely prior-driven (dunif(0,8) posterior mean landed ~3.9-4) and
# that ~4-point SD gets added on top of each arm's own (much smaller) trial
# SE. This is exactly the same "fixed-effect is the objectively correct
# choice for a star network" argument SKILL.md already documents for
# rand_effect->fixed_effect (model_random.txt/model_fixed.txt) -- it applies
# equally to model_simultaneous.txt's own delta structure, this file is the
# fixed-effect counterpart for the absolute-effect path.
#
# Must be run via scripts/run_with_jags.sh, not Rscript directly -- rjags
# needs the `jags` environment module loaded first in this environment.
#
# Usage:
#   scripts/run_with_jags.sh scripts/fit_bnma_model.R --batman <batman.rds> \
#     --model <model_random.txt|model_fixed.txt|model_simultaneous.txt|model_simultaneous_fixed.txt> --cache <samples.rds> [--force]

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

  # model_simultaneous.txt / model_simultaneous_fixed.txt additionally have a
  # pooled baseline mean `m` -- give it the same deliberate zero/random-from-
  # prior init treatment as phi.
  has_pooled_baseline <- basename(args$model) %in% c("model_simultaneous.txt", "model_simultaneous_fixed.txt")
  ns <- batman_data$ns
  M  <- batman_data$M

  #' Chain 1 -> exactly 0 ("no relationship between treatment and outcome",
  #' per the Guide). Chains 2+ -> random draws from the same Normal(0, SD=100)
  #' vague prior every phi[]/d[]/m node in these models actually uses.
  draw_from_vague_prior <- function(n, chain_num) {
    if (chain_num == 1) rep(0, n) else rnorm(n, mean = 0, sd = 100)
  }

  inits.list <- lapply(1:3, function(chain_num) {
    # d[1] is a deterministic constant (`d[1] <- 0`) in every model file --
    # NA in the init vector tells JAGS "no initial value for this element,"
    # which is required since you cannot supply one for a logical node.
    d_init <- c(NA, draw_from_vague_prior(M - 1, chain_num))
    init <- list(
      .RNG.seed = base_seed + chain_num, .RNG.name = "base::Wichmann-Hill",
      phi = draw_from_vague_prior(ns, chain_num),
      d   = d_init
    )
    if (has_pooled_baseline) init$m <- draw_from_vague_prior(1, chain_num)
    init
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
  # `sigma` (the between-study SD of the relative treatment effect, feeding
  # delta[i,j]'s variance -- standard NMA "tau", per the user 2026-08-19) is
  # monitored alongside sigma_m (baseline heterogeneity) so make_forest_plot.R
  # can report it on absolute-effect plots. model_simultaneous_fixed.txt has
  # no `sigma` node at all (delta[i,j] is deterministic there -- see its own
  # header comment) so it's excluded from that file's monitored set.
  variable_names <- if (basename(args$model) == "model_simultaneous.txt") {
    c("d", "phi", "delta", "m", "sigma", "sigma_m", "mu_new")
  } else if (basename(args$model) == "model_simultaneous_fixed.txt") {
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

