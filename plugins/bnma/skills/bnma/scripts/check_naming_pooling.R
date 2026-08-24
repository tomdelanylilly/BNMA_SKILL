#!/usr/bin/env Rscript
# Step 2 of the /bnma skill: the naming/pooling QA gate. Runs before any
# study-selection is offered, so that step is grounded in already-vetted
# compound names and treatment/route labels. Never edits the input data --
# only produces a report for a human (or the calling skill conversation) to
# act on.
#
# Two independent checks, documented in DESIGN.md:
#
# 1. Near-duplicate compound spelling. No signal here *proves* two spellings
#    are the same real compound -- this only ranks candidates for review:
#      - "high" tier: one name is a substring of the other (e.g. "canaflig"
#        in "canafligizon") -- matches the actual failure mode of a dev code
#        name drifting into a full INN name, or a truncated entry.
#      - "low" tier: normalized edit distance below a conservative threshold.
#        Shown separately because GLP-1/GIP-class drugs share suffixes
#        systematically (-glutide, -tide, -trutide) -- edit distance alone
#        would flag real, distinct compounds constantly.
#      - Suppressed entirely if the two names ever appear as separate arms
#        within the same study_name -- that's a head-to-head comparison,
#        strong evidence they're genuinely different compounds.
#      - Skipped entirely if the pair is already in compound_registry.yaml's
#        resolved_pairs.
#
# 2. Route-pooling risk. Mechanical, not fuzzy: for compounds with more than
#    one distinct `aom` (route) value, flag any exact `treatment` string
#    shared across routes (the literal bug -- arm_ind comes from
#    unique(treatment), so such rows collapse into one arm) and any compound
#    with missing/mixed `aom` recording.
#
# Usage:
#   Rscript check_naming_pooling.R --data <merged.rds> [--registry <registry.yaml>] --out <report.json>

suppressPackageStartupMessages({
  library(dplyr)
  library(yaml)
  library(jsonlite)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  data     = list(required = TRUE),
  registry = list(default = file.path(dirname(script_dir), "compound_registry.yaml")),
  out      = list(required = TRUE),
  edit_distance_threshold = list(default = "0.25")
))

EDIT_THRESHOLD <- as.numeric(args$edit_distance_threshold)

merged <- readRDS(args$data)
registry <- if (file.exists(args$registry)) yaml::read_yaml(args$registry) else list()
resolved_pairs <- registry$resolved_pairs %||% list()

pair_key <- function(a, b) paste(sort(c(a, b)), collapse = "|||")

is_resolved <- function(a, b) {
  if (length(resolved_pairs) == 0) return(FALSE)
  target <- pair_key(a, b)
  any(vapply(resolved_pairs, function(p) pair_key(p$a, p$b) == target, logical(1)))
}

# ---------------------------------------------------------------------------
# Check 1: near-duplicate compound spelling
# ---------------------------------------------------------------------------
compounds <- merged$compound %>%
  unique() %>%
  na.omit() %>%
  setdiff("placebo") %>%
  sort()

# study_name sets per compound, to test same-study co-occurrence
studies_by_compound <- split(merged$study_name, merged$compound)

compound_flags <- list()
if (length(compounds) >= 2) {
  pairs <- combn(compounds, 2, simplify = FALSE)
  for (p in pairs) {
    a <- p[1]; b <- p[2]
    if (a == b) next
    if (is_resolved(a, b)) next

    is_substring <- (nchar(a) >= 4 && nchar(b) >= 4) &&
      (grepl(a, b, fixed = TRUE) || grepl(b, a, fixed = TRUE))
    edit_ratio <- adist(a, b)[1, 1] / max(nchar(a), nchar(b))

    tier <- if (is_substring) {
      "high"
    } else if (edit_ratio <= EDIT_THRESHOLD) {
      "low"
    } else {
      NA_character_
    }
    if (is.na(tier)) next

    shared_studies <- intersect(studies_by_compound[[a]], studies_by_compound[[b]])
    suppressed <- length(shared_studies) > 0

    compound_flags[[length(compound_flags) + 1]] <- list(
      compound_a = a,
      compound_b = b,
      tier = tier,
      edit_distance_ratio = round(edit_ratio, 3),
      is_substring = is_substring,
      suppressed = suppressed,
      suppressed_reason = if (suppressed) {
        paste0(
          "co-occur as separate arms in ", length(shared_studies),
          " shared study/ies (e.g. '", shared_studies[1], "') -- ",
          "likely genuinely distinct compounds, not a naming duplicate"
        )
      } else {
        NA_character_
      }
    )
  }
}

# ---------------------------------------------------------------------------
# Check 2: route (aom) pooling risk
# ---------------------------------------------------------------------------
pooling_flags <- list()
has_aom <- "aom" %in% names(merged)

if (has_aom) {
  by_compound <- merged %>%
    filter(compound != "placebo") %>%
    group_by(compound) %>%
    summarise(
      aom_values = list(unique(aom)),
      .groups = "drop"
    )

  for (i in seq_len(nrow(by_compound))) {
    cmpd <- by_compound$compound[i]
    aoms <- by_compound$aom_values[[i]]
    distinct_non_na <- unique(na.omit(aoms))
    if (length(distinct_non_na) < 2 && !any(is.na(aoms))) next # single route, fully recorded: nothing to check

    rows <- merged %>% filter(compound == cmpd)

    if (length(distinct_non_na) >= 2) {
      collisions <- rows %>%
        filter(!is.na(aom)) %>%
        group_by(treatment) %>%
        summarise(n_routes = n_distinct(aom), routes = list(unique(aom)), .groups = "drop") %>%
        filter(n_routes > 1)

      for (j in seq_len(nrow(collisions))) {
        pooling_flags[[length(pooling_flags) + 1]] <- list(
          kind = "route_collision",
          compound = cmpd,
          treatment = collisions$treatment[j],
          routes = collisions$routes[[j]],
          message = paste0(
            "'", collisions$treatment[j], "' (", cmpd, ") appears under ",
            "routes [", paste(collisions$routes[[j]], collapse = ", "), "] -- ",
            "these rows will collapse into ONE treatment arm (arm_ind is ",
            "derived from the treatment string alone), silently pooling ",
            "different routes of administration."
          )
        )
      }
    }

    if (any(is.na(aoms))) {
      pooling_flags[[length(pooling_flags) + 1]] <- list(
        kind = "missing_route",
        compound = cmpd,
        treatment = NA_character_,
        routes = list(),
        message = paste0(
          "'", cmpd, "' has rows with no `aom` recorded -- route can't be ",
          "confirmed, so an accidental oral/injectable pooling can't be ",
          "ruled out for this compound."
        )
      )
    }
  }
}

# ---------------------------------------------------------------------------
# Check 3: placebo rows mistagged with an active-drug compound
# ---------------------------------------------------------------------------
# Neither a naming-similarity nor a route-pooling issue -- a distinct data-
# entry integrity check. Found via testing against real PRD data: a placebo
# arm (treatment == "placebo") occasionally carries the study's active-drug
# compound in the `compound` column instead of "placebo"/NA. build_batman_data.R
# hardens against this (arm_ind 1's compound is always forced to "placebo"
# regardless of what's in the raw data), but it's still flagged here so a
# curator can fix it at the source.
integrity_flags <- list()
mistagged <- merged %>% filter(treatment == "placebo", !is.na(compound), compound != "placebo")
if (nrow(mistagged) > 0) {
  for (i in seq_len(nrow(mistagged))) {
    integrity_flags[[length(integrity_flags) + 1]] <- list(
      kind = "placebo_mistag",
      study_name = mistagged$study_name[i],
      compound = mistagged$compound[i],
      message = paste0(
        "Study '", mistagged$study_name[i], "' has a treatment == 'placebo' row ",
        "tagged with compound = '", mistagged$compound[i], "' instead of 'placebo' ",
        "-- likely a data-entry error. The BNMA model itself keys off the treatment ",
        "string (not compound), so this shouldn't corrupt the fit, but it can mislabel ",
        "the placebo arm's color/legend in the forest plot unless corrected at the source."
      )
    )
  }
}

# `compound == "pbo"` is a real, documented convention this skill's own
# checks previously missed entirely -- confirmed 2026-08-20 against the real
# production package's own placebo_name(): `grep("^placebo$|^pbo$", ...,
# ignore.case = TRUE)`. Every check/filter in this pipeline keys off
# `compound == "placebo"` specifically (route exemption, placebo_clamp,
# arm_ind ordering's fallback), and "placebo" is excluded from Check 1's own
# compound-similarity comparison set below -- so a compound literally spelled
# "pbo" would previously have gone completely unflagged (not compared
# against "placebo" at all, since that string isn't in the comparison list)
# and been treated as some unrelated 28th drug, not the reference arm.
pbo_rows <- merged %>% filter(compound == "pbo")
if (nrow(pbo_rows) > 0) {
  affected_studies <- unique(pbo_rows$study_name)
  integrity_flags[[length(integrity_flags) + 1]] <- list(
    kind = "pbo_compound_alias",
    study_name = NA_character_,
    compound = "pbo",
    message = paste0(
      "compound == 'pbo' found in ", length(affected_studies), " study/ies (",
      paste(head(affected_studies, 5), collapse = ", "),
      if (length(affected_studies) > 5) ", ..." else "",
      ") -- a real placebo alias (matches the production tool's own placebo_name() ",
      "regex) that every check/filter in this pipeline will otherwise treat as an ",
      "unrelated compound. Propose a compound_relabels entry: 'pbo' -> 'placebo'."
    )
  )
}

# ---------------------------------------------------------------------------
# Check 4a: placebo-arm naming variants
# ---------------------------------------------------------------------------
# Found via testing against real T2D HbA1c PRD data, 2026-08-20: several
# studies record their placebo arm's `treatment` as "oral placebo qd",
# "injectable placebo qw", "injectable placebo qd", or "placebo qw" --
# `compound` is correctly "placebo" for every one of them, only the
# treatment STRING varies. This is more than a cosmetic naming issue --
# build_batman_data.R's arm_ind assignment is keyed off the literal
# treatment string (matches the skill's own "arm_ind is derived from the
# treatment string alone" invariant used everywhere else, e.g. Check 2's
# route-collision logic), so each differently-worded placebo row becomes
# its OWN separate, single-study, disconnected network node instead of
# sharing the one placebo reference arm every other study anchors to --
# silently fragmenting the network's connectivity, not just a label
# inconsistency. The dominant convention in this same dataset already uses
# a bare "placebo" string across BOTH oral and injectable rows (route
# filtering already exempts placebo from route matching for exactly this
# reason), so collapsing these variants onto it is consistent with the
# data's own existing convention, not a new one.
placebo_naming_flags <- list()
placebo_variants <- merged %>%
  filter(compound == "placebo", treatment != "placebo") %>%
  distinct(treatment) %>%
  pull(treatment)
if (length(placebo_variants) > 0) {
  for (pv in placebo_variants) {
    affected_studies <- merged %>% filter(compound == "placebo", treatment == pv) %>% pull(study_name) %>% unique()
    placebo_naming_flags[[length(placebo_naming_flags) + 1]] <- list(
      kind = "placebo_naming_variant",
      treatment = pv,
      affected_studies = affected_studies,
      message = paste0(
        "'", pv, "' is a placebo row (compound == 'placebo') under a non-canonical ",
        "treatment string -- without a treatment_relabels entry to 'placebo', ", "affects ",
        length(affected_studies), " study/ies (", paste(head(affected_studies, 5), collapse = ", "),
        if (length(affected_studies) > 5) ", ..." else "",
        ") and will each become their own disconnected single-study node instead of ",
        "sharing the network's one placebo reference arm."
      )
    )
  }
}

# ---------------------------------------------------------------------------
# Check 4b: studies with no placebo arm at all
# ---------------------------------------------------------------------------
# Only matters for model_type rand_effect/fixed_effect -- build_batman_data.R
# leaves such a study disconnected from the network by default (matches the
# real production tool's own documented behavior), unless the manifest opts
# it into phantom-bridging via `phantom_placebo_studies` (see SKILL.md Step
# 3/4). Computed here (pre-study-selection, pre-model_type-finalization) so
# every such study can be surfaced in Step 3's one consolidated ask rather
# than discovered only once build_batman_data.R runs. A study excluded from
# this run entirely (Step 3 studies: list) makes this moot for it, same as
# any other flag here -- the skill conversation reconciles that at Step 3,
# not this script.
#
# Keyed off `compound == "placebo"`, NOT the literal treatment string --
# using the treatment string here would double-count every Check 4a variant
# as "no placebo" too (a study can easily have a real placebo arm recorded
# under one of those variant strings and nothing else), which is exactly the
# false-positive this fix replaces: real case, 2026-08-20, several studies
# whose placebo arm was "oral placebo qd" showed up here as falsely having
# no placebo arm at all.
no_placebo_flags <- list()
studies_with_placebo_all <- merged %>% filter(compound == "placebo") %>% pull(study_name) %>% unique()
studies_without_placebo_all <- setdiff(unique(merged$study_name), studies_with_placebo_all)
if (length(studies_without_placebo_all) > 0) {
  for (sn in studies_without_placebo_all) {
    treats <- merged %>% filter(study_name == sn) %>% pull(treatment) %>% unique()
    no_placebo_flags[[length(no_placebo_flags) + 1]] <- list(
      study_name = sn,
      treatments = treats,
      message = paste0(
        "'", sn, "' has no 'placebo' row -- under model_type rand_effect/fixed_effect this study ",
        "won't connect to the network by default (baseline estimate only, no relative-effect ",
        "information) unless opted into phantom-bridging via phantom_placebo_studies."
      )
    )
  }
}

report <- list(
  compound_flags = compound_flags,
  pooling_flags = pooling_flags,
  integrity_flags = integrity_flags,
  placebo_naming_flags = placebo_naming_flags,
  no_placebo_flags = no_placebo_flags,
  summary = list(
    n_compounds_checked = length(compounds),
    n_compound_flags = length(compound_flags),
    n_compound_flags_active = sum(vapply(compound_flags, function(f) !f$suppressed, logical(1))),
    n_pooling_flags = length(pooling_flags),
    n_integrity_flags = length(integrity_flags),
    n_placebo_naming_flags = length(placebo_naming_flags),
    n_no_placebo_flags = length(no_placebo_flags)
  )
)

jsonlite::write_json(report, args$out, auto_unbox = TRUE, pretty = TRUE, na = "null")

cat("Naming/pooling QA gate report written to:", args$out, "\n")
cat(
  "  Compounds checked:", report$summary$n_compounds_checked, "\n",
  "  Compound flags:", report$summary$n_compound_flags,
  "(", report$summary$n_compound_flags_active, "active,",
  report$summary$n_compound_flags - report$summary$n_compound_flags_active, "suppressed )\n",
  "  Pooling flags:", report$summary$n_pooling_flags, "\n",
  "  Integrity flags (placebo mistagging):", report$summary$n_integrity_flags, "\n",
  "  Placebo naming variants (need a treatment_relabels entry):", report$summary$n_placebo_naming_flags, "\n",
  "  Studies with no placebo arm:", report$summary$n_no_placebo_flags,
  "(relevant only if model_type ends up rand_effect/fixed_effect -- see SKILL.md Step 3)\n"
)
