#!/usr/bin/env Rscript
# Step 5.6 of the /bnma skill: network/uncertainty/consistency/DIC
# diagnostics gate. Adapted from the atlas branch's diagnostics.R (read in
# full before porting) -- the node-splitting consistency check and the
# DIC-inconsistency check are close ports of that file's own working
# implementation, not a from-scratch reimplementation; only the data-access
# layer (which files/columns to read) is adapted to this skill's own
# arm_rows.rds/arm_info.rds/batman.rds schema instead of atlas's bundle.rds.
#
# Five checks, run together, worst-of-five verdict:
#   1. Convergence       -- reuses lib_common.R's compute_convergence_diagnostics()
#                            verbatim (already exists, don't reimplement).
#   2. Network           -- igraph: one connected component? indirect-only arms?
#   3. Uncertainty       -- flags single-study (fragile) arms via CrI width.
#   4. Consistency       -- node-splitting (netmeta::netsplit): direct vs.
#                            indirect evidence per loop-informed comparison.
#   5. DIC inconsistency -- NICE DSU TSD4: fits a second unrelated-mean-
#                            effects (UME) model, compares DIC to the
#                            ordinary consistency model. Runs by default;
#                            --skip-dic opts out (it's a second full JAGS fit).
#
# Must run via run_with_jags.sh (not run_r.sh) unless --skip-dic is passed --
# the DIC check needs rjags for its own second fit.
#
# Usage:
#   scripts/run_with_jags.sh scripts/check_network_diagnostics.R \
#     --batman <batman.rds> --arm-rows <arm_rows.rds> --arm-info <arm_info.rds> \
#     --samples <samples.rds> --model <model.txt> --out <network_diagnostics.yaml> \
#     [--gate] [--skip-dic]

suppressPackageStartupMessages({
  library(dplyr)
  library(coda)
  library(igraph)
  library(netmeta)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  batman   = list(required = TRUE),
  arm_rows = list(required = TRUE),
  arm_info = list(required = TRUE),
  samples  = list(required = TRUE),
  model    = list(default = NULL),
  out      = list(required = TRUE),
  gate     = list(flag = TRUE, default = FALSE),
  skip_dic = list(flag = TRUE, default = FALSE),
  n_adapt  = list(default = "2000"),
  n_burnin = list(default = "2000"),
  n_iter   = list(default = "6000")
))

# The DIC-inconsistency check (5) compares two models that must be identical
# except in exactly the one assumption being tested (consistency vs. UME) --
# both need the SAME flat/independent phi[i] baseline (the UME model below
# hardcodes one), or the DIC difference would partly reflect a baseline
# mismatch instead of purely the consistency question. Defaults to
# model_random.txt regardless of which model the main analysis fit used
# (mirrors atlas's own hardcoded choice of its equivalent model_flat.txt for
# this exact reason) -- override only if you deliberately want to test a
# different baseline's own consistency profile, not as a shortcut to reuse
# whatever --model the main fit happened to pass.
if (is.null(args$model)) {
  args$model <- file.path(dirname(script_dir), "model_random.txt")
}

batman_data <- readRDS(args$batman)
arm_rows <- readRDS(args$arm_rows)
arm_info <- readRDS(args$arm_info)
samples <- readRDS(args$samples)

cn <- colnames(samples[[1]])
samples_mat <- do.call(rbind, lapply(samples, function(x) x[, , drop = FALSE]))
colnames(samples_mat) <- cn

# ---------------------------------------------------------------------------
# 1. CONVERGENCE -- reuse the existing helper verbatim.
# ---------------------------------------------------------------------------
diag_convergence <- function() {
  diag <- compute_convergence_diagnostics(samples)
  print_convergence_diagnostics(diag)
  status <- switch(diag$verdict, pass = "PASS", warn = "WARN", fail = "FAIL", "WARN")
  list(status = status, max_rhat = diag$max_rhat, min_ess = diag$min_ess)
}

# ---------------------------------------------------------------------------
# 2. NETWORK CONNECTIVITY
# ---------------------------------------------------------------------------
diag_network <- function(dat, ref = "placebo") {
  edges <- do.call(rbind, lapply(split(dat$treatment, dat$study_name), function(t) {
    t <- unique(t)
    if (length(t) < 2) return(NULL)
    t(combn(sort(t), 2))
  }))
  g <- simplify(graph_from_edgelist(as.matrix(edges), directed = FALSE))
  comp <- components(g)
  connected <- comp$no == 1
  deg <- sort(degree(g), decreasing = TRUE)
  indirect <- if (ref %in% V(g)$name) {
    setdiff(setdiff(V(g)$name, ref), names(neighbors(g, ref)))
  } else {
    character()
  }
  status <- if (!connected) "FAIL" else if (length(indirect) > 0) "WARN" else "PASS"
  cat(sprintf("[2] NETWORK .......... %s   %d treatments, %d edges, %d component(s)\n",
              status, vcount(g), ecount(g), comp$no))
  cat("     hubs:", paste(sprintf("%s(%d)", names(head(deg, 4)), head(deg, 4)), collapse = ", "), "\n")
  if (!connected) cat("     FAIL: network is disconnected -- some treatments are not estimable.\n")
  if (length(indirect) > 0) {
    cat("     indirect-only (no direct", ref, "comparison; wider by construction):",
        paste(indirect, collapse = ", "), "\n")
  }
  list(status = status, connected = connected, indirect_only = indirect,
       n_treatments = vcount(g), n_edges = ecount(g), components = comp$no,
       hubs = as.list(head(deg, 4)))
}

# ---------------------------------------------------------------------------
# 3. UNCERTAINTY / EVIDENCE PANEL
# ---------------------------------------------------------------------------
widths_from_samples <- function(dat) {
  active <- arm_info %>% filter(treatment != "placebo") %>% pull(treatment) %>% unique()
  active <- active[paste0("d[", arm_info$arm_ind[match(active, arm_info$treatment)], "]") %in% colnames(samples_mat)]
  wdf <- do.call(rbind, lapply(active, function(nm) {
    k <- arm_info$arm_ind[arm_info$treatment == nm][1]
    ds <- samples_mat[, paste0("d[", k, "]")]
    data.frame(treatment = nm, width = as.numeric(quantile(ds, .975) - quantile(ds, .025)))
  }))
  nst <- dat %>% distinct(study_name, treatment) %>% count(treatment, name = "n_studies")
  wdf <- left_join(wdf, nst, by = "treatment")
  wdf$n_studies[is.na(wdf$n_studies)] <- 1
  wdf
}

diag_uncertainty <- function(width_df) {
  fragile <- width_df %>% filter(n_studies <= 1)
  status <- if (nrow(fragile) > 0) "WARN" else "PASS"
  cat(sprintf("[3] UNCERTAINTY ...... %s   CrI width range %.1f-%.1f | %d single-study arm(s)\n",
              status, min(width_df$width), max(width_df$width), nrow(fragile)))
  if (nrow(fragile) > 0) {
    cat("     fragile (single study, treat as provisional):",
        paste(head(fragile$treatment, 8), collapse = ", "),
        if (nrow(fragile) > 8) sprintf("(+%d more)", nrow(fragile) - 8) else "", "\n")
  }
  list(status = status, n_single_study = nrow(fragile),
       width_min = min(width_df$width), width_max = max(width_df$width),
       fragile_treatments = as.list(fragile$treatment))
}

# ---------------------------------------------------------------------------
# 4. CONSISTENCY (node-splitting)
# ---------------------------------------------------------------------------
diag_consistency <- function(dat, ref = "placebo", alpha = 0.05) {
  dat <- dat[!is.na(dat$y) & !is.na(dat$se), ]
  ctr <- do.call(rbind, lapply(split(dat, dat$study_name), function(s) {
    if (nrow(s) < 2) return(NULL)
    cb <- combn(nrow(s), 2)
    do.call(rbind, lapply(seq_len(ncol(cb)), function(k) {
      i <- cb[1, k]; j <- cb[2, k]
      data.frame(studlab = s$study_name[1], treat1 = s$treatment[i], treat2 = s$treatment[j],
                 TE = s$y[i] - s$y[j], seTE = sqrt(s$se[i]^2 + s$se[j]^2), stringsAsFactors = FALSE)
    }))
  }))
  nsub <- tryCatch(netconnection(treat1, treat2, studlab, data = ctr)$n.subnets, error = function(e) NA)
  if (!is.na(nsub) && nsub > 1) {
    cat(sprintf("[4] CONSISTENCY ...... SKIP   real-evidence network has %d sub-networks; only phantom-placebo\n", nsub))
    cat("                     augmentation connects them for the Bayesian fit, so those cross-network\n")
    cat("                     estimates lean on the imputed placebo and cannot be consistency-checked.\n")
    return(list(status = "SKIP", n_tested = 0, n_inconsistent = 0, subnets = nsub))
  }
  nm <- tryCatch(
    suppressWarnings(netmeta(TE, seTE, treat1, treat2, studlab, data = ctr,
                             reference.group = ref, sm = "MD", common = FALSE, random = TRUE)),
    error = function(e) NULL
  )
  if (is.null(nm)) {
    cat("[4] CONSISTENCY ...... SKIP   node-splitting could not fit this network\n")
    cat("                     (disconnected sub-network, or too few independent loops).\n")
    return(list(status = "SKIP", n_tested = 0, n_inconsistent = 0))
  }
  ns_split <- suppressWarnings(netsplit(nm))
  cmp <- ns_split$compare.random
  dir <- ns_split$direct.random[, c("comparison", "TE")]; names(dir)[2] <- "direct"
  ind <- ns_split$indirect.random[, c("comparison", "TE")]; names(ind)[2] <- "indirect"
  cmp <- merge(merge(cmp[, c("comparison", "TE", "p")], dir, by = "comparison", all.x = TRUE),
               ind, by = "comparison", all.x = TRUE)
  testable <- cmp[!is.na(cmp$p) & !is.na(cmp$direct) & !is.na(cmp$indirect), ]
  if (nrow(testable) == 0) {
    cat("[4] CONSISTENCY ...... N/A    no independent loops -- network is star-shaped;\n")
    cat("                     consistency is not assessable. Add a head-to-head study to enable this check.\n")
    return(list(status = "N/A", n_tested = 0, n_inconsistent = 0))
  }
  testable <- testable[order(testable$p), ]
  flagged <- testable[testable$p < alpha, ]
  status <- if (nrow(flagged) > 0) "FAIL" else "PASS"
  cat(sprintf("[4] CONSISTENCY ...... %s   %d loop-informed comparison(s) tested, %d inconsistent (p<%.2f)\n",
              status, nrow(testable), nrow(flagged), alpha))
  show <- head(testable, 8)
  for (r in seq_len(nrow(show))) {
    cat(sprintf("     %-46s direct %+.2f | indirect %+.2f | diff %+.2f (p=%.3f)%s\n",
                substr(show$comparison[r], 1, 46), show$direct[r], show$indirect[r],
                show$TE[r], show$p[r], ifelse(show$p[r] < alpha, "  <-- INCONSISTENT", "")))
  }
  list(status = status, n_tested = nrow(testable), n_inconsistent = nrow(flagged),
       flagged_comparisons = if (nrow(flagged) > 0) {
         lapply(seq_len(nrow(flagged)), function(r) list(
           comparison = flagged$comparison[r], direct = round(flagged$direct[r], 2),
           indirect = round(flagged$indirect[r], 2), p = round(flagged$p[r], 3)
         ))
       } else list())
}

# ---------------------------------------------------------------------------
# 5. DIC-BASED INCONSISTENCY (NICE DSU TSD4)
# ---------------------------------------------------------------------------
ume_model_text <- function() {
  'model{
    for(i in 1:ns){ phi[i] ~ dnorm(0.0, 0.0001) }
    for(i in 1:ns){ for(j in 1:na[i]){
      y[i,j] ~ dnorm(eta[i,j], 1/se[i,j]^2)
    } }
    for(i in 1:ns){ eta[i,1] <- phi[i] + delta[i,1]
      for(j in 2:na[i]){ eta[i,j] <- phi[i] + delta[i,j] } }
    for(i in 1:ns){ delta[i,1] <- 0
      for(j in 2:na[i]){
        delta[i,j] ~ dnorm(sgn[i,j]*mu[edge[i,j]], tau2)
      } }
    for(e in 1:E){ mu[e] ~ dnorm(0, 1e-04) }
    sigma ~ dunif(0,8); tau2 <- 1/(sigma*sigma)
  }'
}

build_edge_index <- function(arms_per_study) {
  edges <- list()
  for (arms in arms_per_study) {
    if (length(arms) < 2) next
    ref <- arms[1]
    for (a in arms[-1]) {
      key <- paste(min(ref, a), max(ref, a))
      if (!key %in% names(edges)) edges[[key]] <- length(edges) + 1
    }
  }
  edges
}

diag_dic_inconsistency <- function() {
  suppressPackageStartupMessages(library(rjags))
  na_v <- batman_data$na; ns_ <- batman_data$ns; trt <- batman_data$trt
  arms_per_study <- lapply(seq_len(ns_), function(i) trt[i, 1:na_v[i]])
  edges <- build_edge_index(arms_per_study)
  E <- length(edges)
  if (E == 0 || all(vapply(arms_per_study, length, integer(1)) <= 1)) {
    cat("[5] DIC INCONSISTENCY .. N/A    no multi-arm/edge structure to compare.\n")
    return(list(status = "N/A"))
  }
  mx <- ncol(trt)
  edge_m <- matrix(NA_integer_, ns_, mx); sgn_m <- matrix(NA_integer_, ns_, mx)
  for (i in seq_len(ns_)) {
    arms <- arms_per_study[[i]]
    if (length(arms) < 2) next
    ref <- arms[1]
    for (jj in 2:length(arms)) {
      a <- arms[jj]
      key <- paste(min(ref, a), max(ref, a))
      edge_m[i, jj] <- edges[[key]]
      sgn_m[i, jj] <- if (a >= ref) 1 else -1
    }
  }

  n_adapt <- as.integer(args$n_adapt); n_burnin <- as.integer(args$n_burnin); n_iter <- as.integer(args$n_iter)

  jm_c <- jags.model(args$model, batman_data, n.chains = 3, n.adapt = n_adapt, quiet = TRUE)
  update(jm_c, n_burnin)
  dic_c <- dic.samples(jm_c, n.iter = n_iter, type = "pD")

  ume_file <- tempfile(fileext = ".txt")
  writeLines(ume_model_text(), ume_file)
  ume_data <- batman_data
  ume_data$edge <- edge_m; ume_data$sgn <- sgn_m; ume_data$E <- E
  jm_u <- suppressWarnings(jags.model(ume_file, ume_data, n.chains = 3, n.adapt = n_adapt, quiet = TRUE))
  update(jm_u, n_burnin)
  dic_u <- dic.samples(jm_u, n.iter = n_iter, type = "pD")

  DIC_c <- sum(dic_c$deviance) + sum(dic_c$penalty)
  DIC_u <- sum(dic_u$deviance) + sum(dic_u$penalty)
  diff <- DIC_c - DIC_u
  status <- if (diff > 5) "FAIL" else if (diff > 2) "WARN" else "PASS"
  cat(sprintf("[5] DIC INCONSISTENCY .. %s   DIC(consistency)=%.1f  DIC(UME/inconsistency)=%.1f  diff=%+.1f\n",
              status, DIC_c, DIC_u, diff))
  cat("     rule: diff should be <=2 (ideally negative = consistency preferred, per NICE DSU TSD4)\n")
  if (status != "PASS") {
    cat("     -> inconsistency model fits meaningfully better; examine deviance contributions\n")
    cat("        per study/arm before trusting the consistency-model forest.\n")
  }
  list(status = status, DIC_consistency = DIC_c, DIC_inconsistency = DIC_u, diff = diff, n_edge_types = E)
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
cat("================ BNMA NETWORK DIAGNOSTICS ================\n")
r1 <- diag_convergence()
r2 <- diag_network(arm_rows)
r3 <- diag_uncertainty(widths_from_samples(arm_rows))
r4 <- diag_consistency(arm_rows)
r5 <- if (!args$skip_dic) diag_dic_inconsistency() else {
  cat("[5] DIC INCONSISTENCY .. SKIP   --skip-dic passed\n")
  list(status = "SKIP")
}

statuses <- c(r1$status, r2$status, r3$status, r4$status, r5$status)
overall <- if ("FAIL" %in% statuses) "FAIL" else if ("WARN" %in% statuses) "WARN" else "PASS"
cat("-------------------------------------------------\n")
cat("OVERALL:", overall,
    if (overall == "FAIL") " -- do NOT ship this forest until resolved."
    else if (overall == "WARN") " -- review warnings before shipping."
    else " -- clear to plot.", "\n")

report <- list(
  generated_at = as.character(Sys.time()),
  overall = overall,
  convergence = r1,
  network = r2,
  uncertainty = r3,
  consistency = r4,
  dic_inconsistency = r5
)
write_yaml(report, args$out)
cat("Written to:", args$out, "\n")

if (args$gate && overall == "FAIL") {
  cat("GATE: FAIL -- blocking the forest plot step (exit 2).\n")
  quit(status = 2)
}
