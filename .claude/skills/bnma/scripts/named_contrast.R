#!/usr/bin/env Rscript
# Ad hoc utility: resolves a contrast between two treatments BY NAME from a
# fitted model's posterior, never by a hardcoded d[k] index. Adapted from
# the atlas branch's named_contrast.R -- replaces the exact anti-pattern
# atlas calls out: `TZP15_vs_Sema72 <- d[18] - d[89]`, a hardcoded posterior
# index that silently goes wrong if treatment order shifts between runs.
#
# Not a numbered pipeline step -- use whenever a specific head-to-head
# comparison is needed from an already-fitted run.
#
# Usage:
#   scripts/run_r.sh scripts/named_contrast.R \
#     --samples <samples.rds> --arm-info <arm_info.rds> \
#     --treat1 "vk2735 10mg oral" --treat2 "vk2735 10mg qw" [--out <contrast.yaml>]

suppressPackageStartupMessages({
  library(coda)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples  = list(required = TRUE),
  arm_info = list(required = TRUE),
  treat1   = list(required = TRUE),
  treat2   = list(required = TRUE),
  out      = list(default = NULL)
))

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)

cn <- colnames(samples[[1]])
samples_mat <- do.call(rbind, lapply(samples, function(x) x[, , drop = FALSE]))
colnames(samples_mat) <- cn

find_arm <- function(name) {
  k <- arm_info$arm_ind[tolower(arm_info$treatment) == tolower(name)]
  if (length(k) == 0) {
    stop(
      "Treatment not found in this network's arm_info: '", name, "'. ",
      "Available: ", paste(head(sort(unique(arm_info$treatment)), 15), collapse = ", "),
      if (length(unique(arm_info$treatment)) > 15) ", ..." else ""
    )
  }
  k[1]
}

k1 <- find_arm(args$treat1)
k2 <- find_arm(args$treat2)

d1_col <- paste0("d[", k1, "]")
d2_col <- paste0("d[", k2, "]")
if (!d1_col %in% colnames(samples_mat)) stop("Node ", d1_col, " (", args$treat1, ") not in samples.")
if (!d2_col %in% colnames(samples_mat)) stop("Node ", d2_col, " (", args$treat2, ") not in samples.")

diff <- samples_mat[, d1_col] - samples_mat[, d2_col]
mean_diff <- mean(diff)
ci <- quantile(diff, c(0.025, 0.975))
p_treat1_better <- mean(diff < 0)

cat(sprintf("%s vs %s\n", args$treat1, args$treat2))
cat(sprintf("  contrast (arm_ind %d - arm_ind %d): %.2f (%.2f, %.2f)\n",
            k1, k2, mean_diff, ci[1], ci[2]))
cat(sprintf("  P(%s better) = %.3f\n", args$treat1, p_treat1_better))

if (!is.null(args$out)) {
  write_yaml(
    list(
      generated_at = as.character(Sys.time()),
      treat1 = args$treat1, treat2 = args$treat2,
      arm_ind1 = k1, arm_ind2 = k2,
      mean = round(mean_diff, 3), ci_lo = round(ci[1], 3), ci_hi = round(ci[2], 3),
      p_treat1_better = round(p_treat1_better, 3)
    ),
    args$out
  )
  cat("Written to:", args$out, "\n")
}
