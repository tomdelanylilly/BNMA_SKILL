#!/usr/bin/env Rscript
# Step 6 of the /bnma skill: forest plot from a fitted model's posterior,
# annotated with contributing studies and footnoted with the source
# data/program paths -- per GUIDE_README.md Flow 2 steps 5, 7, 8 (forest
# plots should show which studies fed the estimate; footnote the exact
# data/program paths so results trace back to a specific run).
#
# Usage:
#   Rscript make_forest_plot.R --samples <samples.rds> --arm-info <arm_info.rds> \
#     --study-info <study_info.rds> --manifest <manifest.yaml> \
#     --effect relative|absolute --out <plot.png> [--title "..."]

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(yaml)
  library(coda) # needed so as.matrix() dispatches as.matrix.mcmc.list correctly
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples     = list(required = TRUE),
  arm_info    = list(required = TRUE),
  study_info  = list(required = TRUE),
  manifest    = list(required = TRUE),
  effect      = list(default = "relative"),
  out         = list(required = TRUE),
  title       = list(default = NULL)
))

if (!args$effect %in% c("relative", "absolute")) {
  stop("--effect must be 'relative' or 'absolute', got: ", args$effect)
}

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)
study_info <- readRDS(args$study_info)
manifest <- yaml::read_yaml(args$manifest)

samples_mat <- as.matrix(samples)

plot_treatments <- manifest$plot_treatments
if (is.null(plot_treatments) || length(plot_treatments) == 0) {
  # Default: every non-placebo treatment that made it into the model, in the
  # order they were first seen -- an explicit `plot_treatments` list in the
  # manifest is how a curated subset/order is requested instead.
  plot_treatments <- arm_info %>% filter(treatment != "placebo") %>% pull(treatment) %>% unique()
}

arm_lookup <- arm_info %>%
  filter(treatment %in% c(plot_treatments, "placebo")) %>%
  group_by(arm_ind) %>% slice(1) %>% ungroup()

m_samples <- if (args$effect == "absolute") samples_mat[, "m"] else NULL

rows <- lapply(seq_len(nrow(arm_lookup)), function(i) {
  arm_k <- arm_lookup$arm_ind[i]
  trt_name <- arm_lookup$treatment[i]
  cmpd <- arm_lookup$compound[i]

  if (args$effect == "relative") {
    post <- if (arm_k == 1) rep(0, nrow(samples_mat)) else samples_mat[, paste0("d[", arm_k, "]")]
  } else {
    post <- if (arm_k == 1) m_samples else m_samples + samples_mat[, paste0("d[", arm_k, "]")]
  }

  data.frame(
    treatment = trt_name,
    compound = if (trt_name == "placebo") "placebo" else cmpd,
    mean = mean(post),
    val2.5pc = quantile(post, 0.025),
    val97.5pc = quantile(post, 0.975)
  )
})

data_plot <- bind_rows(rows) %>%
  filter(treatment %in% plot_treatments | (args$effect == "absolute" & treatment == "placebo")) %>%
  arrange(match(treatment, c("placebo", plot_treatments))) %>%
  mutate(Label = paste0(round(mean, 1), " (", round(val2.5pc, 1), ", ", round(val97.5pc, 1), ")"))

trt_order <- unique(data_plot$treatment)

ylab_text <- if (args$effect == "relative") {
  "Mean & 95% CI of Pbo-adj Percent Change in Body Weight (%)"
} else {
  "Mean & 95% CI of Absolute Percent Change in Body Weight (%)"
}
title_text <- args$title %||% paste0(
  if (args$effect == "relative") "Placebo-Adjusted" else "Absolute",
  " Percent Body Weight Change"
)

contributing_studies <- paste(sort(study_info$study_name), collapse = ", ")
footnote_lines <- c(
  strwrap(paste0("Contributing studies: ", contributing_studies), width = 120),
  strwrap(
    paste0(
      "Source data: ", manifest$source_data$prd %||% "(not recorded)",
      if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""
    ),
    width = 120
  ),
  strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = 120)
)
footnote_text <- paste(footnote_lines, collapse = "\n")

pforest <- ggplot(
  data_plot,
  aes(x = factor(treatment, levels = rev(trt_order)), y = mean, ymin = val2.5pc, ymax = val97.5pc)
) +
  geom_pointrange(aes(col = compound), size = 0.5) +
  geom_hline(yintercept = 0, size = 1, linetype = 2) +
  geom_text(aes(label = Label), position = position_dodge(width = 1), show.legend = FALSE, vjust = 1.6, size = 5) +
  coord_flip() +
  xlab("") +
  ylab(ylab_text) +
  ggtitle(title_text) +
  labs(caption = footnote_text) +
  theme_bw() +
  theme(
    axis.title = element_text(size = 16),
    axis.text = element_text(size = 14),
    plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
    plot.caption = element_text(size = 9, hjust = 0, face = "italic"),
    legend.text = element_text(size = 13),
    legend.title = element_text(size = 13)
  )

plot_height <- max(4, 0.6 * length(trt_order)) + 0.22 * length(footnote_lines)
ggsave(args$out, plot = pforest, width = 12, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote:\n", footnote_text, "\n")
