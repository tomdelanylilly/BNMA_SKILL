#!/usr/bin/env Rscript
# Builds a synthetic QA-schema-shaped Excel fixture with deliberately seeded
# edge cases, so the /bnma skill's scripts can be tested end-to-end without
# touching any real QA/PRD data. Columns follow GUIDE_README.md's QA file
# structure convention; only the columns the pipeline actually reads are
# populated with real values, the rest are left NA (same as real sparse rows).
#
# Seeded cases (see comments inline):
#   1. Near-duplicate compound pair, NOT co-occurring -> should be flagged.
#   2. Near-duplicate-looking pair that DOES co-occur in one study as
#      separate arms -> should be suppressed.
#   3. Route-pooling collision: identical treatment string under two aom
#      values for one compound -> should be flagged.
#   4. Correctly-disambiguated oral/injectable pair for another compound ->
#      should NOT be flagged.
#   5. A compound with a missing `aom` on some rows -> missing_route flag.
#   6. met-097 / berobenatide -- already resolved in compound_registry.yaml
#      -> should NOT be flagged despite being a spelling near-match.
#   7. A Phase 2 study and a Prediction-tier row, to exercise the
#      study-selection listing (step 3) and BATMAN phantom-placebo logic
#      (a study with no placebo arm).
#
# Usage: Rscript tests/make_fixture.R --out tests/fixtures/prd_fixture.xlsx

suppressPackageStartupMessages(library(writexl))

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(dirname(script_dir), "scripts", "lib_common.R"))

args <- parse_args(list(out = list(required = TRUE)))

blank <- function(n) rep(NA_character_, n)

row <- function(study_name, treatment, compound, aom, phase, se, pchg,
                 data_type = "publication", n = 100) {
  data.frame(
    time_entry = "20260814", study_name = study_name, treatment = treatment,
    compound = compound, sponsor = "lilly", aom = aom, phase = phase,
    study_duration = "36 week", n = n, baseline_wgt = 100,
    pchg_wl_ee = pchg, se_wl_ee = se, pchg_wl_tre = NA, se_wl_tre = NA,
    data_type = data_type, source = "synthetic fixture", population = "obese non-t2d",
    analysis_method = "mmrm on treatment", curator_name = "fixture", curator_note = NA,
    qc_name = NA, qc_note = NA, deriviation_spec = NA,
    stringsAsFactors = FALSE
  )
}

observed <- rbind(
  # --- Case 1: near-duplicate compound pair, distinct studies -> flagged ---
  row("canaflig-1",     "placebo",              "placebo",     NA,           "phase 3", 1.0, 0,    n = 80),
  row("canaflig-1",     "canaflig 10mg qw",      "canaflig",    "injectable", "phase 3", 0.5, -12.0, n = 80),
  row("canafligizon-1", "placebo",               "placebo",     NA,           "phase 3", 1.0, 0,    n = 90),
  row("canafligizon-1", "canafligizon 10mg qw",  "canafligizon","injectable", "phase 3", 0.5, -12.4, n = 90),

  # --- Case 2: similar-looking pair that DOES co-occur -> suppressed ---
  row("head2head-1", "placebo",         "placebo", NA, "phase 3", 1.0, 0,     n = 70),
  row("head2head-1", "drugalpha 5mg qw","drugalpha","injectable","phase 3", 0.4, -10.0, n = 70),
  row("head2head-1", "drugalphax 5mg qw","drugalphax","injectable","phase 3", 0.4, -9.0, n = 70),

  # --- Case 3: route-pooling collision (identical treatment string) -> flagged ---
  row("oral-study-1", "placebo",                "placebo",       NA,      "phase 3", 1.0, 0,    n = 60),
  row("oral-study-1", "orforglipron 3mg",        "orforglipron",  "oral",  "phase 3", 0.6, -8.0, n = 60),
  row("inject-study-1","placebo",                "placebo",       NA,      "phase 3", 1.0, 0,    n = 65),
  row("inject-study-1","orforglipron 3mg",       "orforglipron",  "injectable","phase 3", 0.6, -8.5, n = 65),

  # --- Case 4: correctly disambiguated route -> NOT flagged ---
  row("vk-oral-1",   "placebo",              "placebo","NA","phase 3", 1.0, 0,     n = 55),
  row("vk-oral-1",   "vk2735 10mg oral",     "vk2735", "oral", "phase 3", 0.5, -9.0,  n = 55),
  row("vk-inj-1",    "placebo",              "placebo","NA","phase 3", 1.0, 0,     n = 58),
  row("vk-inj-1",    "vk2735 10mg qw",       "vk2735", "injectable","phase 3", 0.5, -11.0, n = 58),

  # --- Case 5: missing aom on some rows for a compound -> missing_route flag ---
  row("missing-route-1", "placebo",             "placebo","NA","phase 3", 1.0, 0,    n = 50),
  row("missing-route-1", "danuglipron 5mg",     "danuglipron", NA, "phase 3", 0.5, -7.0, n = 50),
  row("missing-route-2", "danuglipron 5mg qd",  "danuglipron", "oral", "phase 3", 0.5, -7.5, n = 52),

  # --- Case 6: met-097/berobenatide, already resolved in registry ---
  row("legacy-code-1", "placebo",           "placebo",      NA,           "phase 2", 1.0, 0,    n = 40),
  row("legacy-code-1", "met-097 4.8mg qm",  "met-097",      "injectable", "phase 2", 0.6, -6.0, n = 40),
  row("bero-1",        "placebo",           "placebo",      NA,           "phase 3", 1.0, 0,    n = 75),
  row("bero-1",        "berobenatide 4.8mg qm","berobenatide","injectable","phase 3", 0.5, -13.0, n = 75),

  # --- Case 7: Phase 2 study + a study with no placebo arm (BATMAN test) ---
  row("ph2-study-1", "placebo",              "placebo",     NA,           "phase 2", 1.0, 0,    n = 30),
  row("ph2-study-1", "tirzepatide 5mg qw",   "tirzepatide", "injectable", "phase 2", 0.6, -14.0, n = 30),
  row("no-placebo-1", "tirzepatide 10mg qw", "tirzepatide", "injectable", "phase 3", 0.4, -18.0, n = 100),

  stringsAsFactors = FALSE
)

prediction <- row(
  "vk2735-itp", "vk2735 15mg qw", "vk2735", "injectable", "phase 2",
  0.8, -16.0, data_type = "internal projection", n = NA
)

summary_sheet <- data.frame(
  note = "Synthetic fixture for /bnma skill testing -- not real trial data",
  stringsAsFactors = FALSE
)

writexl::write_xlsx(
  list(Summary = summary_sheet, Observed = observed, Prediction = prediction),
  args$out
)

cat("Fixture written to:", args$out, "\n")
cat("Observed rows:", nrow(observed), " Prediction rows:", nrow(prediction), "\n")
