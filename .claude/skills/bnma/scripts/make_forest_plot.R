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
  library(ggtext) # renders the observed/projection superscript markers as real superscripts
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
    evidence_type = arm_lookup$evidence_type[i],
    mean = mean(post),
    val2.5pc = quantile(post, 0.025),
    val97.5pc = quantile(post, 0.975)
  )
})

data_plot <- bind_rows(rows) %>%
  filter(treatment %in% plot_treatments | (args$effect == "absolute" & treatment == "placebo")) %>%
  arrange(match(treatment, c("placebo", plot_treatments))) %>%
  mutate(Label = paste0(round(mean, 1), " (", round(val2.5pc, 1), ", ", round(val97.5pc, 1), ")"))

# Observed/projection marker -- a superscript on the axis label itself, so a
# reviewer QC'ing the PNG doesn't have to cross-reference the manifest to
# know which arms are real trial data vs. modeled. "mixed" (e.g. the shared
# placebo arm, fed by both an observed and a prediction study in the same
# run) shows both letters -- that's the honest answer, not a simplification.
data_plot <- data_plot %>%
  mutate(
    evidence_marker = case_when(
      evidence_type == "observed"   ~ "^o^",
      evidence_type == "prediction" ~ "^p^",
      evidence_type == "mixed"      ~ "^o,p^",
      TRUE ~ ""
    ),
    treatment_label = paste0(treatment, evidence_marker)
  )

range_span <- max(data_plot$val97.5pc, na.rm = TRUE) - min(data_plot$val2.5pc, na.rm = TRUE)
# The leading "-" of a left-aligned label starting too close to the panel's
# own clip boundary gets sliced off (visible as a missing minus sign on the
# mean, while the CI numbers further right in the same string render fine) --
# 0.04 wasn't enough clearance; push the column further inside the panel.
data_plot$label_x <- max(data_plot$val97.5pc, na.rm = TRUE) + 0.12 * range_span
label_margin <- range_span * (0.12 + 0.018 * max(nchar(data_plot$Label)))

trt_order <- unique(data_plot$treatment_label)

ylab_text <- if (args$effect == "relative") {
  "Mean & 95% CI of Pbo-adj Percent Change in Body Weight (%)"
} else {
  "Mean & 95% CI of Absolute Percent Change in Body Weight (%)"
}
title_text <- args$title %||% paste0(
  if (args$effect == "relative") "Placebo-Adjusted" else "Absolute",
  " Percent Body Weight Change"
)

# Plot width must be known before the footnote is wrapped -- strwrap()'s
# `width` is a character count, and a fixed value (e.g. 120) doesn't
# actually fit the physical plot width once that varies per run (few
# compounds/short labels -> narrow plot -> 120 chars overflows the panel and
# gets clipped, not wrapped -- caught by testing, not assumed). ~11
# characters per inch is a rough estimate for this caption's 9pt font.
n_compounds <- length(unique(data_plot$compound))
max_label_chars <- max(nchar(data_plot$Label))
plot_width <- 10 + 0.15 * max_label_chars + 0.25 * n_compounds
footnote_wrap_width <- max(40, floor(plot_width * 11))

contributing_studies <- paste(sort(study_info$study_name), collapse = ", ")
footnote_lines <- c(
  strwrap(paste0("Contributing studies: ", contributing_studies), width = footnote_wrap_width),
  strwrap(
    paste0(
      "Source data: ", manifest$source_data$prd %||% "(not recorded)",
      if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""
    ),
    width = footnote_wrap_width
  ),
  strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = footnote_wrap_width)
)
footnote_lines <- c(footnote_lines, "^o^ = observed, ^p^ = projection")
# ggtext's markdown parser (needed for the axis superscripts) treats a bare
# "\n" as a soft wrap, not a forced line break -- confirmed by testing: with
# "\n" the whole caption collapsed onto one line and got clipped by the
# panel edge rather than wrapping. "<br>" is the actual forced-break syntax
# it respects.
footnote_text <- paste(footnote_lines, collapse = "<br>")

pforest <- ggplot(
  data_plot,
  aes(x = factor(treatment_label, levels = rev(trt_order)), y = mean, ymin = val2.5pc, ymax = val97.5pc)
) +
  geom_pointrange(aes(col = compound), size = 0.5) +
  geom_hline(yintercept = 0, size = 1, linetype = 2) +
  # A single fixed label column (all labels start at the same y, just past
  # the widest upper CI in the whole plot) rather than positioning each
  # label relative to its own point/CI -- anchoring per-row breaks down as
  # soon as one row is the most extreme in the plot (its label has nowhere
  # to go on that side) or has a very wide CI (the label ends up floating
  # far from its own point). A fixed column is what forest plots normally
  # use for exactly this reason.
  geom_text(
    aes(y = label_x, label = Label), hjust = 0, vjust = 0.5, size = 5, show.legend = FALSE
  ) +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.05), add = c(0, label_margin))) +
  coord_flip() +
  xlab("") +
  ylab(ylab_text) +
  ggtitle(title_text) +
  labs(caption = footnote_text) +
  theme_bw() +
  theme(
    axis.title = element_text(size = 16),
    # Empirically (tested, not assumed): after coord_flip(), axis.text.y is
    # what actually styles the categorical treatment_label axis (rendered on
    # the left) -- axis.text.x styling the same aes was tried first and
    # silently did nothing, so don't "simplify" this back on a hunch.
    # element_markdown() is what renders "^o^"/"^p^" as real superscripts
    # instead of literal caret text.
    axis.text.y = ggtext::element_markdown(size = 14),
    axis.text.x = element_text(size = 14),
    plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
    plot.caption = ggtext::element_markdown(size = 9, hjust = 0, face = "italic"),
    legend.text = element_text(size = 13),
    legend.title = element_text(size = 13)
  )

plot_height <- max(4, 0.6 * length(trt_order)) + 0.22 * length(footnote_lines)
# n_compounds/max_label_chars/plot_width already computed above (needed
# earlier to size the footnote's wrap width) -- reused here, not recomputed.
ggsave(args$out, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote:\n", footnote_text, "\n")
