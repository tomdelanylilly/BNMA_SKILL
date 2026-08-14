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
  if (sheet_name %in% sheets) {
    return(readxl::read_excel(path, sheet = sheet_name))
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
recast_numeric_cols <- function(df) {
  present <- intersect(QA_NUMERIC_COLS, names(df))
  dplyr::mutate(df, dplyr::across(dplyr::all_of(present), as.numeric))
}
