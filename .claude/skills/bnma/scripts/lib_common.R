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

#' MCMC convergence diagnostics on an mcmc.list (from coda.samples()).
#' Thresholds are the BayesianAgent plugin's JAGS/R2jags bar (its own
#' model-diagnostics skill): Rhat <= 1.1 and ESS >= 100 to pass -- looser
#' than the 1.01/400 bar that skill quotes for Stan/NUTS fits, since a
#' Gibbs sampler's per-iteration efficiency isn't directly comparable. Used
#' by both check_convergence.R (standalone re-check) and fit_bnma_model.R
#' (automatic, every fit) so the two never drift apart.
CONVERGENCE_THRESHOLDS <- list(
  rhat_good = 1.01, rhat_concern = 1.10,
  ess_good = 400, ess_min = 100
)

compute_convergence_diagnostics <- function(samples, thresholds = CONVERGENCE_THRESHOLDS) {
  n_chains <- length(samples)
  n_iter_per_chain <- nrow(samples[[1]])

  # Drop degenerate (zero-variance) nodes before scoring -- e.g. d[1], the
  # reference treatment, is fixed at exactly 0 by model construction
  # (model_*.txt's `d[1] <- 0`), not actually sampled. Its ESS is
  # meaningless (mathematically 0, since there's no variance to have an
  # "effective" sample of) and would force a false FAIL on every single fit
  # regardless of how well the real parameters converged.
  all_draws <- do.call(rbind, lapply(samples, function(x) x[, , drop = FALSE]))
  node_var <- apply(all_draws, 2, var)
  degenerate <- names(node_var)[!is.finite(node_var) | node_var < 1e-12]
  scored <- setdiff(colnames(all_draws), degenerate)

  if (length(scored) == 0) {
    return(list(
      n_chains = n_chains, n_iterations_per_chain = n_iter_per_chain,
      thresholds = thresholds, max_rhat = NA, max_rhat_node = NA_character_,
      min_ess = NA, min_ess_node = NA_character_,
      rhat_note = "Every monitored node is constant -- nothing to score. Check the model/manifest for a real error.",
      verdict = "fail"
    ))
  }

  samples_scored <- samples[, scored, drop = FALSE]

  ess_per_chain <- sapply(samples_scored, coda::effectiveSize)
  ess <- if (is.matrix(ess_per_chain)) rowSums(ess_per_chain) else sum(ess_per_chain)
  names(ess) <- scored

  rhat_result <- tryCatch(
    coda::gelman.diag(samples_scored, multivariate = FALSE),
    error = function(e) NULL
  )
  if (is.null(rhat_result)) {
    rhat <- setNames(rep(NA_real_, length(ess)), names(ess))
    rhat_note <- "gelman.diag() failed on the scored nodes -- Rhat unavailable, verdict based on ESS only."
  } else {
    rhat <- rhat_result$psrf[, "Point est."]
    rhat_note <- NULL
  }
  if (length(degenerate) > 0) {
    degenerate_note <- paste0(
      length(degenerate), " constant node(s) excluded from scoring (e.g. the fixed reference treatment): ",
      paste(head(degenerate, 5), collapse = ", "), if (length(degenerate) > 5) ", ..." else ""
    )
    rhat_note <- if (is.null(rhat_note)) degenerate_note else paste(rhat_note, degenerate_note, sep = " ")
  }

  max_rhat <- suppressWarnings(max(rhat, na.rm = TRUE))
  max_rhat_node <- if (is.finite(max_rhat)) names(rhat)[which.max(rhat)] else NA_character_
  min_ess <- min(ess)
  min_ess_node <- names(ess)[which.min(ess)]

  rhat_fail <- is.finite(max_rhat) && max_rhat > thresholds$rhat_concern
  ess_fail  <- min_ess < thresholds$ess_min
  verdict <- if (rhat_fail || ess_fail) "fail" else if (
    (is.finite(max_rhat) && max_rhat > thresholds$rhat_good) || min_ess < thresholds$ess_good
  ) "warn" else "pass"

  list(
    n_chains = n_chains,
    n_iterations_per_chain = n_iter_per_chain,
    thresholds = thresholds,
    max_rhat = if (is.finite(max_rhat)) round(max_rhat, 4) else NA,
    max_rhat_node = max_rhat_node,
    min_ess = round(min_ess, 1),
    min_ess_node = min_ess_node,
    rhat_note = rhat_note,
    verdict = verdict
  )
}

#' Console-print a compute_convergence_diagnostics() result in the
#' BayesianAgent-style checklist format (checkmarks per metric).
print_convergence_diagnostics <- function(diag) {
  th <- diag$thresholds
  rhat_mark <- if (!is.finite(diag$max_rhat)) "?" else if (diag$max_rhat <= th$rhat_good) "✓" else if (diag$max_rhat <= th$rhat_concern) "~" else "✗"
  ess_mark  <- if (diag$min_ess >= th$ess_good) "✓" else if (diag$min_ess >= th$ess_min) "~" else "✗"

  cat("=== MCMC Convergence Diagnostics ===\n")
  cat("Chains:", diag$n_chains, " Iterations/chain (post-thin):", diag$n_iterations_per_chain, "\n")
  cat("Max Rhat:", ifelse(is.finite(diag$max_rhat), diag$max_rhat, "NA"), "(", diag$max_rhat_node, ")", rhat_mark, "\n")
  cat("Min ESS: ", diag$min_ess, "(", diag$min_ess_node, ")", ess_mark, "\n")
  cat("Verdict:", toupper(diag$verdict), "\n")
  if (!is.null(diag$rhat_note)) cat("Note:", diag$rhat_note, "\n")

  if (diag$verdict == "fail") {
    cat("\n*** CONVERGENCE WARNING ***\n")
    cat("This fit does not meet the minimum bar (Rhat <=", th$rhat_concern, ", ESS >=", th$ess_min, ").\n")
    cat("Do not treat the forest plot as reliable without surfacing this to the user and\n")
    cat("getting an explicit decision (re-fit with more iterations, or proceed anyway with\n")
    cat("this caveat documented) -- same rule as every other gate in this skill.\n")
  }
}
