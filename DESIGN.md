# `/bnma` skill — design doc

## Background

From the July obesity/diabetes CI team meeting (led by Ran Liao), two problems
were raised that this skill addresses:

1. **Workflow documentation drift.** The written QA→PRD data-update workflow
   and analysis workflow are incomplete/out of date relative to the current
   data structure. Naming-convention changes have silently broken
   meta-analysis scripts, data prep is inconsistent (temporary datasets,
   no reliable cumulative QA trail), and existing guidance references a
   `/bnma` skill for "BATMAN augmentation, JAGS model, forest plots" that
   **does not actually exist** — confirmed by searching for it; only the
   name is referenced, twice, in the workflow docs.
2. **Manual study selection is error-prone.** A concrete incident: a low-dose
   Phase 2 study was silently included in a semaglutide analysis and skewed
   the result. Nothing forces an analyst to explicitly confirm which studies
   and treatment arms go into a network meta-analysis (NMA) — selection
   currently lives as a hardcoded, hand-edited exclusion vector inside each
   R script.

This doc scopes building the `/bnma` skill from scratch to close both gaps,
plus a data-quality feature requested separately: detecting near-duplicate
compound naming and route-of-administration pooling risk.

## Current state (what exists today)

The obesity landscape workflow lives on an SMB share (QA staging tier +
PRD cumulative tier, see the workspace's `GUIDE_README.md`), with one dated
`programs/`↔`output/shared/` folder pair per analysis. A representative
project (`20260811_monthly_obesity_landscape_GZMU_misc5`) contains:

- **`efficacy_bnma_v3_gzmu_misc5.R`** — loads the PRD Excel workbook's
  Observed + Prediction sheets, merges in a hand-built Brenipatide Phase 1
  dose-response addition, filters out a hardcoded list of Phase 2 studies,
  builds study/arm indices, does BATMAN phantom-placebo augmentation for
  studies missing a placebo arm, fits a JAGS random-effects NMA model, and
  produces a placebo-adjusted forest plot.
- **`efficacy_bnma_absolute_v3_gzmu_misc5.R`** — repeats the *exact same*
  data-loading/filtering code (must stay byte-identical to the first script
  so arm indices line up), loads the cached posterior instead of refitting,
  and plots absolute (non-placebo-adjusted) treatment effects.
- **`model_simultaneous.txt`** — the JAGS model: hierarchical study baselines
  (`phi[i] ~ dnorm(m, tau2_m)`), a random treatment effect per arm
  (`delta[i,j] ~ dnorm(..., tau2d[i,j])`) with a heterogeneity variance
  `sigma`/`tau2`, and a `mu_new` node for out-of-sample prediction.
- **`bnma-nonadj-11AUG2026.R`** — a newer iteration of the absolute-effect
  script. Notable as a live example of the exact problems above: comments
  read `# 🚨 changed in prd data?` next to study names the author wasn't
  sure still matched after a PRD naming change; a hardcoded
  `treatment[58] = "semaglutide 2.4mg qw"` row-index patch; an ad hoc
  `compound == "met-097"` → `"berobenatide"` rename.
- **`GIAE_NMA_code.R`** — a separate GI-adverse-event NMA (nausea, vomiting,
  etc.), using a frequentist approach (`netmeta`) instead of JAGS. Notable
  for this design doc only because it has a genuine fixed-vs-random-effect
  toggle (`common = FALSE, random = TRUE`) — **not needed here**: heterogeneity
  in the weight-loss model is already handled by the existing `sigma`/`tau2`
  term, so no new fixed-effect model is in scope.

**Known bugs this skill is designed to close**, all confirmed by reading the
actual code rather than assumed:
- Hardcoded `!study %in% c(...)` exclusion vectors — the literal mechanism
  behind the semaglutide Phase 2 incident.
- `arm_ind` is assigned via `unique(treat)` on the raw `treatment` string —
  two rows with an identical `treatment` string but different `aom` (route)
  *do* silently collapse into one treatment arm today.
- A stale project-level `CLAUDE.md` still instructs renaming the QA Excel
  file on every update; the corrected workflow doc fixed this to a stable
  filename + row-level `time_entry` stamp — a plausible root cause of
  "naming convention changes broke scripts."

## Goals

1. **Fix the stale workflow doc** (trim the drifted `CLAUDE.md` to a pointer
   at the canonical guide + project-specific content only, so it can't
   silently re-diverge).
2. **Build `/bnma`** as a real, reusable Claude Code skill that forces
   explicit decisions instead of running end-to-end on hardcoded vectors.

## `/bnma` skill design

Location: `.claude/skills/bnma/SKILL.md` + `scripts/` for anything that must
be deterministic code rather than LLM judgment (matching the existing
`extract-publication` skill's pattern of SKILL.md + `scripts/extract.py`).

### Step 1 — Load & merge data

QA + PRD per the workflow doc's fallback rule (try QA path, fall back to PRD
if the QA file has since moved/been promoted), merging in code. Reuses the
existing read/merge pattern already proven in `efficacy_bnma_v3_gzmu_misc5.R`.

### Step 2 — Naming/pooling QA gate (new)

Before any study selection, a deterministic R script
(`scripts/check_naming_pooling.R`, base R only — `adist()` for edit distance,
no new dependency) scans the merged data's distinct `compound`/`treatment`/
`aom` values.

**Near-duplicate compound detection.** There's no signal in a spreadsheet
that *proves* two spellings are the same real compound — this only surfaces
candidates for a human to confirm. Signals, in decreasing reliability:

1. **Substring/prefix containment** (e.g. `"canaflig"` contained in
   `"canafligizon"`) — the strongest signal; matches the actual failure mode
   of a dev code name drifting into a full INN name, or a truncated entry.
   Low false-positive rate.
2. **Normalized edit distance** (`adist(a,b) / max(nchar(a),nchar(b))`) as a
   weaker, separately-shown secondary tier — used carefully, because GLP-1/
   GIP-class drugs share suffixes systematically (`-glutide`, `-tide`,
   `-trutide`, `-gliflozin`), so raw edit distance alone would flag real,
   distinct compounds constantly.
3. **Disconfirming check**: if two similar-looking compound names ever
   appear as separate arms *within the same study*, that's strong evidence
   they're genuinely different compounds (a head-to-head comparison) —
   auto-suppress/downgrade the flag rather than re-litigate what the data
   already disambiguates.
4. **A persisted "known compounds" registry**, seeded from names already
   confirmed in the workflow doc's QC history, growing as a curator resolves
   each flag ("yes, merge" / "no, distinct") — so the same pair is never
   re-flagged on every future run. Without persistence this would nag
   forever.

No external grounding (no ClinicalTrials.gov/INN lookup) in this version —
that would be more reliable than string similarity but adds a network
dependency the current scripts don't have; explicitly out of scope for now.

**Route-pooling risk.** Mechanical, not fuzzy: group by `compound`; where
more than one distinct `aom` exists, flag (a) any exact `treatment` string
that appears under more than one `aom` — the literal bug mechanism, since
`arm_ind` comes from `unique(treat)` on that same string — and (b) compounds
with mixed/missing `aom` where the `treatment` label doesn't visibly encode
route.

Output is a report for human review; this never auto-edits data.

### Step 3 — Force explicit study/treatment-selection confirmation

List every distinct `study`/`treat`/`phase`/data-type (observed vs.
prediction) combination in the now-vetted data, flagging Phase 1/2 studies
and prediction rows. The user must explicitly include/exclude each flagged
group — no hardcoded/silent filtering, no assumed defaults. This is the
direct fix for the semaglutide-Phase-2 incident.

### Step 4 — Persist the decision

Write the confirmed selection (plus any naming/pooling resolutions) to a
manifest file (e.g. `study_selection_manifest.yaml`) alongside the dated
`programs/YYYYMMDD_.../` folder — a traceable, reviewable artifact instead of
a commented-out R vector, and most of what the workflow doc's footnote rule
already asks for.

### Step 5 — Run BATMAN → JAGS → forest plot

Reuses the existing `model_simultaneous.txt` model and existing R plotting
code, parameterized from the manifest instead of a hardcoded vector — no
rewrite of the statistics, no new fixed-effect model (heterogeneity is
already handled by the model's existing `sigma`/`tau2`).

### Step 6 — Auto-generate the footnote

Contributing studies + source program path, generated from the manifest.

## Non-goals

- **`/home/l138303/BNMA`** is an unrelated project (an LLM-based PDF
  extraction/curation Shiny app with its own DuckDB backend) that happens to
  share the "BNMA" name — explicitly out of scope, not touched by this work.
- Production polish: GUI, every filter type discussed in the meeting
  (sponsor filters, oral/injectable as UI toggles) — deferred until the core
  "force a decision" pattern is validated.
- A true fixed-effects NMA model — not needed; the concern was heterogeneity,
  which the existing random-effects model already estimates.

## Verification plan

- Confirm the trimmed workflow doc no longer contradicts the canonical guide
  anywhere (especially the file-renaming rule).
- Run `/bnma` end-to-end against the local misc5 files and confirm it: (a)
  surfaces at least one realistic naming/pooling flag against
  deliberately-seeded near-duplicate/route-collision rows, (b) lists every
  study/phase/data-type combination present in the real merged data, (c)
  refuses to proceed without explicit confirmation, (d) produces the same
  forest plot as the current script when given the same selection that
  script currently hardcodes, and (e) writes a manifest documenting both the
  naming/pooling resolutions and the study selection.
