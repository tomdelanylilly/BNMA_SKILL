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
  title       = list(default = NULL),
  xlab        = list(default = NULL)
))

if (!args$effect %in% c("relative", "absolute")) {
  stop("--effect must be 'relative' or 'absolute', got: ", args$effect)
}

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)
study_info <- readRDS(args$study_info)
manifest <- yaml::read_yaml(args$manifest)

samples_mat <- as.matrix(samples)

# model_random.txt/model_fixed.txt (the real production models, confirmed
# 2026-08-17 via BNMA_forest_plot-main.zip) have no pooled baseline -- phi[i]
# is separate per study, so there's no single "m" to add d[k] to. Only
# model_simultaneous.txt (legacy hierarchical) has one. Check for it here
# rather than assuming, so a mismatched --effect absolute request fails
# loudly instead of erroring obscurely inside the m_samples lookup below.
if (args$effect == "absolute" && !("m" %in% colnames(samples_mat))) {
  stop(
    "--effect absolute needs a pooled baseline 'm' node, which only ",
    "model_simultaneous.txt has -- the real production rand_effect/",
    "fixed_effect models use a separate phi[i] per study with no pooling, ",
    "so there's no single global baseline to add d[k] to. Re-fit with ",
    "model_simultaneous.txt for absolute effects, or use --effect relative."
  )
}

# The pooled baseline used for absolute effects is the average of phi[i]
# across only the studies that actually have a real placebo arm -- NOT the
# model's own "m" node directly. m is drawn from every study's phi[i]
# including head-to-head trials with no placebo row at all, whose phi[i] is
# purely a hierarchical-prior artifact with nothing real anchoring it (found
# by testing, 2026-08-19: two no-placebo studies had phi[i] of -15 and -25
# against every real-placebo study's -3 to +1, dragging m from a plausible
# ~-2% to an implausible -5.9%). Falls back to m with a warning if
# study_info predates the has_placebo column (an older cached study_info.rds).
if (args$effect == "absolute") {
  if ("has_placebo" %in% colnames(study_info)) {
    placebo_studies <- study_info %>% filter(has_placebo) %>% pull(study_ind)
    phi_cols <- paste0("phi[", placebo_studies, "]")
    missing_phi <- setdiff(phi_cols, colnames(samples_mat))
    if (length(missing_phi) > 0) {
      stop("Expected phi columns not found in samples: ", paste(missing_phi, collapse = ", "))
    }
    m_samples <- rowMeans(samples_mat[, phi_cols, drop = FALSE])
    cat("Pooled baseline computed from", length(placebo_studies), "studies with a real placebo arm",
        "(excluded", nrow(study_info) - length(placebo_studies), "with none).\n")
  } else {
    warning("study_info.rds has no has_placebo column (predates this fix) -- falling back to the model's ",
            "own 'm' node directly, which may be contaminated by no-placebo studies' phi[i]. Rebuild ",
            "study_info.rds to get the corrected pooled baseline.")
    m_samples <- samples_mat[, "m"]
  }
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

ylab_text <- args$xlab %||% if (args$effect == "relative") {
  "Mean (95% CI) of Pbo-adj Percent Change in Body Weight (%)"
} else {
  "Mean (95% CI) of Absolute Percent Change in Body Weight (%)"
}
title_text <- args$title %||% paste0(
  if (args$effect == "relative") "Placebo-Adjusted" else "Absolute",
  " Percent Body Weight Change"
)

# Absolute-effect plots report the two parameters that number is actually
# built from -- the pooled placebo baseline (mu = m) and the between-study
# SD of the relative treatment effect (tau = sigma, standard NMA notation,
# per the user 2026-08-19) -- so a reviewer sees the method, not just the
# number. Soft-fails (omits the line, doesn't error the whole plot) if
# `sigma` isn't in this fit's samples -- true for any samples.rds cached
# before sigma was added to fit_bnma_model.R's monitored variables.
subtitle_text <- NULL
if (args$effect == "absolute") {
  mu_mean <- mean(m_samples); mu_ci <- quantile(m_samples, c(0.025, 0.975))
  mu_part <- sprintf("Absolute = pooled placebo μ (%.1f%%; 95%% CrI: %.1f, %.1f) + d[j]",
                      mu_mean, mu_ci[1], mu_ci[2])
  if ("sigma" %in% colnames(samples_mat)) {
    tau_mean <- mean(samples_mat[, "sigma"]); tau_ci <- quantile(samples_mat[, "sigma"], c(0.025, 0.975))
    subtitle_text <- sprintf("%s    τ = %.2f (95%% CrI: %.2f, %.2f)", mu_part, tau_mean, tau_ci[1], tau_ci[2])
  } else {
    # No 'sigma' column can mean either: (a) this fit used
    # model_simultaneous_fixed.txt, where delta[i,j] is deterministic by
    # design -- there's no tau to report, not an omission; or (b) an older
    # samples.rds cached before sigma was added to model_simultaneous.txt's
    # monitored variables. Can't tell which from samples_mat alone, so the
    # message covers both rather than asserting the wrong one.
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
# Any compound NOT in this list (this skill has plotted 20+ over the
# session) falls back to a distinct auto-generated color rather than
# erroring or rendering as NA -- extend FIXED_COMPOUND_COLORS here as more
# reference conventions are confirmed.
FIXED_COMPOUND_COLORS <- c(
  semaglutide  = "#7B241C",
  cagrisema    = "#1B4F72",
  maritide     = "#D68910",
  retatrutide  = "#000000",
  berobenatide = "#E74C3C",
  tirzepatide  = "#85C1E9",
  placebo      = "#7F8C8D"
)
compounds_in_plot <- unique(data_plot$compound)
unmapped_compounds <- setdiff(compounds_in_plot, names(FIXED_COMPOUND_COLORS))
fallback_colors <- if (length(unmapped_compounds) > 0) {
  setNames(scales::hue_pal()(length(unmapped_compounds)), unmapped_compounds)
} else {
  character(0)
}
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


plot_height <- max(4, 0.6 * length(trt_order)) + 0.22 * length(footnote_lines)
# n_compounds/max_label_chars/plot_width already computed above (needed
# earlier to size the footnote's wrap width) -- reused here, not recomputed.
ggsave(args$out, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote:\n", footnote_text, "\n")
