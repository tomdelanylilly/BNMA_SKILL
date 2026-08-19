#!/usr/bin/env Rscript
# Step 3+4 of the /bnma skill: apply a confirmed study-selection manifest to
# the merged data, then BATMAN-augment and build the JAGS input matrices.
#
# The manifest (written by the skill conversation after the user explicitly
# confirms study inclusion/exclusion -- see SKILL.md) must list EVERY study
# present in the usable merged data. This script validates that and REFUSES
# TO RUN otherwise -- that hard failure is what makes "no silent default
# selection" a real guarantee instead of a social convention, closing the
# gap that let a low-dose Phase 2 study slip into a prior analysis unnoticed.
#
# Usage:
#   Rscript build_batman_data.R --data <merged.rds> --manifest <manifest.yaml> \
#     --batman-out <batman.rds> --arm-info-out <arm_info.rds> --study-info-out <study_info.rds>

suppressPackageStartupMessages({
  library(dplyr)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  data            = list(required = TRUE),
  manifest        = list(required = TRUE),
  batman_out      = list(required = TRUE),
  arm_info_out    = list(required = TRUE),
  study_info_out  = list(required = TRUE)
))

merged <- readRDS(args$data)
manifest <- yaml::read_yaml(args$manifest)

if (is.null(manifest$studies) || length(manifest$studies) == 0) {
  stop(
    "Manifest has no `studies` entries. Every study found in the data must ",
    "have an explicit include/exclude decision before a model can be run -- ",
    "see SKILL.md step 3."
  )
}

# SE fallback -- derive se_wl_ee = sd/sqrt(n) for rows missing se_wl_ee but
# with a known arm sample size n. This is a real, repeated team convention,
# not a one-off: redefine1's own curator_note documents it verbatim ("se is
# calculated with 10/sqrt(n) where sd=10 is commonly used for %change in
# body weight in nont2d"), and it's actually *applied* (not just written
# down) in brenipatide_gzmu_misc5.R and brenipatide_gzmu_gzmd.R. Runs before
# the unusable-row filter below so a rescued row survives it, same as any
# row that already had a real se_wl_ee. Opt-in and reasoned, same pattern as
# placebo_clamp -- unlike placebo_clamp, this is judged common enough across
# real datasets to offer as a standing manifest field rather than a
# one-off (per the user, 2026-08-19), but it still defaults to off:
# fabricating an SE for a row that never had a data-quality decision made
# about it must be a deliberate, visible choice, not silent.
if (isTRUE(manifest$se_fallback)) {
  if (is.null(manifest$se_fallback_reason) || !nzchar(trimws(manifest$se_fallback_reason))) {
    stop(
      "se_fallback is true but se_fallback_reason is missing/blank -- this can ",
      "rewrite an arbitrary number of rows' se_wl_ee values, so (like ",
      "placebo_clamp) it needs a documented reason, not just a logged default."
    )
  }
  fallback_sd <- as.numeric(manifest$se_fallback_sd %||% 10)
  se_num <- suppressWarnings(as.numeric(merged$se_wl_ee))
  n_num  <- suppressWarnings(as.numeric(merged$n))
  needs_fallback <- is.na(se_num) & !is.na(n_num) & n_num > 0
  n_rescued <- sum(needs_fallback)
  if (n_rescued > 0) {
    rescued_studies <- unique(merged$study_name[needs_fallback])
    cat(
      n_rescued, "row(s) with missing se_wl_ee but known n given a derived SE (",
      fallback_sd, "/ sqrt(n)) -- reason:", manifest$se_fallback_reason, "\n",
      "  Affected studies:", paste(rescued_studies, collapse = ", "), "\n"
    )
    merged$se_wl_ee[needs_fallback] <- fallback_sd / sqrt(n_num[needs_fallback])
  }
}

# Rows unusable regardless of any selection decision (not a study-selection
# choice, just a data-quality precondition) -- same filter the existing
# misc5 scripts apply, made explicit and logged here.
usable <- merged %>% filter(!is.na(suppressWarnings(as.numeric(se_wl_ee))))
dropped_unusable <- setdiff(unique(merged$study_name), unique(usable$study_name))
if (length(dropped_unusable) > 0) {
  cat(
    "Dropped as unusable (non-numeric/missing se_wl_ee for every row):\n  ",
    paste(dropped_unusable, collapse = ", "), "\n"
  )
}

# Supplementary data -- literal rows for data that hasn't been promoted into
# the QA/PRD workbook yet (e.g. a hand-digitized dose-response series from a
# slide deck). Found via bnma-nonadj-11AUG2026.R, which bind_rows() a
# hand-typed brenipatide tibble straight into its analysis with no
# traceability; this is the same capability, but as an explicit, reasoned
# manifest entry instead of a silent literal in a script. Bound in here,
# before row_exclusions/relabels/placebo_clamp/the scope filters, so these
# rows flow through the entire normal pipeline just like any other row --
# the only exemption is evidence_filter (see below), since "supplementary"
# isn't a meaningful point on the observed/prediction axis.
if (!is.null(manifest$supplementary_data)) {
  required_fields <- c("study_name", "treatment", "compound", "pchg_wl_ee", "se_wl_ee", "reason")
  supp_rows <- lapply(seq_along(manifest$supplementary_data), function(i) {
    entry <- manifest$supplementary_data[[i]]
    missing_fields <- setdiff(required_fields, names(entry))
    if (length(missing_fields) > 0) {
      stop(
        "supplementary_data entry ", i, " is missing required field(s): ",
        paste(missing_fields, collapse = ", "), " -- every entry needs ",
        paste(required_fields, collapse = ", "), "."
      )
    }
    data.frame(
      # Normalized the same way load_merge_data.R normalizes every other
      # row (tolower + squish_ws) -- otherwise a supplementary row's
      # study_name/treatment/compound/aom could silently fail to match the
      # manifest's studies:/plot_treatments/route_filter comparisons purely
      # on casing or stray whitespace.
      study_name = tolower(squish_ws(entry$study_name)),
      treatment = tolower(squish_ws(entry$treatment)),
      compound = tolower(squish_ws(entry$compound)),
      pchg_wl_ee = as.numeric(entry$pchg_wl_ee),
      se_wl_ee = as.numeric(entry$se_wl_ee),
      aom = if (is.null(entry$aom)) NA_character_ else tolower(squish_ws(entry$aom)),
      region = tolower(squish_ws(entry$region %||% "global")),
      source_tier = "supplementary",
      source_sheet = "supplementary",
      stringsAsFactors = FALSE
    )
  })
  supp_df <- bind_rows(supp_rows)
  cat(
    "Supplementary data: ", nrow(supp_df), " hand-added row(s) across ",
    n_distinct(supp_df$study_name), " study/ies:\n"
  )
  for (i in seq_along(manifest$supplementary_data)) {
    entry <- manifest$supplementary_data[[i]]
    cat("  ", entry$study_name, "/", entry$treatment, " -- reason:", entry$reason, "\n")
  }
  usable <- bind_rows(usable, supp_df)
}

# Row-level exclusions (e.g. a single anomalous/likely-erroneous row within an
# otherwise-included study) -- a study-level include/exclude decision can't
# express this, so the manifest supports an optional `row_exclusions` list.
# Every entry must actually match a row still present at this point, or the
# script stops -- silently matching zero rows (e.g. a stale exclusion after
# the underlying data changed) is exactly the kind of quiet drift this skill
# exists to prevent. An optional `n` field disambiguates two literal duplicate
# rows sharing the same (study_name, treatment) -- found via testing against
# real data (solstice's elecoglipron 75mg qd had two identical-looking rows
# differing only in n and the reported value). Without `n`, an entry matching
# more than one row is ALSO an error -- ambiguous exclusions are exactly as
# unsafe as ones matching zero.
#
# MANIFEST AUTHORING GOTCHA: write the key as quoted `"n": 37`, not bare
# `n: 37` -- YAML 1.1 (which the `yaml` package follows) parses a bare `n`
# (also `y`/`yes`/`no`/`on`/`off`) as the boolean FALSE, not the string "n",
# so an unquoted key silently vanishes and this block never disambiguates
# anything. Hit this exact bug once already; quoting the key is what fixes it.
if (!is.null(manifest$row_exclusions)) {
  for (ex in manifest$row_exclusions) {
    match_idx <- which(usable$study_name == ex$study_name & usable$treatment == ex$treatment)
    if (!is.null(ex$n)) {
      match_idx <- match_idx[usable$n[match_idx] == ex$n]
    }
    if (length(match_idx) == 0) {
      stop(
        "row_exclusions entry matched no rows: study_name='", ex$study_name,
        "', treatment='", ex$treatment, "'",
        if (!is.null(ex$n)) paste0(", n=", ex$n) else "",
        " -- check the manifest against the current data (it may have ",
        "changed since this exclusion was written)."
      )
    }
    if (length(match_idx) > 1) {
      stop(
        "row_exclusions entry matched ", length(match_idx), " rows (ambiguous): ",
        "study_name='", ex$study_name, "', treatment='", ex$treatment, "' -- add ",
        "an `n` field (or another discriminator) to pick exactly one row."
      )
    }
    cat(
      "Excluding", length(match_idx), "row(s): study='", ex$study_name,
      "' treatment='", ex$treatment, "' -- reason:", ex$reason %||% "(none given)", "\n"
    )
    usable <- usable[-match_idx, ]
  }
}


# Compound relabels -- for a naming-QA flag resolved as "these rows were
# mislabeled, merge into the canonical spelling" (as opposed to "these are
# genuinely different compounds, just noted"). Applied globally by compound
# string, since that's what the naming-QA gate flags on. Same
# match-or-stop-loudly guarantee as row_exclusions above.
if (!is.null(manifest$compound_relabels)) {
  for (rl in manifest$compound_relabels) {
    match_idx <- which(usable$compound == rl$from)
    if (length(match_idx) == 0) {
      stop(
        "compound_relabels entry matched no rows: from='", rl$from, "' -- check ",
        "the manifest against the current data (it may have changed since this ",
        "relabel was written)."
      )
    }
    cat(
      "Relabeling", length(match_idx), "row(s): compound '", rl$from, "' -> '",
      rl$to, "' -- reason:", rl$reason %||% "(none given)", "\n"
    )
    usable$compound[match_idx] <- rl$to
  }
}

# Treatment relabels -- for a naming-QA flag resolved as "these rows use a
# different label for what is the same treatment" (e.g. a mislabeled dose
# string). Applied globally by treatment string, matching the same
# match-or-stop-loudly guarantee as compound_relabels above. Unlike
# compound_relabels (identity of the drug), this changes which arm_ind a row
# maps to -- use it deliberately.
if (!is.null(manifest$treatment_relabels)) {
  for (rl in manifest$treatment_relabels) {
    match_idx <- which(usable$treatment == rl$from)
    if (length(match_idx) == 0) {
      stop(
        "treatment_relabels entry matched no rows: from='", rl$from, "' -- check ",
        "the manifest against the current data (it may have changed since this ",
        "relabel was written)."
      )
    }
    cat(
      "Relabeling", length(match_idx), "row(s): treatment '", rl$from, "' -> '",
      rl$to, "' -- reason:", rl$reason %||% "(none given)", "\n"
    )
    usable$treatment[match_idx] <- rl$to
  }
}

# Placebo clamp -- forces any placebo row reporting a positive (weight-GAIN)
# pchg_wl_ee to 0. Found via bnma-nonadj-11AUG2026.R, which applies this
# unconditionally with no manifest equivalent ("Yongming advised setting the
# placebo effect to zero"). Opt-in and reasoned here, same pattern as every
# other manifest field -- absent means today's behavior (no clamping),
# unchanged. Requires a reason (hard stop, not just logged) because unlike a
# single row_exclusions entry, this can silently rewrite an arbitrary number
# of rows' values across the whole run.
if (isTRUE(manifest$placebo_clamp)) {
  if (is.null(manifest$placebo_clamp_reason) || !nzchar(trimws(manifest$placebo_clamp_reason))) {
    stop(
      "placebo_clamp is true but placebo_clamp_reason is missing/blank -- ",
      "this rewrites placebo values across the whole run and needs an ",
      "explicit, documented reason before it can be applied."
    )
  }
  clamp_idx <- which(usable$compound == "placebo" & suppressWarnings(as.numeric(usable$pchg_wl_ee)) > 0)
  if (length(clamp_idx) > 0) {
    cat(
      "Placebo clamp: ", length(clamp_idx), " placebo row(s) with positive ",
      "(weight-gain) pchg_wl_ee forced to 0 -- reason:", manifest$placebo_clamp_reason, "\n"
    )
    usable$pchg_wl_ee[clamp_idx] <- 0
  } else {
    cat("Placebo clamp enabled, but no placebo rows had a positive pchg_wl_ee -- no-op this run.\n")
  }
}

# Route-of-administration and observed/projection pre-filters (Step 2.5 of
# the skill) -- global scoping choices made once per run, applied before any
# study-selection review. Both default to "both" (no filtering) when absent,
# so every manifest written before these fields existed keeps working
# unchanged.
route_filter <- manifest$route_filter %||% "both"
if (!route_filter %in% c("oral", "injectable", "both")) {
  stop("route_filter must be 'oral', 'injectable', or 'both', got: ", route_filter)
}
if (route_filter != "both") {
  before_n <- nrow(usable)
  # Placebo rows are never dropped by route -- a placebo arm's own `aom` tag
  # reflects its paired active comparator's route, not a property of placebo
  # itself. A row with missing `aom` is dropped under a specific route filter
  # (can't confirm it matches what was asked for) -- same "can't rule out
  # pooling if route isn't recorded" logic as check_naming_pooling.R's
  # missing_route flag.
  usable <- usable %>% filter(compound == "placebo" | aom == route_filter)
  cat("Route filter '", route_filter, "': ", before_n - nrow(usable), " row(s) dropped.\n", sep = "")
}

evidence_filter <- manifest$evidence_filter %||% "both"
if (!evidence_filter %in% c("observed", "prediction", "both")) {
  stop("evidence_filter must be 'observed', 'prediction', or 'both', got: ", evidence_filter)
}
if (evidence_filter != "both") {
  before_n <- nrow(usable)
  # supplementary rows are exempt, same pattern as placebo's route exemption
  # above -- "supplementary" isn't a meaningful point on the observed/
  # prediction axis, so forcing an evidence_filter choice on it would just
  # drop deliberately hand-added data for the wrong reason.
  usable <- usable %>% filter(source_sheet == "supplementary" | source_sheet == evidence_filter)
  cat("Evidence filter '", evidence_filter, "': ", before_n - nrow(usable), " row(s) dropped.\n", sep = "")
}

# Compound scope filter -- for a "compound-first" run (user supplies a list
# of wanted compounds/doses up front, per SKILL.md step 0.5, rather than
# reviewing the full unfiltered study list). Row-level, not study-level: a
# study that mixes a wanted compound with an unwanted one (e.g. "believe"
# has semaglutide alongside bimagrumab and a bimagrumab+semaglutide combo
# arm) keeps its wanted-compound rows and drops the rest, rather than either
# keeping the whole study (silently pulling in compounds nobody asked for)
# or dropping the whole study (losing the wanted compound's evidence too).
# Dropping arms from a multi-arm trial doesn't corrupt the remaining arms'
# own estimates as long as a shared comparator (placebo, almost always)
# still connects them -- this is standard NMA subnetwork selection, not a
# statistical shortcut. Placebo rows are always exempt, same pattern as the
# route filter above -- placebo is the network's shared reference arm
# regardless of which compounds are in scope.
if (!is.null(manifest$compound_filter)) {
  compound_filter <- unlist(manifest$compound_filter)
  before_n <- nrow(usable)
  usable <- usable %>% filter(compound == "placebo" | compound %in% compound_filter)
  cat(
    "Compound filter (", length(compound_filter), " compounds): ",
    before_n - nrow(usable), " row(s) dropped.\n", sep = ""
  )
}

# Region scope filter -- for a workbook that carries a region-scoped extra
# sheet (e.g. "China Observed") alongside the standard global Observed/
# Prediction sheets (see load_merge_data.R). Defaults to "global" ONLY --
# unlike route/evidence/compound_filter, which default to "both" -- because
# region-scoped sheets are read into every merge unconditionally regardless
# of whether a given run asked for them; defaulting to "both" here would
# silently pull a newly-added regional dataset into every existing run the
# moment someone adds that sheet to a workbook. An explicit region_filter is
# required to include anything beyond "global". No placebo exemption here
# (unlike route_filter): a regional dataset's own placebo rows are part of
# that region's scope, not a universal reference shared across regions.
region_filter <- unlist(manifest$region_filter %||% "global")
if (!"region" %in% names(usable)) usable$region <- "global"
before_n <- nrow(usable)
usable <- usable %>% filter(region %in% region_filter)
if (before_n - nrow(usable) > 0) {
  cat(
    "Region filter (", paste(region_filter, collapse = ", "), "): ",
    before_n - nrow(usable), " row(s) dropped.\n", sep = ""
  )
}

studies_in_data <- unique(usable$study_name)
studies_in_manifest <- vapply(manifest$studies, function(s) s$study_name, character(1))

missing_from_manifest <- setdiff(studies_in_data, studies_in_manifest)
if (length(missing_from_manifest) > 0) {
  stop(
    "Manifest is missing an explicit include/exclude decision for ",
    length(missing_from_manifest), " study/ies found in the data:\n  ",
    paste(missing_from_manifest, collapse = ", "),
    "\nAdd an entry for each under `studies:` before re-running -- no ",
    "study is included or excluded by default."
  )
}

unknown_in_manifest <- setdiff(studies_in_manifest, studies_in_data)
if (length(unknown_in_manifest) > 0) {
  cat(
    "Note: manifest lists studies not present in this data run (ignored):\n  ",
    paste(unknown_in_manifest, collapse = ", "), "\n"
  )
}

included_studies <- vapply(
  Filter(function(s) isTRUE(s$include), manifest$studies),
  function(s) s$study_name,
  character(1)
)

data_sel <- usable %>% filter(study_name %in% included_studies)

if (nrow(data_sel) == 0) {
  stop("No rows remain after applying the manifest's study selection.")
}

data_sel <- data_sel %>%
  rename(study = study_name, treat = treatment)

# Disambiguate study identity when a single study_name internally collides on
# (study, treat) -- e.g. a study whose own observed rows and own prediction
# rows are both kept (per the manifest), and both happen to include the same
# treatment string (typically "placebo") at a different duration. BATMAN
# requires exactly one row per treatment per "study" -- this is the same
# distinction that already exists naturally between e.g. retatrutide_ph2_gzbf
# and retatrutide_gzbf (which just happen to have different study_names);
# here it's the same study_name internally, so split by source_sheet instead.
# Only colliding studies get the [sheet] suffix, so the common case (no
# internal observed+prediction mix) is untouched.
colliding_studies <- data_sel %>%
  count(study, treat) %>%
  filter(n > 1) %>%
  pull(study) %>%
  unique()

if (length(colliding_studies) > 0) {
  cat(
    "Disambiguating studies with an internal same-treatment collision by ",
    "data source (observed vs. prediction): ", paste(colliding_studies, collapse = ", "), "\n"
  )
  data_sel <- data_sel %>%
    mutate(study = if_else(study %in% colliding_studies, paste0(study, " [", source_sheet, "]"), study))
}

study_list <- unique(data_sel$study)
treatment_list <- unique(data_sel$treat)
if ("placebo" %in% treatment_list) {
  treatment_list <- c("placebo", setdiff(treatment_list, "placebo"))
} else {
  warning("No 'placebo' arm found in the selected data -- adding as phantom reference.")
  treatment_list <- c("placebo", treatment_list)
}

data_recon <- data_sel %>%
  left_join(data.frame(study = study_list, study_ind = seq_along(study_list)), by = "study") %>%
  left_join(data.frame(treat = treatment_list, arm_ind = seq_along(treatment_list)), by = "treat")

# ---------------------------------------------------------------------------
# BATMAN augmentation: phantom placebo arm for studies with none
# ---------------------------------------------------------------------------
# model_type controls whether this fires at all. Confirmed 2026-08-17
# (BNMA_forest_plot-main.zip, the real production BNMA Shiny app): the real
# tool has NO automatic phantom-placebo bridging anywhere -- its own
# intro page states "If a placebo already exists for the treatment arm from
# previous studies in the Core dataset, no new placebo data is needed.
# Otherwise, placebo data is required," i.e. a curator supplies the value
# upstream; a study with none simply doesn't connect to the network (its
# phi[i] baseline is estimated, but it contributes no delta/relative-effect
# information). That's real, documented behavior (unlike the earlier
# connectivity-aware attempt, which had no documentation anywhere and was
# reverted for exactly that reason) -- so for model_type rand_effect/
# fixed_effect (the real production models), we match it: no injection,
# just a clear log line instead of a silent no-op.
#
# model_type absent or "simultaneous" (the legacy hierarchical model) keeps
# today's unconditional bridging exactly as-is -- every existing manifest
# was written assuming this, so the field defaults to the OLD behavior when
# absent, not the new recommended default (same asymmetric-default pattern
# as region_filter's own note above).
model_type <- manifest$model_type %||% "simultaneous"
if (!model_type %in% c("simultaneous", "rand_effect", "fixed_effect")) {
  stop("model_type must be 'simultaneous', 'rand_effect', or 'fixed_effect', got: ", model_type)
}

studies_with_placebo <- data_recon %>% filter(treat == "placebo") %>% pull(study_ind) %>% unique()
studies_without_placebo <- setdiff(unique(data_recon$study_ind), studies_with_placebo)

if (length(studies_without_placebo) > 0) {
  lookup <- data_recon %>% select(study, study_ind) %>% distinct()
  no_placebo_studies <- lookup %>% filter(study_ind %in% studies_without_placebo) %>% pull(study)

  if (model_type == "simultaneous") {
    cat("Studies without a placebo arm (phantom arm injected):\n  ", paste(no_placebo_studies, collapse = ", "), "\n")
    phantom_rows <- data_recon %>%
      filter(study_ind %in% studies_without_placebo) %>%
      select(study, study_ind) %>%
      distinct() %>%
      mutate(treat = "placebo", arm_ind = 1L, pchg_wl_ee = NA_real_, se_wl_ee = 1, compound = NA_character_)
    data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
  } else {
    cat(
      "Studies without a placebo arm (model_type='", model_type, "' -- NOT bridged, matches the real ",
      "production tool's own behavior; these studies contribute a baseline estimate only, no ",
      "relative-effect information):\n  ", paste(no_placebo_studies, collapse = ", "), "\n", sep = ""
    )
  }
}

# ---------------------------------------------------------------------------
# Build BATMAN/JAGS input matrices
# ---------------------------------------------------------------------------
na_df <- data_recon %>% group_by(study_ind) %>% summarise(na = n_distinct(arm_ind), .groups = "drop") %>% arrange(study_ind)
na_vec <- na_df$na
ns <- max(data_recon$study_ind)
M <- max(data_recon$arm_ind)
max_na <- max(na_vec)

trt <- matrix(NA_integer_, ns, max_na)
y   <- matrix(NA_real_, ns, max_na)
se  <- matrix(NA_real_, ns, max_na)

for (i in seq_len(ns)) {
  arms_i <- data_recon %>% filter(study_ind == i) %>% arrange(arm_ind)
  n_i <- nrow(arms_i)
  if (n_i > 0) {
    trt[i, 1:n_i] <- as.integer(arms_i$arm_ind)
    y[i, 1:n_i]   <- as.numeric(arms_i$pchg_wl_ee)
    se[i, 1:n_i]  <- as.numeric(arms_i$se_wl_ee)
  }
}

batman_data <- list(na = na_vec, M = M, ns = ns, trt = trt, y = y, se = se)
saveRDS(batman_data, args$batman_out)

# Surface whether this specific network can actually support a
# random-effects heterogeneity estimate, or whether every treatment node is
# single-study (fixed-effects territory -- see lib_common.R's
# compute_heterogeneity_estimability() for the full rationale and its
# pf_nma.R precedent). Informational only -- never overrides the manifest's
# own model_type, but must be surfaced to the statistician before fitting
# (Step 5 in SKILL.md) rather than left for them to discover after the fact.
print_heterogeneity_estimability(compute_heterogeneity_estimability(data_recon))

arm_info <- data_recon %>%
  mutate(node = paste0("d[", arm_ind, "]")) %>%
  select(node, arm_ind, treatment = treat, compound) %>%
  # A placebo row's compound is always "placebo" by construction, regardless
  # of what the raw data says -- found via testing against real PRD data,
  # where a placebo arm occasionally carried the study's active-drug compound
  # (a data-entry error; see check_naming_pooling.R's placebo_mistag flag,
  # which surfaces this for a curator to fix at the source). Forcing it here
  # means the forest plot's placebo arm is never mislabeled by that error.
  mutate(compound = if_else(treatment == "placebo", "placebo", compound)) %>%
  distinct() %>%
  # Phantom BATMAN placebo rows have compound = NA and can duplicate a real
  # row's arm_ind (same node/treatment, no compound) -- prefer the row that
  # actually carries a compound so downstream lookups never depend on which
  # of the two ties happened to sort first.
  arrange(arm_ind, is.na(compound)) %>%
  distinct(arm_ind, .keep_all = TRUE)

# Per-arm evidence type, for the forest plot's observed/projection/
# supplementary marker. Aggregated from source_sheet (the clean tag, not the
# free-text data_type column) across every surviving row that maps to this
# arm_ind -- an arm can legitimately be fed by more than one source (e.g. the
# shared placebo arm fed by both observed and prediction studies, or a
# supplementary row sharing an arm with a real one). Stored as the sorted,
# comma-joined set of distinct sources rather than a lossy "mixed" catch-all
# -- single-source arms keep their existing plain string ("observed",
# "prediction", "supplementary") unchanged; a genuinely mixed arm stores e.g.
# "observed,prediction" or "observed,supplementary" so make_forest_plot.R can
# render the exact combination instead of guessing which two sources mixed.
# BATMAN's own synthetic phantom-placebo rows have no source_sheet (they're
# not from any real source) and are excluded here so they can't make a real
# placebo arm look unevidenced.
arm_evidence <- data_recon %>%
  filter(!is.na(source_sheet)) %>%
  group_by(arm_ind) %>%
  summarise(evidence_type = paste(sort(unique(source_sheet)), collapse = ","), .groups = "drop")
arm_info <- arm_info %>% left_join(arm_evidence, by = "arm_ind")
saveRDS(arm_info, args$arm_info_out)

study_info <- data_recon %>% select(study_ind, study_name = study) %>% distinct() %>% arrange(study_ind)
saveRDS(study_info, args$study_info_out)

cat(
  "BATMAN data built:", ns, "studies,", M, "treatment arms.\n",
  "Written to:", args$batman_out, "/", args$arm_info_out, "/", args$study_info_out, "\n"
)
