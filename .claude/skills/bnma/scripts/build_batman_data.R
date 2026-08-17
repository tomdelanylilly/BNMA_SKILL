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
# different label for what is, for network-connection purposes, the same
# treatment" (e.g. a dose-flexible "or mtd" label vs. the fixed-dose string
# used everywhere else for the same nominal dose). Applied globally by
# treatment string, matching the same match-or-stop-loudly guarantee as
# compound_relabels above. Unlike compound_relabels (identity of the drug),
# this changes which arm_ind a row maps to -- use it deliberately, since it
# can connect a study to the rest of the network that would otherwise need a
# phantom-placebo bridge (or need one at all).
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
  usable <- usable %>% filter(source_sheet == evidence_filter)
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
# BATMAN augmentation: phantom placebo arm for genuinely disconnected studies
# ---------------------------------------------------------------------------
# A study with no literal placebo arm does NOT automatically need bridging --
# if its own treatment(s) already appear in some other included study that
# does connect to placebo, it's already part of the network via that shared
# arm identity (standard indirect comparison), no phantom row required. Only
# a study whose entire arm set is otherwise isolated from the placebo
# component is a genuine island. Checked here via union-find over
# co-occurring arms within each study (an edge = two treatments compared in
# the same trial) -- this replaces a naive "no literal placebo -> bridge"
# check, which incorrectly flagged every head-to-head trial even when its
# own arms already connect elsewhere (e.g. a tirzepatide-vs-X trial when
# tirzepatide already appears in a placebo-controlled study).
treat_nodes <- unique(data_recon$treat)
uf_parent <- setNames(treat_nodes, treat_nodes)
uf_find <- function(x) { while (uf_parent[[x]] != x) x <- uf_parent[[x]]; x }
uf_union <- function(a, b) {
  ra <- uf_find(a); rb <- uf_find(b)
  if (ra != rb) uf_parent[[ra]] <<- rb
}
for (s in unique(data_recon$study)) {
  ts <- unique(data_recon$treat[data_recon$study == s])
  if (length(ts) > 1) for (i in 2:length(ts)) uf_union(ts[1], ts[i])
}
placebo_root <- if ("placebo" %in% treat_nodes) uf_find("placebo") else NA

study_roots <- data_recon %>%
  distinct(study, treat) %>%
  mutate(root = vapply(treat, uf_find, character(1))) %>%
  group_by(study) %>%
  # If there's no real placebo row anywhere in scope (placebo_root is NA --
  # a fully head-to-head-only selection), every study is disconnected from
  # it by definition -- `any(root == NA)` would otherwise evaluate to NA and
  # get silently dropped by the filter below instead of correctly flagged.
  summarise(connected_to_placebo = if (is.na(placebo_root)) FALSE else any(root == placebo_root), .groups = "drop")

disconnected_studies <- study_roots %>% filter(!connected_to_placebo) %>% pull(study)

# legacy_naive_phantom_bridging: true opts into the OLD, pre-connectivity-fix
# behavior (bridge any study lacking a literal placebo row, regardless of
# whether it's already connected via shared arms) -- exists ONLY to
# reproduce/compare against a specific historical run that used that
# behavior (e.g. validating against an existing team script). Not intended
# for normal use: it will bridge studies that don't actually need it,
# injecting avoidable extra uncertainty -- the default (connectivity-aware)
# behavior above is the statistically correct one for everyday runs.
if (isTRUE(manifest$legacy_naive_phantom_bridging)) {
  literal_placebo_studies <- data_recon %>% filter(treat == "placebo") %>% pull(study) %>% unique()
  disconnected_studies <- setdiff(unique(data_recon$study), literal_placebo_studies)
}

# Injecting a phantom placebo (SE=1, y=NA) assumes this study's true placebo
# response is exchangeable with the network's real placebo-controlled
# studies -- reasonable for some genuinely isolated trials, not automatically
# true for all of them (e.g. a very different population/design). This must
# be an explicit, reviewed decision per study, not a silent default -- a
# disconnected study that is NOT explicitly approved below causes a hard
# stop; the analyst must either approve the bridge with a reason, or exclude
# the study from `studies:` instead.
if (length(disconnected_studies) > 0) {
  approved_names <- vapply(manifest$phantom_placebo_approved %||% list(), function(a) a$study_name, character(1))
  unapproved <- setdiff(disconnected_studies, approved_names)
  if (length(unapproved) > 0) {
    stop(
      "The following included study/ies are disconnected from the placebo ",
      "component (their arms don't appear in any other included study) and ",
      "would need a phantom-placebo bridge, but are not approved for it in ",
      "the manifest:\n  ", paste(unapproved, collapse = ", "),
      "\nAdd a `phantom_placebo_approved` entry (with study_name + reason) for ",
      "each one this study's design is genuinely comparable to the network's ",
      "placebo-controlled studies, or exclude it from `studies:` instead -- ",
      "phantom bridging is never applied by default."
    )
  }

  cat(
    "Disconnected studies bridged with an explicitly-approved phantom placebo arm:\n  ",
    paste(disconnected_studies, collapse = ", "), "\n"
  )
  phantom_rows <- data_recon %>%
    filter(study %in% disconnected_studies) %>%
    select(study, study_ind) %>%
    distinct() %>%
    mutate(treat = "placebo", arm_ind = 1L, pchg_wl_ee = NA_real_, se_wl_ee = 1, compound = NA_character_)
  data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
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

# Per-arm evidence type, for the forest plot's observed/projection marker.
# Aggregated from source_sheet (the clean observed/prediction tag, not the
# free-text data_type column) across every surviving row that maps to this
# arm_ind -- an arm can legitimately be "mixed" (e.g. the shared placebo arm
# is fed by both observed and prediction studies whenever both are in scope
# for a run). BATMAN's own synthetic phantom-placebo rows have no
# source_sheet (they're not from either source) and are excluded here so
# they can't make a real placebo arm look unevidenced.
arm_evidence <- data_recon %>%
  filter(!is.na(source_sheet)) %>%
  group_by(arm_ind) %>%
  summarise(
    evidence_type = if (n_distinct(source_sheet) > 1) {
      "mixed"
    } else {
      unique(source_sheet)
    },
    .groups = "drop"
  )
arm_info <- arm_info %>% left_join(arm_evidence, by = "arm_ind")
saveRDS(arm_info, args$arm_info_out)

study_info <- data_recon %>% select(study_ind, study_name = study) %>% distinct() %>% arrange(study_ind)
saveRDS(study_info, args$study_info_out)

cat(
  "BATMAN data built:", ns, "studies,", M, "treatment arms.\n",
  "Written to:", args$batman_out, "/", args$arm_info_out, "/", args$study_info_out, "\n"
)
