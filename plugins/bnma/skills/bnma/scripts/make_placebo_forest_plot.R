#!/usr/bin/env Rscript
# QC plot for the standalone pooled-placebo model (fit_pooled_placebo_model.R)
# -- shows each contributing study's observed vs. posterior-shrunk placebo
# effect, the overall pooled estimate (m), and the predictive distribution
# for a hypothetical new study (mu_new). Adapted 2026-08-21 from a
# colleague's independent implementation on the `godwill-bnma` branch
# (make_placebo_forest_plot.R there), which mirrors the production app's own
# placebo_forest_plot() (CMH.BNMA R/plot_utils.R + R/mod_pooled_placebo.R).
#
# This is a real capability gap fit_pooled_placebo_model.R alone doesn't
# fill: make_forest_plot.R only ever *consumes* this model's m/sigma_m as an
# absolute-effect baseline, with no way to visually confirm the pooled model
# itself is sane (is shrinkage reasonable? is any one placebo study wildly
# discordant? does mu_new look plausible?) -- exactly the kind of check the
# "modelled, shrunk placebo level, not any single trial's observed placebo"
# footnote in make_forest_plot.R asks a reviewer to keep in mind, but gives
# them no picture of.
#
# Reads --placebo-data from fit_pooled_placebo_model.R's own
# --placebo-data-out (study_name/study_idx/y/se) rather than re-deriving the
# placebo subset independently -- single source of truth for which rows fed
# the fit, same reasoning as fit_pooled_placebo_model.R's own header comment.
#
# Usage:
#   Rscript make_placebo_forest_plot.R --samples <placebo_samples.rds> \
#     --placebo-data <placebo_data.rds> --manifest <manifest.yaml> \
#     --out <plot.png> [--title "..."] [--xlab "..."]

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(yaml)
  library(coda)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples      = list(required = TRUE),
  placebo_data = list(required = TRUE),
  manifest     = list(required = TRUE),
  out          = list(required = TRUE),
  title        = list(default = NULL),
  xlab         = list(default = NULL)
))

samples <- readRDS(args$samples)
placebo_data <- readRDS(args$placebo_data)
manifest <- yaml::read_yaml(args$manifest)

s <- summary(samples)
m_mean <- s$statistics["m", "Mean"]; m_lo <- s$quantiles["m", "2.5%"]; m_hi <- s$quantiles["m", "97.5%"]
sigma_mean <- s$statistics["sigma_m", "Mean"]; sigma_lo <- s$quantiles["sigma_m", "2.5%"]; sigma_hi <- s$quantiles["sigma_m", "97.5%"]
mu_new_mean <- s$statistics["mu_new", "Mean"]; mu_new_lo <- s$quantiles["mu_new", "2.5%"]; mu_new_hi <- s$quantiles["mu_new", "97.5%"]

mu_rows <- grepl("^mu\\[", rownames(s$statistics))
mu_summary <- data.frame(
  study_idx = as.integer(gsub("mu\\[(\\d+)\\]", "\\1", rownames(s$statistics)[mu_rows])),
  post_mean = s$statistics[mu_rows, "Mean"],
  post_lower = s$quantiles[mu_rows, "2.5%"],
  post_upper = s$quantiles[mu_rows, "97.5%"]
)

plot_data <- placebo_data %>%
  left_join(mu_summary, by = "study_idx") %>%
  mutate(
    obs_lower = y - 1.96 * se,
    obs_upper = y + 1.96 * se,
    Label = sprintf("%.1f (%.1f, %.1f)", post_mean, post_lower, post_upper)
  ) %>%
  arrange(study_name)

# Study rows (observed, hollow point) + posterior-shrunk estimate (filled
# point), so shrinkage is visible, not just stated -- plus a POOLED summary
# row and a NEW STUDY (PREDICTED) row for mu_new, so a reviewer sees both the
# historical pooled effect and what to expect next time without
# cross-referencing the console output.
study_order <- c("New study (predicted)", "Pooled (m)", rev(plot_data$study_name))

rows_obs <- plot_data %>% transmute(
  label = study_name, kind = "Observed", mean = y, lo = obs_lower, hi = obs_upper
)
rows_post <- plot_data %>% transmute(
  label = study_name, kind = "Posterior (shrunk)", mean = post_mean, lo = post_lower, hi = post_upper
)
rows_pooled <- data.frame(
  label = "Pooled (m)", kind = "Pooled", mean = m_mean, lo = m_lo, hi = m_hi
)
rows_new <- data.frame(
  label = "New study (predicted)", kind = "Predicted (mu_new)", mean = mu_new_mean, lo = mu_new_lo, hi = mu_new_hi
)

data_plot <- bind_rows(rows_obs, rows_post, rows_pooled, rows_new) %>%
  mutate(label = factor(label, levels = study_order))

effect_col <- manifest$effect_col %||% "pchg_wl_ee"
endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
xlab_text <- args$xlab %||% sprintf("Mean (95%% CI) Placebo Percent Change in %s (%%)", endpoint_label)
title_text <- args$title %||% sprintf("Pooled Placebo Effect: %s", endpoint_label)
subtitle_text <- sprintf(
  "Pooled m = %.2f%% (95%% CrI: %.2f, %.2f)   between-study SD (sigma_m) = %.2f (95%% CrI: %.2f, %.2f)",
  m_mean, m_lo, m_hi, sigma_mean, sigma_lo, sigma_hi
)

plot_width <- 9
# Wrap the caption to the plot's own width (~11 chars/inch at this caption's
# 8pt font, same estimate make_forest_plot.R uses) -- confirmed by testing:
# an unwrapped contributing-studies line silently clips at the panel edge
# rather than wrapping, exactly the kind of untraceable footnote this skill
# otherwise insists on getting right.
footnote_wrap_width <- max(40, floor(plot_width * 11))
caption_text <- paste(
  strwrap(paste0("Contributing studies: ", paste(sort(placebo_data$study_name), collapse = ", ")), width = footnote_wrap_width),
  collapse = "\n"
)
caption_text <- paste0(
  caption_text,
  "\n", paste(strwrap(paste0(
    "Source data: ", manifest$source_data$prd %||% "(not recorded)",
    if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""
  ), width = footnote_wrap_width), collapse = "\n"),
  "\n", paste(strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = footnote_wrap_width), collapse = "\n")
)

p <- ggplot(data_plot, aes(x = label, y = mean, ymin = lo, ymax = hi, color = kind, shape = kind)) +
  geom_pointrange(position = position_dodge(width = 0.4), size = 0.5) +
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.6) +
  scale_color_manual(values = c(
    "Observed" = "#7F8C8D", "Posterior (shrunk)" = "#1B4F72",
    "Pooled" = "#000000", "Predicted (mu_new)" = "#7B241C"
  )) +
  scale_shape_manual(values = c(
    "Observed" = 1, "Posterior (shrunk)" = 16, "Pooled" = 18, "Predicted (mu_new)" = 17
  )) +
  coord_flip() +
  xlab("") + ylab(xlab_text) +
  ggtitle(title_text, subtitle = subtitle_text) +
  labs(color = "", shape = "", caption = caption_text) +
  theme_bw() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 10, color = "grey35", hjust = 0.5),
    plot.caption = element_text(size = 8, hjust = 0, face = "italic"),
    legend.position = "bottom"
  )

plot_height <- max(4, 0.45 * length(study_order) + 2) + 0.15 * length(strsplit(caption_text, "\n")[[1]])
ggsave(args$out, plot = p, width = plot_width, height = plot_height, dpi = 150)

cat("Pooled placebo forest plot saved to:", args$out, "\n")
cat(sprintf("Pooled placebo effect (m): %.2f%% (95%% CrI: %.2f, %.2f)\n", m_mean, m_lo, m_hi))
cat(sprintf("Between-study SD (sigma_m): %.2f (95%% CrI: %.2f, %.2f)\n", sigma_mean, sigma_lo, sigma_hi))
cat(sprintf("Predicted placebo effect in a new study (mu_new): %.2f%% (95%% CrI: %.2f, %.2f)\n",
            mu_new_mean, mu_new_lo, mu_new_hi))
