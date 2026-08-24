# Shared helpers for the /bnma skill's R scripts. Sourced, never run directly.

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Collapse repeated internal whitespace and trim ends. trimws() alone
#' misses internal double-spaces (e.g. "semaglutide 2.4mg  qw" vs
#' "semaglutide 2.4mg qw"), which otherwise silently fragments one dose into
#' two separate treatment arms in the BNMA -- found by testing against real
#' PRD data, not hypothetical.
squish_ws <- function(x) gsub("[[:space:]]+", " ", trimws(x))

#' Parse simple `--flag value` command-line arguments into a named list.
#' Flags may be written with hyphens (`--batman-out`) even though the spec's
#' keys use underscores (`batman_out`) -- normalized here so call sites can
#' use either without the two silently failing to match.
parse_args <- function(spec) {
  raw <- commandArgs(trailingOnly = TRUE)
  out <- list()
  for (name in names(spec)) out[[name]] <- spec[[name]]$default
  i <- 1
  while (i <= length(raw)) {
    key <- gsub("-", "_", sub("^--", "", raw[i]))
    if (!key %in% names(spec)) stop("Unknown argument: --", raw[i])
    if (isTRUE(spec[[key]]$flag)) {
      out[[key]] <- TRUE
      i <- i + 1
    } else {
      if (i == length(raw)) stop("Missing value for --", raw[i])
      out[[key]] <- raw[i + 1]
      i <- i + 2
    }
  }
  for (name in names(spec)) {
    if (isTRUE(spec[[name]]$required) && is.null(out[[name]])) {
      stop("Missing required argument: --", name)
    }
  }
  out
}

#' Read a sheet by name with a numeric-index fallback, since older QA/PRD
#' workbooks use sheet index (2 = Observed, 3 = Prediction/ITP) while newer
#' ones name sheets "Observed"/"Prediction" (see GUIDE_README.md QA file
#' structure convention). Returns NULL (with a message, not an error) if
#' neither the name nor the fallback index sheet exists, so callers can
#' proceed with whichever tiers/sheets actually exist.
read_sheet_with_fallback <- function(path, sheet_name, fallback_index) {
  sheets <- readxl::excel_sheets(path)
  # Case-insensitive name match -- confirmed real case, 2026-08-20: a T2D
  # HbA1c workbook with sheets literally named "observed"/"prediction"
  # (lowercase). Exact %in% matching missed both, fell through to the
  # POSITIONAL fallback for "Prediction" -- which landed on an unrelated
  # "chinese population" sheet sitting between them (position 3), silently
  # mislabeling it as the prediction tier while the real "prediction" sheet
  # (position 4) was never read at all. Matching case-insensitively finds
  # the real sheet directly by name in this case, so the fragile positional
  # fallback is only reached when a workbook truly has no matching sheet at
  # all -- exactly what it was meant for.
  match_idx <- which(tolower(trimws(sheets)) == tolower(trimws(sheet_name)))
  if (length(match_idx) > 0) {
    return(readxl::read_excel(path, sheet = sheets[match_idx[1]]))
  }
  if (!is.null(fallback_index) && fallback_index <= length(sheets)) {
    message(
      "Sheet '", sheet_name, "' not found in ", path,
      " - falling back to sheet index ", fallback_index,
      " ('", sheets[fallback_index], "'). Confirm this is really the ",
      sheet_name, " tab before trusting the result."
    )
    return(readxl::read_excel(path, sheet = fallback_index))
  }
  message("No '", sheet_name, "' sheet (and no usable fallback) in ", path)
  NULL
}

#' Coerce every column to character, for safe bind_rows() across sheets/tiers
#' with inconsistent column typing (mirrors the existing misc5 scripts'
#' pattern of casting before bind_rows, then re-casting numeric columns after).
stringify_all <- function(df) {
  if (is.null(df)) return(NULL)
  dplyr::mutate(df, dplyr::across(dplyr::everything(), as.character))
}

QA_NUMERIC_COLS <- c(
  "n", "baseline_wgt", "pchg_wl_ee", "se_wl_ee", "pchg_wl_tre", "se_wl_tre"
)

#' Re-cast the QA schema's numeric columns back to numeric after a
#' stringify_all()-based bind_rows(), leaving any column not present alone.
#' The fixed list above is the weight-loss QA/PRD schema's own numeric
#' columns -- harmless (via `intersect()`) for any other endpoint's workbook,
#' since none of those column names will be present to recast. This is NOT a
#' functional gap for a non-weight-loss endpoint though: build_batman_data.R
#' wraps every read of the manifest's own `effect_col`/`se_col` in an
#' explicit `as.numeric()` regardless of this recast, so an HbA1c/physical-
#' function column left as character here still ends up numeric where it
#' actually matters. This list only affects merged.rds's column *type* for
#' anyone inspecting it directly, not any value the model sees.
recast_numeric_cols <- function(df) {
  present <- intersect(QA_NUMERIC_COLS, names(df))
  dplyr::mutate(df, dplyr::across(dplyr::all_of(present), as.numeric))
}

#' Whether this network's data can actually support a random-effects
#' heterogeneity estimate, or whether every treatment node is fed by exactly
#' one study -- the literal "star network" case in pf_nma.R (a physical-
#' function sub-network where STEP-1/REDEFINE-1/SURMOUNT-1-GPHK each supply
#' the ONLY study for their own vs-placebo comparison): "with only 1 study
#' per comparison, between-study heterogeneity cannot be estimated;
#' fixed-effects is the appropriate primary analysis." That file's model is
#' entirely different (frequentist netmeta, not this skill's JAGS BNMA) --
#' only the underlying identifiability argument transfers.
#'
#' Proxy used here (documented as a proxy, not a literal graph-theoretic
#' multi-edge check): per non-placebo treatment node (arm_ind != 1), count
#' distinct contributing studies. If NO node has >=2, every contrast in the
#' network is single-study-supported and tau/sigma has nothing to be
#' estimated from -- a random-effects fit would be reporting its prior back,
#' not a data-driven heterogeneity estimate.
#'
#' `data_recon` must have `study_ind` and `arm_ind` columns (one row per
#' study-arm, same shape build_batman_data.R already has in scope when it
#' builds `trt`/`y`/`se`).
compute_heterogeneity_estimability <- function(data_recon) {
  per_node <- data_recon %>%
    dplyr::filter(arm_ind != 1) %>%
    dplyr::group_by(arm_ind) %>%
    dplyr::summarise(n_studies = dplyr::n_distinct(study_ind), .groups = "drop")

  n_multi_study  <- sum(per_node$n_studies >= 2)
  n_single_study <- sum(per_node$n_studies == 1)
  is_star_network <- nrow(per_node) > 0 && n_multi_study == 0

  list(
    n_nodes_total = nrow(per_node),
    n_nodes_multi_study = n_multi_study,
    n_nodes_single_study = n_single_study,
    is_star_network = is_star_network,
    recommendation = if (is_star_network) {
      "fixed_effect -- every treatment node is fed by exactly one study; heterogeneity is not estimable from this data (per pf_nma.R's identical situation and rationale)."
    } else {
      "rand_effect (or fixed_effect, analyst's choice) -- at least one node has multi-study support, so heterogeneity can be estimated from the network as a whole."
    }
  )
}

#' Console-print a compute_heterogeneity_estimability() result.
print_heterogeneity_estimability <- function(het) {
  cat("=== Heterogeneity Estimability ===\n")
  cat("Treatment nodes:", het$n_nodes_total,
      " (", het$n_nodes_multi_study, "with >=2 studies,",
      het$n_nodes_single_study, "with exactly 1 study)\n")
  if (het$is_star_network) {
    cat("*** STAR NETWORK -- every node is single-study. ***\n")
  }
  cat("Recommended model_type:", het$recommendation, "\n")
}
