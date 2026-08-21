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
  samples          = list(required = TRUE),
  arm_info         = list(required = TRUE),
  study_info       = list(required = TRUE),
  manifest         = list(required = TRUE),
  effect           = list(default = "relative"),
  placebo_samples  = list(default = NULL),
  out              = list(required = TRUE),
  title            = list(default = NULL),
  xlab             = list(default = NULL)
))

if (!args$effect %in% c("relative", "absolute")) {
  stop("--effect must be 'relative' or 'absolute', got: ", args$effect)
}

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)
study_info <- readRDS(args$study_info)
manifest <- yaml::read_yaml(args$manifest)

samples_mat <- as.matrix(samples)

# The absolute-effect baseline comes from a SEPARATE, standalone pooled-
# placebo model (scripts/fit_pooled_placebo_model.R), not from this model's
# own fit -- adopted 2026-08-20 from the real production package's own
# pooled-placebo feature (EliLillyCo/CMH.BNMA). This decouples --effect
# absolute from model_type entirely: model_random.txt/model_fixed.txt (the
# real production relative-effect models) have no pooled baseline of their
# own at all, so this is what actually makes absolute effects available for
# them, not just the legacy model_simultaneous.txt/model_simultaneous_fixed.txt
# (which still work fine here too -- this doesn't care what the main model
# was).
#
# Superseded: averaging phi[i] across only real-placebo studies from
# model_simultaneous.txt's OWN fit (2026-08-19) -- correct in spirit
# (excluding no-placebo studies' contaminated phi[i]) but architecturally
# coupled to one specific legacy model file. A genuinely independent fit
# that only ever sees placebo data is cleaner and works everywhere.
if (args$effect == "absolute") {
  if (is.null(args$placebo_samples)) {
    stop(
      "--effect absolute needs --placebo-samples <path> -- the cached fit from ",
      "scripts/fit_pooled_placebo_model.R (run it first against this run's ",
      "arm_rows.rds if you haven't already)."
    )
  }
  if (!file.exists(args$placebo_samples)) {
    stop("--placebo-samples file not found: ", args$placebo_samples)
  }
  placebo_samples_mat <- as.matrix(readRDS(args$placebo_samples))
  if (!"m" %in% colnames(placebo_samples_mat)) {
    stop("--placebo-samples file has no 'm' node -- was it really fit from model_placebo_random.txt?")
  }
  # Resample to this fit's own draw count so `m_samples + d_samples` below is
  # a valid elementwise Monte Carlo combination of two independent
  # posteriors, regardless of the two models' differing chain lengths/thin
  # (the placebo model deliberately uses a lighter MCMC budget -- see its
  # own script header).
  m_samples <- sample(placebo_samples_mat[, "m"], nrow(samples_mat), replace = TRUE)
  sigma_m_samples <- sample(placebo_samples_mat[, "sigma_m"], nrow(samples_mat), replace = TRUE)
  cat("Pooled placebo baseline loaded from", args$placebo_samples,
      "-- mean m =", round(mean(m_samples), 3), "\n")
}

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

# Observed/projection/supplementary marker -- a superscript on the axis
# label itself, so a reviewer QC'ing the PNG doesn't have to cross-reference
# the manifest to know which arms are real trial data, modeled, or hand-added
# (see supplementary_data in SKILL.md). evidence_type is the sorted,
# comma-joined set of distinct sources feeding this arm (build_batman_data.R)
# -- map each token through type_code and rejoin, so any combination (not
# just the observed+prediction pair this used to hardcode) renders correctly,
# e.g. "observed,supplementary" -> "^o,s^".
type_code <- c(observed = "o", prediction = "p", supplementary = "s")
data_plot <- data_plot %>%
  mutate(
    evidence_marker = vapply(evidence_type, function(et) {
      if (is.na(et) || !nzchar(et)) return("")
      codes <- type_code[strsplit(et, ",")[[1]]]
      paste0("^", paste(codes, collapse = ","), "^")
    }, character(1)),
    treatment_label = paste0(treatment, evidence_marker)
  )

range_span <- max(data_plot$val97.5pc, na.rm = TRUE) - min(data_plot$val2.5pc, na.rm = TRUE)

trt_order <- unique(data_plot$treatment_label)

# Default axis/title text templates assume a "percent change" endpoint
# (weight loss, HbA1c reduction, etc.) -- this is a template, not a
# universal label: an endpoint that isn't naturally a percent change (e.g. a
# raw physical-function score) will render a technically-present but
# semantically-wrong "(%)" via this default. --xlab/--title always override
# it regardless, so use those explicitly for any endpoint this template
# doesn't fit rather than trying to make one template cover every shape.
effect_col <- manifest$effect_col %||% "pchg_wl_ee"
endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
ylab_text <- args$xlab %||% sprintf(
  "Mean (95%% CI) of %s Percent Change in %s (%%)",
  if (args$effect == "relative") "Pbo-adj" else "Absolute",
  endpoint_label
)
title_text <- args$title %||% sprintf(
  "%s Percent %s Change",
  if (args$effect == "relative") "Placebo-Adjusted" else "Absolute",
  endpoint_label
)

# Absolute-effect plots report the two parameters that number is actually
# built from -- the pooled placebo baseline (mu = m, sigma_mu = the standalone
# placebo model's own between-study SD of the placebo response) and the
# between-study SD of the relative treatment effect (tau = sigma, standard
# NMA notation, per the user 2026-08-19) -- so a reviewer sees the method,
# not just the number. The tau half soft-fails (omits that clause, doesn't
# error the whole plot) if `sigma` isn't in the MAIN model's samples -- true
# for a fixed-effect delta model, or an older samples.rds cached before
# sigma was added to fit_bnma_model.R's monitored variables.
subtitle_text <- NULL
if (args$effect == "absolute") {
  mu_mean <- mean(m_samples); mu_ci <- quantile(m_samples, c(0.025, 0.975))
  sigma_mu_mean <- mean(sigma_m_samples)
  mu_part <- sprintf(
    "Absolute = pooled placebo μ (%.1f%%; 95%% CrI: %.1f, %.1f; between-study σ=%.2f, standalone placebo-only model) + d[j]",
    mu_mean, mu_ci[1], mu_ci[2], sigma_mu_mean
  )
  if ("sigma" %in% colnames(samples_mat)) {
    tau_mean <- mean(samples_mat[, "sigma"]); tau_ci <- quantile(samples_mat[, "sigma"], c(0.025, 0.975))
    subtitle_text <- sprintf("%s    τ = %.2f (95%% CrI: %.2f, %.2f)", mu_part, tau_mean, tau_ci[1], tau_ci[2])
  } else {
    # No 'sigma' column can mean either: (a) this fit used a deterministic-
    # delta model (model_fixed.txt/model_simultaneous_fixed.txt), where
    # there's no tau to report, not an omission; or (b) an older samples.rds
    # cached before sigma was added to the main model's monitored variables.
    # Can't tell which from samples_mat alone, so the message covers both
    # rather than asserting the wrong one.
    subtitle_text <- paste0(mu_part, "    (no τ for this fit -- either a fixed-effect delta model, or refit to capture 'sigma')")
  }
}

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

# Subtitle uses an 11pt font (vs. the caption's 9pt) -- wider characters, so
# reuse the same physical-width logic scaled down proportionally (~9 chars/
# inch instead of ~11) rather than a fixed character count, same reasoning
# as the footnote's own wrap width above. Found by testing, 2026-08-20: the
# absolute-effect subtitle's added between-study-sigma clause pushed it past
# the plot width, silently clipped rather than wrapped.
if (!is.null(subtitle_text)) {
  subtitle_wrap_width <- max(40, floor(plot_width * 9))
  subtitle_text <- paste(strwrap(subtitle_text, width = subtitle_wrap_width), collapse = "\n")
}

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
footnote_lines <- c(footnote_lines, "^o^ = observed, ^p^ = projection, ^s^ = supplementary (hand-added, not yet in QA/PRD)")
# ggtext's markdown parser (needed for the axis superscripts) treats a bare
# "\n" as a soft wrap, not a forced line break -- confirmed by testing: with
# "\n" the whole caption collapsed onto one line and got clipped by the
# panel edge rather than wrapping. "<br>" is the actual forced-break syntax
# it respects.
footnote_text <- paste(footnote_lines, collapse = "<br>")

# Reference palette (2026-08-19, per the user's team-standard T2D forest
# plot): fixed, named colors for the compounds it showed, so our output
# lines up with that convention exactly rather than an auto-assigned hue.
# This is a weight-loss/obesity-landscape compound convention specifically,
# not tied to the endpoint being plotted -- an HbA1c or physical-function run
# on these same compounds still gets these colors; a run on unrelated
# compounds (a different drug class) just falls through to
# generate_fallback_colors() below, same as any other unlisted compound.
# Any compound NOT in this list falls back to a distinct auto-generated
# color rather than erroring or rendering as NA -- extend
# FIXED_COMPOUND_COLORS here as more reference conventions are confirmed
# (vk2735/brenipatide added 2026-08-20, deliberately NOT their raw hue_pal()
# fallback [scales::hue_pal() was this skill's fallback before also being
# replaced 2026-08-20, see below] -- the auto-generated vk2735 hue landed
# visually close to berobenatide's already-fixed red, so it was assigned a
# separated purple instead; brenipatide's auto teal was already
# well-separated and kept as-is).
FIXED_COMPOUND_COLORS <- c(
  semaglutide  = "#7B241C",
  cagrisema    = "#1B4F72",
  maritide     = "#D68910",
  retatrutide  = "#000000",
  berobenatide = "#E74C3C",
  tirzepatide  = "#85C1E9",
  vk2735       = "#6C3483",
  brenipatide  = "#00BFC4",
  placebo      = "#7F8C8D"
)
compounds_in_plot <- unique(data_plot$compound)
unmapped_compounds <- setdiff(compounds_in_plot, names(FIXED_COMPOUND_COLORS))
# Fallback for any compound not in the team-standard fixed list: matches the
# real production package's own generate_color_palette() (2026-08-20,
# EliLillyCo/CMH.BNMA/R/plot_utils.R) -- RColorBrewer "Set3", darkened 0.3,
# extended via colorRampPalette beyond 12 compounds. Confirmed this is what
# feeds mod_model_forest.R's own BNMA results forest plot specifically (NOT
# build_color_map()'s dose-shaded palette, which turned out to feed an
# unrelated raw-data bar chart, mod_group_barchart.R -- checked the call
# sites directly rather than assuming from the function's name/vicinity).
# Replaces this skill's own prior scales::hue_pal() fallback.
generate_fallback_colors <- function(compounds) {
  n <- length(compounds)
  if (n == 0) return(character(0))
  base_colors <- RColorBrewer::brewer.pal(max(min(n, 12), 3), "Set3")
  if (n > 12) {
    base_colors <- grDevices::colorRampPalette(RColorBrewer::brewer.pal(12, "Set3"))(n)
  }
  setNames(colorspace::darken(base_colors[seq_len(n)], amount = 0.3), compounds)
}
fallback_colors <- generate_fallback_colors(unmapped_compounds)
compound_colors <- c(FIXED_COMPOUND_COLORS, fallback_colors)

pforest <- ggplot(
  data_plot,
  aes(x = factor(treatment_label, levels = rev(trt_order)), y = mean, ymin = val2.5pc, ymax = val97.5pc)
) +
  geom_pointrange(aes(col = compound), size = 0.5) +
  geom_hline(yintercept = 0, linewidth = 1, linetype = 2) +
  # Label sits directly above its own point (nudged along the categorical
  # axis, pre-flip that's "x") rather than in a fixed side column -- matches
  # the reference plot's layout. Nudging by a fraction of a row (0.32) keeps
  # it inside that row's own band, clear of the neighboring row's point.
  geom_text(
    aes(y = mean, label = Label),
    position = position_nudge(x = 0.32), vjust = 0, size = 4.2, color = "black", show.legend = FALSE
  ) +
  scale_color_manual(values = compound_colors, name = "Compound") +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.08))) +
  scale_x_discrete(expand = expansion(add = c(0.6, 0.6))) +
  coord_flip() +
  xlab("") +
  ylab(ylab_text) +
  ggtitle(title_text, subtitle = subtitle_text) +
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
    plot.subtitle = element_text(size = 11, color = "grey35", hjust = 0.5),
    plot.caption = ggtext::element_markdown(size = 9, hjust = 0, face = "italic"),
    legend.text = element_text(size = 13),
    legend.title = element_text(size = 13)
  )


subtitle_lines <- if (is.null(subtitle_text)) 0 else lengths(regmatches(subtitle_text, gregexpr("\n", subtitle_text))) + 1
plot_height <- max(4, 0.6 * length(trt_order)) + 0.22 * length(footnote_lines) + 0.18 * subtitle_lines
# n_compounds/max_label_chars/plot_width already computed above (needed
# earlier to size the footnote's wrap width) -- reused here, not recomputed.
ggsave(args$out, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote:\n", footnote_text, "\n")
