#!/usr/bin/env Rscript
# Step 5 of the /bnma skill: fit (or load a cached fit of) the BATMAN/JAGS
# random-effects NMA model.
#
# MCMC settings and chain initialization follow the NMA Output Review
# Process Guide (2026 V2, re-read 2026-08-19) rather than
# efficacy_bnma_v3_gzmu_misc5.R's own (lighter) settings -- confirmed
# neither CLAUDE.md nor GUIDE_README.md say anything to the contrary, and a
# second internal script (bnma_berobenatide_T2D.R) independently corroborates
# the Guide's burn-in and thinning:
#   - Burn-in 20,000 (Guide's Run 1/Run 2 examples AND bnma_berobenatide_T2D.R
#     both use 20,000; misc5's 10,000 is the outlier here).
#   - Thin 5 (the Guide's own stated default, "initially set to 5",
#     independently matched by bnma_berobenatide_T2D.R).
#   - Sampling iterations: the Guide's own examples range 100,000-200,000;
#     bnma_berobenatide_T2D.R uses 50,000. No single number is unanimous, so
#     50,000 (the smallest of the three, and the only one from an actual
#     recent obesity/BNMA-adjacent run rather than a documentation example)
#     is the new default -- still 2.5x this skill's old 20,000, and anyone
#     needing the Guide's heavier 100k/200k can still pass --n_iter directly.
#   - n.chains stays 3, matching the Guide's explicit "three chains of
#     initial values" (bnma_berobenatide_T2D.R's 4 chains is the outlier).
#   - Chain 1 gets deterministic zero initial values for the baseline (phi,
#     and m for model_simultaneous.txt) and treatment-effect (d) nodes;
#     chains 2+ get random draws from those same nodes' own vague priors
#     (Normal(0, SD=100)) -- verbatim per the Guide's stated procedure.
#     Nothing in bnma_berobenatide_T2D.R contradicts this (it just doesn't
#     specify explicit inits at all, so JAGS's own defaults apply there).
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
  n_burnin = list(default = "20000"),
  n_iter   = list(default = "50000"),
  thin     = list(default = "5"),
  seed     = list(default = "2026")
))

batman_data <- readRDS(args$batman)

if (file.exists(args$cache) && !args$force) {
  cat("Loading cached MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))
  base_seed <- as.integer(args$seed) * 1000

  # model_simultaneous.txt additionally has a pooled baseline mean `m` --
  # give it the same deliberate zero/random-from-prior init treatment as phi.
  has_pooled_baseline <- basename(args$model) == "model_simultaneous.txt"
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
  # can report it on absolute-effect plots.
  variable_names <- if (basename(args$model) == "model_simultaneous.txt") {
    c("d", "phi", "delta", "m", "sigma", "sigma_m", "mu_new")
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

# Convergence diagnostics -- always run, never skipped (same rule as every
# other gate in this skill). Written next to the cache file so it survives
# alongside the samples it describes; re-derived every time (cheap), even
# when loading a cached fit, so an old run that was never checked still
# gets checked on its next use.
diagnostics_path <- sub("\\.rds$", "_diagnostics.yaml", args$cache)
diag <- compute_convergence_diagnostics(samples)
print_convergence_diagnostics(diag)
yaml::write_yaml(
  c(
    list(generated_at = as.character(Sys.time()),
         samples_file = normalizePath(args$cache, mustWork = FALSE)),
    diag
  ),
  diagnostics_path
)
cat("Diagnostics written to:", diagnostics_path, "\n")

