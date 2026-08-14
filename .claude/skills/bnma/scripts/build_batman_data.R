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
studies_with_placebo <- data_recon %>% filter(treat == "placebo") %>% pull(study_ind) %>% unique()
studies_without_placebo <- setdiff(unique(data_recon$study_ind), studies_with_placebo)

if (length(studies_without_placebo) > 0) {
  lookup <- data_recon %>% select(study, study_ind) %>% distinct()
  cat(
    "Studies without a placebo arm (phantom arm injected):\n  ",
    paste(lookup %>% filter(study_ind %in% studies_without_placebo) %>% pull(study), collapse = ", "),
    "\n"
  )
  phantom_rows <- data_recon %>%
    filter(study_ind %in% studies_without_placebo) %>%
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
  distinct() %>%
  # Phantom BATMAN placebo rows have compound = NA and can duplicate a real
  # row's arm_ind (same node/treatment, no compound) -- prefer the row that
  # actually carries a compound so downstream lookups never depend on which
  # of the two ties happened to sort first.
  arrange(arm_ind, is.na(compound)) %>%
  distinct(arm_ind, .keep_all = TRUE)
saveRDS(arm_info, args$arm_info_out)

study_info <- data_recon %>% select(study_ind, study_name = study) %>% distinct() %>% arrange(study_ind)
saveRDS(study_info, args$study_info_out)

cat(
  "BATMAN data built:", ns, "studies,", M, "treatment arms.\n",
  "Written to:", args$batman_out, "/", args$arm_info_out, "/", args$study_info_out, "\n"
)
