#!/usr/bin/env Rscript
# Step 1 of the /bnma skill: load QA + PRD data and merge into one data.frame.
#
# Join logic (documented here per GUIDE_README.md Flow 2 step 4 — merge
# happens in code, not as a shared preprocessing file):
#   - PRD is the cumulative, lead-team-curated tier and is always the base.
#   - QA (optional) holds newer entries not yet promoted to PRD. Any QA row
#     matching an existing PRD row on (study_name, treatment) is treated as
#     an update to that row and wins (kept), using its own time_entry as the
#     tie-breaker when both exist. QA rows with no PRD match are additions.
#   - Both tiers' Observed and Prediction sheets are read (by name, with a
#     fallback to positional sheet 2/3 for older workbooks — see
#     lib_common.R's read_sheet_with_fallback) and tagged with source_tier /
#     source_sheet columns so downstream steps and the footnote can trace
#     every row back to where it came from.
#
# Usage:
#   Rscript load_merge_data.R [--prd <path.xlsx>] [--qa <path.xlsx>] --out <merged.rds>
#
# At least one of --prd/--qa must be given. Both are optional individually
# (not just --qa) so a QA-only run -- e.g. no cumulative PRD file has been
# copied in for this dataset -- tags its rows source_tier="qa" correctly,
# rather than being forced through --prd and mislabeled "prd".

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(normalizePath(script_path)), "lib_common.R"))

args <- parse_args(list(
  prd = list(default = NULL),
  qa  = list(default = NULL),
  out = list(required = TRUE)
))

if (is.null(args$prd) && is.null(args$qa)) {
  stop("At least one of --prd or --qa must be given.")
}

# A workbook's standard "Observed"/"Prediction" sheets are tagged
# region="global". Some workbooks also carry a region-scoped extra sheet
# (found in practice: a "China Observed" sheet alongside the standard ones)
# -- any sheet matching "<Region> Observed" or "<Region> Prediction"
# (case-insensitive) is read the same way and tagged with that region,
# lowercased, instead of "global". This is read into every merge
# unconditionally (same as the standard sheets); `region_filter` in
# build_batman_data.R is what actually scopes a run to global-only or a
# specific region -- load time just needs to capture that the rows exist
# and where they came from.
region_sheet_pattern <- "^(.*)\\s+(Observed|Prediction)$"

load_tier <- function(path, tier_label) {
  if (is.null(path)) return(NULL)
  if (!file.exists(path)) stop("File not found for --", tier_label, ": ", path)

  sheets <- excel_sheets(path)
  parts <- list()

  observed <- read_sheet_with_fallback(path, "Observed", fallback_index = 2)
  if (!is.null(observed)) {
    parts[["Observed"]] <- stringify_all(observed) %>%
      mutate(source_tier = tier_label, source_sheet = "observed", region = "global")
  }
  prediction <- read_sheet_with_fallback(path, "Prediction", fallback_index = 3)
  if (!is.null(prediction)) {
    parts[["Prediction"]] <- stringify_all(prediction) %>%
      mutate(source_tier = tier_label, source_sheet = "prediction", region = "global")
  }

  # Case-insensitive exclusion (matches read_sheet_with_fallback's own
  # case-insensitive name match above) -- otherwise a lowercase "observed"/
  # "prediction" sheet would remain in extra_sheets and get needlessly
  # checked against the region-sheet regex below.
  extra_sheets <- sheets[!tolower(trimws(sheets)) %in% c("observed", "prediction")]
  for (sheet_name in extra_sheets) {
    m <- regexec(region_sheet_pattern, sheet_name, ignore.case = TRUE)
    matched <- regmatches(sheet_name, m)[[1]]
    if (length(matched) == 3 && nzchar(matched[2])) {
      region_name <- tolower(squish_ws(matched[2]))
      sheet_kind <- tolower(matched[3])
      cat("Found region-scoped sheet '", sheet_name, "' -- tagging region='", region_name, "'.\n", sep = "")
      parts[[sheet_name]] <- stringify_all(readxl::read_excel(path, sheet = sheet_name)) %>%
        mutate(source_tier = tier_label, source_sheet = sheet_kind, region = region_name)
    }
  }

  if (length(parts) == 0) {
    stop("Neither an Observed nor a Prediction sheet was found in ", path)
  }
  bind_rows(parts)
}

prd_data <- load_tier(args$prd, "prd")
qa_data  <- load_tier(args$qa, "qa")

if (is.null(prd_data)) {
  merged <- qa_data
} else if (is.null(qa_data)) {
  merged <- prd_data
} else {
  # QA rows matching an existing PRD (study_name, treatment) pair are updates
  # and win; QA rows with no match are new additions. Both cases: just prefer
  # QA over PRD on key collision, keep everything else.
  key <- function(df) paste(df$study_name, df$treatment, sep = "")
  prd_keys <- key(prd_data)
  qa_keys  <- key(qa_data)
  merged <- bind_rows(
    prd_data %>% filter(!prd_keys %in% qa_keys),
    qa_data
  )
}

# Some QA workbooks carry leftover derived columns from a prior analysis run
# (study_ind, arm_ind, treat) that were never supposed to persist in the
# source file (GUIDE_README.md: "study_ind, arm_ind (re-derived at analysis
# time, not stored)") -- found via testing against a real T2D QA file whose
# Prediction sheet already had a `treat` column, colliding with this script's
# own rename() step downstream. Drop them defensively; this pipeline always
# recomputes its own indices, so any pre-existing ones can't be trusted
# anyway (they'd reflect some other, unrelated arm-numbering scheme).
merged <- merged %>% select(-any_of(c("study_ind", "arm_ind", "treat")))

merged <- merged %>%
  mutate(
    compound  = tolower(squish_ws(compound)),
    treatment = tolower(squish_ws(treatment)),
    study_name = tolower(squish_ws(study_name))
  ) %>%
  recast_numeric_cols()

saveRDS(merged, args$out)
cat(
  "Merged", nrow(merged), "rows (",
  sum(merged$source_tier == "prd"), "from PRD,",
  sum(merged$source_tier == "qa"), "from QA ).\n",
  "Studies:", n_distinct(merged$study_name), "  Compounds:", n_distinct(merged$compound), "\n",
  "Written to:", args$out, "\n"
)
