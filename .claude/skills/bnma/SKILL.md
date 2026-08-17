---
name: bnma
description: >
  Run an obesity-landscape Bayesian network meta-analysis (BNMA) on weight-
  loss data with forced study-selection confirmation and a naming/route
  pooling-risk QA gate, instead of a hardcoded, hand-edited study list. Use
  this skill whenever the user wants to run, update, or refresh a BNMA
  forest plot from the QA/PRD weight-loss dataset, or mentions "/bnma",
  "run the meta-analysis", "BATMAN", or a compound landscape forest plot.
---

# /bnma

Guided BNMA workflow for the obesity weight-loss QA/PRD dataset. Reuses the
existing BATMAN-augmentation + JAGS + forest-plot pipeline (see the misc5
project's R scripts for the reference implementation this was built from),
but replaces every place that pipeline made a silent, hardcoded decision
with an explicit step the user must confirm. See `DESIGN.md` in this skill's
repo (or the project's `GUIDE_README.md`) for why each step exists.

**Do not skip steps or assume defaults on the user's behalf.** The whole
point of this skill is that a low-dose Phase 2 study or an oral/injectable
mix-up must never enter a model silently again — every step below ends with
the user explicitly confirming something in writing (the manifest), not you
inferring it from what "usually" gets excluded.

## Step 0 — Locate the data

Ask the user (if not already given) for the PRD file path and, if there's a
newer QA file not yet promoted, its path too. Resolve per the workflow doc's
fallback rule: try the QA path first, fall back to PRD if it's moved/been
promoted. Do not guess a path — ask, or use exactly what the user gives you.

## Step 1 — Load & merge

```bash
scripts/run_r.sh scripts/load_merge_data.R \
  --prd <prd_path.xlsx> [--qa <qa_path.xlsx>] --out /tmp/bnma_merged.rds
```

Read the printed summary (row/study/compound counts) back to the user so
they know what's actually in scope before the QA gate runs.

## Step 2 — Naming/pooling QA gate

```bash
scripts/run_r.sh scripts/check_naming_pooling.R \
  --data /tmp/bnma_merged.rds --out /tmp/bnma_naming_report.json
```

Read the JSON report. For every **active** (non-suppressed) `compound_flags`
entry and every `pooling_flags` entry:

- Present it to the user in plain language — what was flagged and why (the
  report's `message`/`suppressed_reason` fields already explain the
  mechanism, e.g. "these rows will collapse into ONE treatment arm").
- Ask them to resolve it: for a compound-name flag, "are `a` and `b` the same
  compound, or genuinely different?" For a pooling flag, "should this be
  split into separate arms by route, or is this pooling intentional?"
- **Persist their answer** by appending a `resolved_pairs` entry to
  `compound_registry.yaml` (compound flags) using the Edit tool directly —
  do this in this skill's own repo copy, not by re-running a script — so the
  same pair is never re-flagged on a future run. Pooling-flag resolutions get
  recorded directly in the manifest (step 4), not the registry, since they're
  data-specific rather than a general compound-identity fact.
- If there are zero active flags, say so plainly and move on — don't invent
  concerns that aren't in the report.

Do not proceed to step 3 until every active flag has an explicit resolution.

## Step 2.5 — Scope filters (route of administration, observed vs. projection, compound)

Before enumerating individual studies, ask two blanket scoping questions —
these are the two filters a statistician typically already knows the answer
to before opening the data (per a specific compound-launch or route
comparison request), so ask them up front rather than making the user
discover route/evidence mixing one flagged row at a time later:

- **Route of administration**: oral only, injectable only, or both (default
  both).
- **Evidence type**: observed only, projection only, or both (default both).

Record the answers as two new top-level manifest fields, `route_filter` and
`evidence_filter` (see step 4's example). Leave a field out entirely (or set
it to `both`) if the user wants no filtering on that axis — `build_batman_data.R`
treats a missing field as `both`, so manifests written before this step
existed keep working unchanged.

Note for the route filter: placebo rows are never dropped by it, regardless
of which route is chosen — a placebo arm's `aom` tag reflects its paired
active comparator's route, not a property of placebo itself, so filtering it
out would just remove a study's reference arm for no reason.

### Compound-first entry point

A run can also start from a user-supplied list of specific
compounds/treatments rather than a full unscoped study review (e.g. "I need
these 21 treatments in the analysis"). This is a legitimate alternate entry
point, not a shortcut around the naming/pooling gate — still run step 2 on
the *full* merged dataset first, so a typo'd or aliased spelling of a
requested compound gets caught rather than silently falling outside the
list just because it doesn't match verbatim. Then:

1. Match each requested treatment string against the merged data's actual
   `treatment` values. Report exact matches plainly; for anything without an
   exact match, use edit-distance/substring candidates (same mechanism as
   step 2's compound check) and confirm the resolution with the user rather
   than guessing — a missing dose suffix (e.g. "Tirzepatide 5mg" vs.
   "tirzepatide 5mg qw") is usually unambiguous, but a request like "X
   Pooled" that doesn't correspond to any single row in the source data
   needs an explicit decision (which single arm to use, or whether to
   compute a genuinely new derived value — never invent one silently).
2. Derive the distinct compound list from the resolved treatments and record
   it as `compound_filter` in the manifest — a list of compound names.
   `build_batman_data.R` applies this as a **row-level** filter (drop any row
   whose `compound` isn't in the list), not a study-level one: a study that
   mixes a wanted compound with an unwanted one (e.g. a trial with a
   semaglutide arm and a separate bimagrumab arm) keeps its wanted-compound
   rows and drops the rest, rather than pulling in compounds nobody asked
   for just because they share a study. Placebo rows are always exempt, same
   as the route filter.
3. **Still enumerate every study for an explicit decision, same as step 3.**
   Row-level compound filtering does not exempt a study from needing a
   decision — a study with no requested compound will usually still have
   its placebo row survive (compound-exempt), so it still appears in
   `build_batman_data.R`'s required-decision list. Batch-exclude these with
   a shared reason ("not one of the requested compounds for this run") —
   this is expected, not a bug to work around.

## Step 3 — Study/treatment selection

From the merged data (after step 2's resolutions), enumerate every distinct
`study_name`, with its `phase`, `data_type` (observed vs. prediction), and
whether it has usable rows (non-missing `se_wl_ee`). Group studies with
Phase 1/2 data and prediction rows into a clearly visually separate list —
these are the categories where past incidents happened (a Phase 2 study
skewing a result) — and ask the user to explicitly include or exclude each
one, with a one-line reason. Phase 3 observed studies still need a decision,
just a lower-friction one ("include all Phase 3 observed unless you say
otherwise" is fine to *propose*, but the user must still say yes).

Also ask which treatments/doses should appear on the eventual forest plot
(`plot_treatments`) and in what order, and which effect type they want:
`relative` (placebo-adjusted, the usual view) or `absolute`.

## Step 4 — Write the manifest

Write a YAML manifest capturing everything decided so far — this is the
traceable artifact that replaces a commented-out R vector. Example shape:

```yaml
created_at: "2026-08-14"
source_data:
  prd: /lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_20260805.xlsx
  qa: null
source_program: <path to whatever script/session produced this run>
route_filter: both # oral | injectable | both -- from step 2.5; omit or "both" = no route filtering
evidence_filter: both # observed | prediction | both -- from step 2.5; omit or "both" = no evidence filtering
compound_filter: null # optional list of compound names -- from step 2.5's compound-first entry point; omit/null = no compound filtering
naming_pooling_resolutions:
  - kind: compound_flag
    compound_a: canaflig
    compound_b: canafligizon
    decision: different
    note: "confirmed distinct INNs with the curator"
  - kind: pooling_flag
    compound: orforglipron
    treatment: "orforglipron 3mg"
    decision: split_by_route
    note: "oral and injectable rows were sharing one treatment label; relabeled oral rows"
studies:
  - study_name: surmount-1
    phase: "phase 3"
    data_type: observed
    include: true
  - study_name: retatrutide_ph2_gzbf
    phase: "phase 2"
    data_type: observed
    include: false
    reason: "Phase 2 only, excluded per analyst decision"
compound_relabels:
  - from: "exenatide qw"
    to: exenatide
    reason: "Inconsistently labeled subset of rows -- see naming_pooling_resolutions above for why."
treatment_relabels:
  - from: "some inconsistently-labeled dose string"
    to: "the canonical dose string used elsewhere for the same treatment"
    reason: "Naming-QA flag resolved as a mislabeling, not a genuinely different treatment."
row_exclusions:
  - study_name: some-study
    treatment: "some treatment 5mg qd"
    "n": 37 # quote this key -- bare `n:` parses as boolean FALSE in YAML 1.1, not the string "n", and the exclusion silently stops disambiguating (hit this for real once)
    reason: "Duplicate row sharing (study_name, treatment) with another row -- n disambiguates which one to drop."
plot_treatments:
  - tirzepatide 5mg qw
  - tirzepatide 10mg qw
  - tirzepatide 15mg qw
effect_type: relative
```

`compound_relabels` is for a naming-QA flag resolved as "these rows were
mislabeled, merge into the canonical spelling" -- applied globally by
compound string. `treatment_relabels` is the same idea but for the
`treatment` string itself (changes which arm a row maps to, not just which
compound it's attributed to). `row_exclusions` is for a single anomalous or
duplicate row within an otherwise-included study; add `"n"` (quoted) when
two rows share the same `(study_name, treatment)` and need a third field to
tell them apart.

**Any study lacking a literal placebo row gets a phantom placebo arm
(SE=1, y=NA) injected automatically** — matches
`efficacy_bnma_v3_gzmu_misc5.R`'s own logic exactly. This is not something
the skill second-guesses or gates on a per-study decision; if this behavior
ever needs revisiting, that's a call for whoever owns the BATMAN+/NMA
methodology, not something to change unilaterally here.

Save it under the dated `programs/YYYYMMDD_.../` folder for this run (ask the
user for that folder if it's not obvious), e.g. `study_selection_manifest.yaml`.

**Every study found in step 1's merged data must appear under `studies:`.**
`build_batman_data.R` (step 5) enforces this itself and will refuse to run
otherwise — that's intentional, not a bug to work around.

## Step 5 — Build BATMAN data, fit the model

```bash
scripts/run_r.sh scripts/build_batman_data.R \
  --data /tmp/bnma_merged.rds --manifest <manifest.yaml> \
  --batman-out /tmp/bnma_batman.rds --arm-info-out /tmp/bnma_arm_info.rds \
  --study-info-out /tmp/bnma_study_info.rds
```

If this errors because studies are missing from the manifest, that's the
intended guard — go back to step 3/4 with the user, don't patch around it.

Then fit (or load a cached fit of) the model. **Must go through the JAGS
wrapper** — plain `Rscript` will fail to load `rjags` in this environment:

```bash
scripts/run_with_jags.sh scripts/fit_bnma_model.R \
  --batman /tmp/bnma_batman.rds --model model_simultaneous.txt \
  --cache <programs_folder>/samples_<run_name>.rds
```

Give the cache file a run-specific name (per the workflow doc's "cached MCMC
samples are expensive to regenerate, version-specific name" rule) — don't
reuse another run's cache path.

## Step 6 — Forest plot + footnote

```bash
scripts/run_r.sh scripts/make_forest_plot.R \
  --samples <cache.rds> --arm-info /tmp/bnma_arm_info.rds \
  --study-info /tmp/bnma_study_info.rds --manifest <manifest.yaml> \
  --effect relative --out <output_folder>/forest_plot.png
```

The script prints the footnote text (contributing studies, source data
path(s), source program) it embedded in the plot — surface that back to the
user so they can confirm it's traceable, per the workflow doc's footnote
requirement. Save the plot into the matching dated `output/shared/YYYYMMDD_.../`
folder, not next to the manifest in `programs/`.

Every plotted treatment label carries a superscript marking its evidence
type — `°` for observed, `ᵖ` for projection, `°ᵖ` for an arm fed by both
(e.g. a shared placebo arm) — so a reviewer QC'ing the PNG can tell which
arms are real trial data vs. modeled without cross-referencing the manifest.
A one-line legend ("° = observed, ᵖ = projection") is appended to the
footnote automatically.

## Step 7 — Generate the driver script

Once the manifest-driven run is finished (BATMAN built, model fit, plot(s)
rendered) and the user is happy with the plot, write a thin driver script
into the same dated `programs/YYYYMMDD_.../` folder, e.g. `run_bnma_<slug>.R`,
that reproduces the run from scratch by calling this skill's own tested
scripts — not a flattened rewrite of their logic. Its header comments
should point at (not duplicate) the manifest, since that's where the actual
decisions and reasons live:

```r
#!/usr/bin/env Rscript
# Driver script for the <slug> BNMA run.
# Manifest (full decision record incl. route/evidence filters): <path to manifest.yaml>
# Source data: <prd path> [+ <qa path>]
# Re-running this script from scratch reproduces the same plot. The JAGS step
# will just reload the cached samples unless <cache.rds> is deleted (or
# --force is passed to fit_bnma_model.R, if this run used it).

skill_dir <- "<path to .claude/skills/bnma>"
# system2() joins `args` with spaces and runs it through the shell -- it does
# NOT shell-quote elements for you, so any arg containing a space (the plot
# --title, almost always) gets word-split by the shell into multiple argv
# tokens unless explicitly shQuote()'d. Confirmed by testing: an unquoted
# multi-word --title really did break argument parsing downstream --
# shQuote() every element, not just the ones that look risky.
sys2 <- function(command, args) system2(command, shQuote(args))

sys2(file.path(skill_dir, "scripts/run_r.sh"), c(
  file.path(skill_dir, "scripts/load_merge_data.R"),
  "--prd", "<prd_path.xlsx>", "--qa", "<qa_path.xlsx>", "--out", "<merged.rds>"
))
sys2(file.path(skill_dir, "scripts/run_r.sh"), c(
  file.path(skill_dir, "scripts/build_batman_data.R"),
  "--data", "<merged.rds>", "--manifest", "<manifest.yaml>",
  "--batman-out", "<batman.rds>", "--arm-info-out", "<arm_info.rds>",
  "--study-info-out", "<study_info.rds>"
))
sys2(file.path(skill_dir, "scripts/run_with_jags.sh"), c(
  file.path(skill_dir, "scripts/fit_bnma_model.R"),
  "--batman", "<batman.rds>", "--model", file.path(skill_dir, "model_simultaneous.txt"),
  "--cache", "<samples_<run_name>.rds>"
))
sys2(file.path(skill_dir, "scripts/run_r.sh"), c(
  file.path(skill_dir, "scripts/make_forest_plot.R"),
  "--samples", "<samples_<run_name>.rds>", "--arm-info", "<arm_info.rds>",
  "--study-info", "<study_info.rds>", "--manifest", "<manifest.yaml>",
  "--effect", "relative", "--out", "<forest_plot.png>", "--title", "<title>"
))
```

Fill in every `<...>` placeholder with this run's literal paths/args before
writing the file — it must be directly `Rscript run_bnma_<slug>.R`-runnable
with no further editing.

## Non-goals

- No fixed-effects model — heterogeneity is already handled by this model's
  `sigma`/`tau2` term.
- No external grounding (ClinicalTrials.gov/INN lookups) for the naming
  check — string-similarity + same-study disconfirmation + a persisted
  registry only.
- Does not touch `/home/l138303/BNMA` (an unrelated LLM-extraction/curation
  app project that happens to share the name).
