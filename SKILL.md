---
name: cmh-ci
description: >
  Explore a Cardiometabolic Health QA/PRD dataset -- what studies,
  compounds, phases, and evidence tiers it contains -- and, when the goal
  is a full analysis, carry that same reviewed data through to a Bayesian
  network meta-analysis (BNMA) on any single continuous endpoint (weight
  loss, HbA1c, physical function, etc.), with forced study-selection
  confirmation and a naming/route pooling-risk QA gate instead of a
  hardcoded, hand-edited study list. Use this skill whenever the user wants
  to see what's in a PRD/QA dataset (studies, compounds, coverage) even with
  no analysis in mind, or wants to run, update, or refresh a BNMA forest
  plot from one, or mentions "/cmh-ci", "what's in this data", "what
  studies/compounds do we have", "run the BNMA", "run the meta-analysis",
  "BATMAN", "landscape forest plot", or "competitive intelligence deck
  figures". Every invocation opens with a landing page explaining the
  workflow before touching any data, file, or folder, and proceeds only on
  explicit confirmation.
---

# /cmh-ci

Guided workflow for the Cardiometabolic Health competitive-intelligence
QA/PRD dataset. Introducing and explaining what's actually in a PRD/QA
workbook -- studies, compounds, phases, evidence tiers -- is step 1 for
*everyone*, and a complete outcome on its own for someone who just wants to
know what's there; only when the goal is a full analysis does the same
reviewed data carry on through to the BNMA itself, generalized across
endpoints (weight loss, HbA1c, physical function, etc. -- see Step 2's
Endpoint question and Step 8's `effect_col`/`se_col` manifest fields).
Reuses the existing BATMAN-augmentation + JAGS + forest-plot pipeline (see
the misc5 project's R scripts for the reference implementation this was
built from), but replaces every place that pipeline made a silent,
hardcoded decision with an explicit step the user must confirm. See
`DESIGN.md` in this skill's repo (or the project's `GUIDE_README.md`) for
why each step exists.

**Run this in a terminal, with the statistician's own working directory of
their choice** (their own project folder under `programs/`/`output/shared/`,
per `GUIDE_README.md`'s Flow 2 convention — not necessarily this skill's own
repo checkout). Step 1 assumes exactly this: a folder that may already have
PRD/QA data sitting in it, not a bare/empty directory.

**Canonical reference for MCMC settings and model behavior:**
`EliLillyCo/CMH.BNMA` (the real production Shiny app this skill's pipeline
is meant to match) — provided in full, 2026-08-20. Where this skill's own
prior settings conflicted with that package's actual documented/coded
behavior, this skill was corrected to match it (see Step 10's MCMC settings
and the single-arm-study/`pbo`-alias notes below); `BNMA_forest_plot-main.zip`
(confirmed 2026-08-17) remains the source for the JAGS model files
themselves, which CMH.BNMA's own model files match verbatim.

**Workflow at a glance** (see DESIGN.md's design-iteration history for why
this order is enforced): introduce the data before asking for decisions,
force study selection before any analysis, don't drag someone toward
folders/manifests/custom-data talk just because they located a file, and
don't collect modelling preferences until the real dataset — and its
network structure — is actually known.

```
Landing page  Explain the workflow end-to-end, ask to proceed
Step 1  Introduce the PRD dataset, list studies, ask which to include
Step 2  Ask whether additional, non-PRD data should be incorporated
        (including a link/publication extraction pathway)
Step 3  Convert and structure any additional data into the QA format
        (only if Step 2 said yes)
Step 4  Merge the supplemental data into QA and re-load
        (only if Step 2 said yes)
Step 5  Confirm ready to run BNMA, create folders, write manifest
Step 6  Collect modelling preferences (random/fixed, route, evidence)
Step 7  Produce analysis outputs (relative + absolute forest plots,
        RMD report)
```

**Do not skip steps or assume defaults on the user's behalf on anything
genuinely discretionary.** The whole point of this skill is that a low-dose
Phase 2 study or an oral/injectable mix-up must never enter a model silently
again. The landing page explains the workflow and asks to proceed before
touching anything. Step 1 lists studies and asks which to include. Step 2
asks about new data. Step 5 asks whether to actually run a BNMA. Step 6
collects design decisions (random/fixed). Only then does Step 7 fit the
model and produce both plots plus the RMD report.

## Landing page — shown before anything is touched

Every `/cmh-ci` invocation opens here, before any search, read,
`run_bnma_pipeline.R` call, manifest write, or `compound_registry.yaml`
access. **Print the block below verbatim — do not paraphrase, regenerate,
reorder, or restyle it.** It is fixed text so the page reads identically
on every run, for every user; the point is a stable operator banner, not
a fresh description each session — a paraphrased banner is exactly how a
stale claim (like a dropped question the page still promised) survives
unnoticed across runs.

```
════════════════════════════════════════════════════════════════════

                          /cmh-ci
        Bayesian Network Meta-Analysis · CMH Competitive Intelligence

════════════════════════════════════════════════════════════════════

From the PRD/QA weight-loss dataset to a fitted BNMA. This skill reads
the data, has you select studies and settle any conflicts, folds in any
outside data you supply, fits the model, and returns both forest plots
(placebo-adjusted and absolute), a per-run report, and a standalone
re-runnable script.

It runs in steps. Each step needs one decision from you — nothing is
assumed silently.

    1 ─ Read the PRD/QA data; list every study, compound, phase, and
        evidence tier.
    2 ─ You pick the studies and compounds to include.
    3 ─ Phase, route, and compound are stated plainly with your
        selection; a genuine overlap or naming inconsistency still
        gets its own call-out.
    4 ─ You say whether outside data (press release, publication link,
        digitized slide, another workbook) goes in.
    5 ─ Any outside data is mapped to the QA schema and merged — you
        confirm the rows.
    6 ─ You choose random- or fixed-effects.
    7 ─ Fit, then output both forest plots, the report, and a
        standalone re-runnable script.

Stopping after any step is a valid outcome — reviewing or updating the
data without fitting is a complete session.

────────────────────────────────────────────────────────────────────
  Shall I read the PRD dataset and list the studies?   ( yes / no )
────────────────────────────────────────────────────────────────────
```

- **Explicit yes** ("yes," "let's proceed," etc.) → proceed directly into
  Step 1.
- **"No" or anything non-affirmative/ambiguous** → end the turn without
  touching anything. Nothing carries over from this page, since nothing
  was touched.

Operator notes (not printed on the page above):
- Deeper "why" for any step — the incident history behind it — lives in
  `DESIGN.md` in this skill's repo (or the project's `GUIDE_README.md`),
  not here.
- **One thing still interrupts downstream of this page: a hard gate
  failure** — `run_bnma_pipeline.R` refusing to run because a study is
  missing from the manifest. Continuing silently past it defeats the
  skill's purpose, not just its UX.
- **No automated post-fit diagnostics are run** (no Rhat/ESS,
  network-connectivity/consistency/DIC) — matches the production
  `EliLillyCo/CMH.BNMA` app's own behavior (confirmed 2026-08-24: it fits
  and plots with no such checks). To verify a fit, inspect the posterior
  manually (`coda::gelman.diag()`, `coda::effectiveSize()` on the cached
  `samples.rds`) rather than expecting this skill to flag it.


## Step 1 — Introduce and explain the available PRD dataset

**The PRD dataset lives at:**
```
/lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_YYYYMMDD.xlsx
```

**Locate the most recent dated file matching that pattern first** — one
cheap `ls`, not a search — rather than assuming a fixed date. New dated
PRD extracts land in that directory periodically; treating a specific
date as permanent (or, worse, improvising an ad hoc check for whether
it's still current) is exactly the kind of slow, unscoped work this step
should avoid. Resolve it in the same command that reads the file, no
separate step:

```bash
module load R/4.4.2 2>/dev/null
export PRD_FILE=$(ls -t /lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_*.xlsx 2>/dev/null | head -1)
echo "Using PRD file: $PRD_FILE"
Rscript -e '
library(readxl); library(dplyr)
f <- Sys.getenv("PRD_FILE")
sheets <- excel_sheets(f)
for (s in sheets[!tolower(sheets) %in% c("summary","revision history")]) {
  d <- read_excel(f, sheet=s)
  if ("study_name" %in% names(d)) {
    cat("\nSheet:", s, "| Rows:", nrow(d), "\n")
    studies <- d %>% group_by(study_name) %>%
      summarise(compounds = paste(sort(unique(compound)), collapse=", "),
                treatments = paste(sort(unique(treatment)), collapse="; "),
                phase = first(phase),
                routes = paste(sort(unique(na.omit(aom))), collapse="/"),
                .groups="drop")
    for (i in seq_len(nrow(studies))) {
      route_str <- if (nzchar(studies$routes[i])) paste0(", ", studies$routes[i]) else ""
      cat("  ", i, ". ", studies$study_name[i],
          " (", studies$phase[i], route_str, ", ", tolower(s), ")",
          " -- ", studies$compounds[i], "\n", sep="")
      cat("       ", studies$treatments[i], "\n")
    }
  }
}
'
```

Present the output to the user showing **all studies from both sheets**
(Observed and Prediction), then ask:

```
Here's what's in the PRD (cwm_wl_nont2d):

  OBSERVED (N studies):
    1. <study_name> (<phase>, <route>) — <compound>: <treatments>
    2. ...

  PREDICTION (M studies):
    1. <study_name> (<phase>, <route>) — <compound>: <treatments>
    2. ...

  Which studies do you want to include?
```

**Both sheets get the identical per-study numbered format** — `N. <study_name>
(<phase>, <route>) — <compound>: <treatments>`, one line per study. Never
collapse the Prediction list into a summary paragraph (a compound-name
roundup like "includes amycretin, cagrilintide, ...") just because it's
the second sheet — a Prediction study is exactly as eligible for selection
as an Observed one, and hiding its phase/treatments behind a name-only
mention makes it too easy to pick the wrong study by accident.

If the user already named specific treatments/studies in their prompt,
pre-resolve those and propose them as the include list.

**Once the user picks studies, echo the confirmed selection in this same
format** — phase, route, and compound stated plainly per study, right in
the confirmation itself, not as a separate question. Mixing routes (oral
+ injectable) or phases across the selection is a legitimate modeling
choice, not something to gate on — an oral/injectable combined analysis
is a completely normal thing to want. State what's in the selection;
don't ask permission for it. The same goes for compound naming: if it's
spelled consistently, this line already shows that — there's no separate
naming/route round-trip needed for the routine case, and skipping it is
real time saved over the course of a session.

This is different from a genuine anomaly that a phase/route/compound line
wouldn't surface on its own — e.g. two selected studies that are actually
the same underlying trial at different follow-up points (a base study and
its extension), or a literal spelling inconsistency where what should be
one compound is written two different ways across rows. Those are actual
data problems, not a modeling choice, and still deserve their own explicit
call-out and confirmation before proceeding.

## Step 2 — Ask whether additional, non-PRD data should be incorporated

Once the user confirms which studies they want, ask:

```
Do you have any additional data to add before fitting?
(e.g. a press release, new readout, hand-digitized data, another workbook,
or a link to a publication)
```

If **no** → proceed to Step 5.

If **yes** → go to Step 3.

## Step 3 — Convert and structure any additional data into the expected QA format

Get the new data in any form:
- Pasted rows in the prompt
- A file path (xlsx, csv)
- "Take X from file Y" — read and filter
- **A link attached in chat** (publication, press release, or other web
  source) — see "Link/publication extraction pathway" below.

Map it into the QA schema (canonical column list in the table below).
Fill what's known from context — mainly baseline values; `source` is the
link/file/reference the user provided to extract from; `curator_note` is
`AI extraction` whenever the AI did the extraction (link/pdf/ppt/etc.).
Leave undecided fields blank rather than guessing.

**Show the mapped row(s) back as the schema itself — horizontally, columns
across and one row per arm — with undecided cells (SE and the rest) shown
blank, so the statistician sees exactly which fields are still theirs to
fill.** Display the core columns below; if the schema is wider than fits,
split into two aligned horizontal tables (identity+efficacy, then
provenance) — never pivot to a vertical key/value dump.

```
Extracted from <source> — mapped to QA schema (Observed/Prediction TBD).
Blank cells are still yours to decide.

| study_name | treatment | compound | phase | n | pchg_wl_ee | se_wl_ee | baseline_wgt | study_duration | population | route | source | data_type | curator_note |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ...        | ...       | ...      | ...   |...|    ...     |          |     ...      |      ...       |    ...    |       | <link> | publication| AI extraction|

(+ N optional schema fields — qc_name, qc_note, derivation_spec, … —
written to the workbook blank; not shown here.)
```

This is a **display** projection. The **insert** (what
`append_to_qa.R` writes to the workbook) always carries the full column
set below, blanks as NA — nothing persisted is dropped just because the
display was trimmed.

### Link/publication extraction pathway

When the user attaches a link instead of pasting rows or pointing at a
file:

1. Fetch/extract the study data directly from that source — generic, not
   publication-specific (works the same for a publication, press release,
   or any other web source). A single link often covers more than one
   study or arm (e.g. a press release bundling two trial readouts) —
   extract all of them, not just the one study the user named.
2. **Flag any population/scope mismatch explicitly, per study extracted —
   don't fold it quietly into `curator_note` and move on.** Check each
   extracted study's population against this dataset's scope (e.g. T2D
   vs. non-T2D for `cwm_wl_nont2d`) before mapping anything. If a study
   is out of scope, call it out on its own line (e.g. "TRIUMPH-2 is a T2D
   population — out of scope for this non-T2D dataset, excluding it") and
   confirm the exclusion with the user, the same way Step 1's
   naming/route conflicts get a grouped confirmation rather than a silent
   decision. Only studies confirmed in-scope proceed to mapping.
3. **Ask the user whether the extracted data is observed or predicted —
   never infer this.** The answer sets the destination QA sheet
   (`Observed` vs `Prediction`, matching `append_to_qa.R`'s `--sheet`
   argument) and feeds `analysis_method`/`derivation_spec`.
4. Map the extracted fields into the QA column schema. **This is the
   canonical, full column set — the insert writes all of it; the display
   above shows the ★-marked core subset.**

   | Column | Meaning |
   |---|---|
   | `time_entry` | date this row is entered — **always today's run date (`yyyymmdd`), auto-filled, never asked.** It records when the row was curated, not a "data as of" date from the source — don't confuse the two, and don't prompt the user for it. |
   | ★ `study_name` | study identifier |
   | ★ `treatment` | arm label, e.g. `tirzepatide 15mg` |
   | ★ `compound` | compound/molecule name |
   | ★ `phase` | trial phase; for Prediction rows, the phase it's *from* |
   | ★ `n` | arm sample size |
   | ★ `pchg_wl_ee` | % weight change, efficacy estimand (non-pbo adj) |
   | ★ `se_wl_ee` | SE of `pchg_wl_ee` |
   | ★ `baseline_wgt` | baseline body weight |
   | ★ `study_duration` | study/analysis duration, e.g. `68 week` |
   | ★ `population` | population, e.g. `obese non-t2d, background therapy` |
   | ★ `route` | `Oral` vs `Injectable` |
   | ★ `source` | citation/URL — the exact link provided |
   | ★ `data_type` | source type — `publication` for this pathway |
   | ★ `curator_note` | `AI extraction` when the AI extracted the row |
   | `sponsor` | study sponsor, e.g. `lilly` |
   | `pchg_wl_tre` | % weight change, treatment-regimen estimand (non-pbo adj) |
   | `se_wl_tre` | SE of `pchg_wl_tre` |
   | `analysis_method` | method, e.g. `mmrm` on treatment; Prediction method |
   | `curator_name` | curator name once curation is done |
   | `qc_name` / `qc_note` | QC name/comments once QC is done |
   | `derivation_spec` | formula/method when a value is derived |

   For Prediction rows, `source` is the source-program location for
   deriving the value. Match column names/casing to whatever the live QA
   workbook actually uses at read time (it also carries an `aom`
   route-family column and split `observed`/`prediction` tabs) rather than
   hardcoding — this full table is the authoritative field set to populate.

5. **Mandatory fields — never leave blank/skipped without flagging it:**
   SE (`se_wl_ee`/`se_wl_tre` as applicable — if not directly reported and
   must be derived, record the method in `derivation_spec`),
   `study_duration`, `sponsor`, `baseline_wgt`, `population`, and `source`
   (the exact link provided). If any of these can't be determined from
   the source, flag it to the user explicitly and ask them to supply
   it — never guess or leave it silently blank. The same goes for
   anything else inferred rather than directly stated (e.g. dosing
   frequency, per-arm `n` derived from a randomization ratio) — surface
   the assumption and ask, don't bury it in
   `derivation_spec`/`curator_note` as the only record of it.
   `time_entry` is **not** part of this ask-if-ambiguous list — it's
   always just today's date, filled in automatically (see the schema
   table above).
6. Show the mapped row(s) for confirmation — same table-confirmation
   pattern as any other source in this step — then follow Step 2's
   existing merge question. This pathway feeds the same merge decision;
   it doesn't bypass it.

## Step 4 — Merge the supplemental data with the selected PRD subset

Once confirmed, target the **existing** QA file rather than assuming a
fixed filename: find the most recent dated file matching

```
/lillyce/qa/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_qa_YYYYMMDD.xlsx
```

in that directory (convention: swap `/prd/` → `/qa/` and `_prd_` →
`_qa_` in the filename).

If **no** file matching that pattern exists at all, confirm with the
user before creating one — never create silently. Only once confirmed,
create it directly (PRD schema, Observed/Prediction sheets) via
`append_to_qa.R`'s `--create-from` fallback.

Append using `append_to_qa.R`, targeting the located file. If the scripts
haven't been materialized yet this session, run Appendix B's extraction
command first (it writes both scripts to `/tmp/$(whoami)/cmh_ci_lib/` in
one pass — never retype them):
```bash
module load R/4.4.2 2>/dev/null
Rscript /tmp/$(whoami)/cmh_ci_lib/append_to_qa.R \
  --qa <located_qa_path.xlsx> --sheet <Observed|Prediction> \
  --rows /tmp/new_rows.rds
```

Only pass `--create-from <prd_path.xlsx>` in the rare case above (no
existing QA file found, and the user confirmed creating a new one) —
`--create-from` stays in the script as a fallback, it just isn't this
step's default path anymore.

**A located QA file's target sheet is often genuinely empty (0 rows)** —
a freshly created workbook, or a sheet nobody has populated yet. That's
a normal case to append into, not a sign something's wrong; `append_to_qa.R`
handles it (see Appendix B2's 2026-08-27 fix).

**Don't check whether a study is already in QA before appending, and
don't delete an old entry to replace it.** A study confirmed for this
run gets appended as new rows regardless of whether an earlier run
already added something for it — `run_bnma_pipeline.R`'s load+merge step
resolves any resulting duplicate (same `study_name`+`treatment`) by
keeping whichever row has the latest `time_entry`, so this run's own
entry always wins without anyone needing to edit or delete QA history.

Show the append (or create) summary. No separate reload is needed here —
Step 7's `run_bnma_pipeline.R` always loads PRD + QA fresh, so the new
rows are picked up automatically the next time it runs.

Loop back to Step 2 ("anything else to add?") until the user says the
subset is sufficient.

## Step 5 — Generate the BNMA using the prepared dataset

Once the subset is confirmed (with or without additional data), ask:

```
Ready to run a BNMA on this subset? (Y/n)
```

If **no** → end here (the session was just about reviewing/updating data).

If **yes** → create working folders and write the manifest:

**Output paths (hardcoded base):**
- Programs: `/lillyce/qa/diabetes/bnma/obesity/programs/YYYYMMDD_<slug>/`
- Outputs: `/lillyce/qa/diabetes/bnma/obesity/output/shared/YYYYMMDD_<slug>/`

Derive `<slug>` from the endpoint/scope (e.g. `cwm_wl_nont2d`,
`wl_oral_only`). Create both folders.

**Getting the complete study list — reuse the pipeline's own gate, don't
hand-roll a fresh merge script.** Every study in the merged PRD+QA data
needs an explicit `include: true/false`, but there's no need to write a
separate `bind_rows()`/dedup script to enumerate them — that re-implements
load+merge logic the extracted `run_bnma_pipeline.R` already has (correct
stringification, correct QA-vs-PRD and within-QA dedup), and a hand-rolled
version risks re-hitting exactly the type-mismatch bugs already fixed
there (e.g. binding a character column against a numeric one across
sheets). Instead:

1. Write `study_selection_manifest.yaml` to
   `/tmp/$(whoami)/cmh_ci_lib/study_selection_manifest.yaml` with just the
   studies already confirmed (Step 1/3) as `studies:` entries.
2. Run the extracted `run_bnma_pipeline.R` once against that manifest,
   with no `--plot`/`--cache`/`--fit-placebo` — it exits at the BUILD
   stage, before any JAGS compile or MCMC, so this is fast:
   ```bash
   module load R/4.4.2 jags 2>/dev/null
   Rscript /tmp/$(whoami)/cmh_ci_lib/run_bnma_pipeline.R \
     --prd <prd_path.xlsx> --qa <qa_path.xlsx> \
     --manifest /tmp/$(whoami)/cmh_ci_lib/study_selection_manifest.yaml \
     --model model_random.txt
   ```
3. It fails with `Manifest is missing an explicit include/exclude decision
   for N study/ies: <full list>` — that list is the authoritative,
   already-deduped remainder. Add all of them to the manifest with
   `include: false`, then proceed.

No separate duplicate-checking pass between QA and PRD is needed either —
the merge step inside the pipeline already handles that (QA overrides PRD
on a matching `study_name`+`treatment` key).

Every study in the data must appear with an explicit `include: true/false`;
`run_bnma_pipeline.R`'s missing-decision gate is what enforces that (see
above). What's different from earlier in this skill's history is
persistence: the manifest itself is no longer a kept deliverable — Step
7's RMD report is, and it names only the studies that were actually
included rather than dumping the full true/false list (see Step 7).

## Step 6 — Collect modelling preferences

Ask the design decision — **no model-fitting preview at this stage:**

```
Model specification:
  Heterogeneity  ► random-effects (rand_effect) [default]
                   or fixed-effect?
```

**(Region, Route, and Evidence questions are dropped entirely — not
asked. `route_filter` and `evidence_filter` are never set by the user
here and stay at their manifest default of `"both"`.)**

**Effect (relative vs. absolute) is not asked here** — Step 7 always
produces both, so there's nothing to choose.

Default proceeds unless the user says otherwise. Once confirmed, update
the manifest with `model_type`.

**This decision is final.** Once the user answers Heterogeneity here,
don't re-ask, and don't re-litigate it later — whatever they pick is
used as-is, with no post-hoc network-based recommendation.

## Step 7 — Produce analysis outputs and visualisations

**This is where the script is first materialized (if Step 4 didn't
already).** Extract Appendix B's `run_bnma_pipeline.R` to
`/tmp/$(whoami)/cmh_ci_lib/run_bnma_pipeline.R` using **Appendix B's
extraction command — never retype the script text.**
It is the only script this step needs — load+merge, build BATMAN, fit the
JAGS model, fit the pooled-placebo model, and render **both** forest plots
happen in **one invocation of one R script, in one R process**
(`--effect both`); there is no separate plotting script, no second
invocation to re-plot from cache, and no shell wrapper: `module load` runs
inline in the command below.

Model file selection:
- `rand_effect` → `model_random.txt`
- `fixed_effect` → `model_fixed.txt`
- `simultaneous` → `model_simultaneous.txt`
- `simultaneous_fixed` → `model_simultaneous_fixed.txt`

MCMC: n.adapt=10000, burn-in=10000, 20000 iterations thinned by 10, 3 chains.

**Every run always produces both effect plots — this is not a user
choice (see Step 6).** `--effect both` renders the relative and the
absolute plot from the same process and the same fit: the JAGS model is
fit once, the pooled-placebo model is fit once (for the absolute plot's
baseline), and both PNGs are saved before the process exits — no second
R startup, package load, Excel re-read, or BATMAN rebuild between them.

```bash
module load R/4.4.2 jags 2>/dev/null
Rscript /tmp/$(whoami)/cmh_ci_lib/run_bnma_pipeline.R \
  --prd <prd_path.xlsx> [--qa <qa_path.xlsx>] \
  --manifest <manifest.yaml> --model <model_file> \
  --cache /tmp/$(whoami)/cmh_ci_lib/samples.rds \
  --fit-placebo --placebo-cache /tmp/$(whoami)/cmh_ci_lib/placebo_samples.rds \
  --plot --effect both \
  --plot-out <output_folder>/forest_plot_relative.png \
  --plot-out-absolute <output_folder>/forest_plot_absolute.png
```

(For an ad hoc single-plot re-render later in a session, `--effect
relative` or `--effect absolute` with one `--plot-out` still works and
reuses `--cache`, so nothing refits.)

`--cache`/`--placebo-cache` point at the same `/tmp` scratch dir the script
itself is materialized into — never the programs folder. They only exist to
let a `--contrast` follow-up or a re-plot skip re-running MCMC within the
same session; they are not part of the audit trail (the script + RMD
report are what make the run reproducible, not the raw posterior draws)
and must not be copied into `programs/YYYYMMDD_<slug>/`.

**Display both plots** (Read tool) immediately.

**Then write the per-run RMD report** — see "RMD report" below.

Save outputs:
- Both forest plots →
  `/lillyce/qa/diabetes/bnma/obesity/output/shared/YYYYMMDD_<slug>/forest_plot_relative.png`
  and `.../forest_plot_absolute.png`
- **A copy of the exact `run_bnma_pipeline.R` used for the fit** →
  `/lillyce/qa/diabetes/bnma/obesity/programs/YYYYMMDD_<slug>/run_bnma_pipeline.R`
  (copy, don't move, from the `/tmp/$(whoami)/cmh_ci_lib/` materialization —
  the `/tmp` copy is scratch and may not survive the session; the programs
  folder is the permanent audit trail. Without this copy, reproducing the
  run depends on this chat session still existing.) Copy it after both
  fits succeed, e.g. `cp /tmp/$(whoami)/cmh_ci_lib/run_bnma_pipeline.R
  <programs_folder>/run_bnma_pipeline.R`.
- **The per-run RMD report** →
  `/lillyce/qa/diabetes/bnma/obesity/programs/YYYYMMDD_<slug>/report.Rmd`
  — this is the permanent audit trail now, not the manifest (see below).

The programs folder holds **only the script and the RMD report** — no
`study_selection_manifest.yaml`, and no `samples.rds`/`placebo_samples.rds`
either. The manifest stays in `/tmp` scratch
(`/tmp/$(whoami)/cmh_ci_lib/study_selection_manifest.yaml`, written in
Step 5) — `run_bnma_pipeline.R` still needs it as an input, and its
missing-decision gate still forces an explicit `true`/`false` for every
study, but the manifest itself is no longer kept as a deliverable; its
substance carries forward into the RMD report instead, which is what
actually persists in the programs folder.

### RMD report

Generate a fresh `report.Rmd` every run (never accumulated across runs),
written to the same run's programs folder alongside the script. Pull its
content from the manifest written in Step 5/6 rather than re-deriving
anything, but **summarize, don't dump**:

- **Studies included** — just the studies with `include: true` (e.g.
  "scale maintenance, believe, zupreme-1, triumph-3"). Don't enumerate the
  `false` ones — the manifest already made that decision explicit at fit
  time; the report doesn't need to repeat it study by study.
- The design choices made this run: `model_type` (random vs. fixed
  effects), `route_filter`, `evidence_filter`, and any supplemental data
  merged in via Step 2/3 — including the observed-vs-predicted
  determination for anything pulled in via the link/publication pathway.
- The scripts used to produce the two plots (the copied
  `run_bnma_pipeline.R` path, and each invocation's arguments).
- Links to the two output plots (relative-effect and absolute-effect) in
  this run's output folder.

## What this skill does NOT do

- No `/cmh-ci-explain` command — the landing page is shown on every
  `/cmh-ci` invocation instead
- No region, route, or evidence questions (dropped — always "both")
- No relative-vs-absolute question (Step 6) — every run always produces
  both plots, in one invocation (Step 7's `--effect both`)
- No model-fitting preview before design decisions
- No re-asking Step 6's `model_type` choice once made, and no post-hoc
  network-based recommendation for it either — the statistician's answer
  is used as-is
- No `study_selection_manifest.yaml`, `samples.rds`, or
  `placebo_samples.rds` in the programs folder — the manifest and MCMC
  caches all stay in `/tmp` scratch; only the script + RMD report persist
  there, and the report summarizes just the included studies, not a full
  true/false dump
- No automated post-fit diagnostics (matches EliLillyCo/CMH.BNMA)
- No placebo QC plot (removed — only the two forest plots are produced)
- No compound_registry.yaml persistence
- No Project CLAUDE.md generation

---

## Appendix A — JAGS Models (reference documentation)

This appendix documents the model definitions this skill uses. **It is
reference documentation only, not something a step instructs you to
materialize** — the single operative copy of every model lives inside
Appendix B1's `run_bnma_pipeline.R` (`MODEL_TEXTS`, built by
`make_network_model()`), passed to `jags.model()` via `textConnection()`
at fit time, so no `model_*.txt` file is ever written to disk during a
session. The model text is deliberately **not** repeated here as code
blocks: a second verbatim copy previously lived in this appendix and had
already drifted in formatting from the operative one — one source of
truth, described here, defined in B1. In the team's own separate driver
script (not part of this skill's numbered steps), the model text is still
written inline via `cat('...', file = model_path)`, matching the team's
existing convention for a script meant to run outside any Claude session.

### The five models, and how they relate

The four network models are compositions along exactly two axes, and B1's
`make_network_model(pooled_baseline, fixed_delta)` builds each one from a
single shared likelihood body plus those two toggles — so the shared
structure (arm likelihood, `eta`, the `w`/`sw` multi-arm correction,
`Dbar`, the `d[k]` priors, `sigma`/`tau2`) is written exactly once and
cannot drift between variants:

| `--model` name | Baseline `phi[i]` | `delta[i,j]` | Use for |
|---|---|---|---|
| `model_random.txt` (A1, **DEFAULT**) | flat `dnorm(0, 1e-4)` | stochastic (random-effects) | placebo-adjusted forest — the standard deliverable; production default |
| `model_fixed.txt` (A2) | flat `dnorm(0, 1e-4)` | deterministic (fixed-effect) | star networks where sigma can't be estimated, or as sensitivity check |
| `model_simultaneous.txt` (A3) | pooled `dnorm(m, tau2_m)` + `mu_new` | stochastic (random-effects) | absolute-effect forest (`m + d[k]`) |
| `model_simultaneous_fixed.txt` (A4) | pooled `dnorm(m, tau2_m)` + `mu_new` | deterministic (fixed-effect) | absolute-effect forest on a full-star network — the pooled baseline is still needed for the absolute effect, but a star network's CIs should track the arms' own reported SE, not an unreplicated, prior-driven `sigma` |

The only structural differences the toggles introduce: `pooled_baseline`
swaps the flat `phi` prior for the hierarchical `phi[i] ~ dnorm(m, tau2_m)`
block (with `m`, `sigma_m`) and appends `mu_new ~ dnorm(m, 1/sigma_m^2)`;
`fixed_delta` swaps the stochastic `delta[i,j] ~ dnorm(...)` line for the
deterministic `delta[i,j] <- ...` one. The fixed-delta variants keep the
(dead-but-present) `sigma`/`tau2` declarations for structural symmetry,
exactly as the original standalone `model_fixed.txt` did. A4 was never
present as a standalone file before — every place that referenced it
described the composition (A3's baseline + A2's delta) without spelling
out the resulting text; with the template, that composition is now
guaranteed by construction rather than hand-assembled.

**A5. Pooled-placebo meta-analysis (`model_placebo_random.txt`)** stands
apart — a simple random-effects meta-analysis of the placebo arms alone
(`y_pct[i] ~ dnorm(mu[study_idx[i]], ...)`, `mu[i] ~ dnorm(m, ...)`,
`mu_new` for a new study's predicted placebo). Used for the absolute-effect
plot's baseline. Its text is a standalone string in `MODEL_TEXTS`, not
template-generated.

To read any model's exact assembled text, open B1's `run_bnma_pipeline.R`:
`NETWORK_MODEL_BODY` + `make_network_model()` + `MODEL_TEXTS` sit together
near the top, immediately after the shared helpers.

---


## Appendix B — R Scripts (embedded, no external files needed)

These are the exact, tested scripts this skill's pipeline runs, embedded
in this SKILL.md so the skill remains a single self-contained file.

**Materializing them: extract, never retype.** This SKILL.md itself is on
disk in the session — it *is* the reference copy — so the scripts are
pulled out of it mechanically rather than regenerated line by line
(retyping ~1,100 lines of R costs minutes of generation time per session
and risks transcription errors; extraction is byte-exact and takes under
a second). Run this once, at the first step that needs a script (Step 4's
append, or Step 7's fit — whichever comes first):

```bash
module load R/4.4.2 2>/dev/null
Rscript -e '
skill_md <- "<path this SKILL.md was loaded from>"  # the skill file itself
src   <- readLines(skill_md, warn = FALSE)
fence <- strrep("\x60", 3)                          # three backticks
starts <- grep(paste0("^", fence, "r$"), src)
ends   <- grep(paste0("^", fence, "$"), src)
lib <- file.path("/tmp", Sys.info()[["user"]], "cmh_ci_lib")
dir.create(lib, recursive = TRUE, showWarnings = FALSE)
for (s in starts) {
  e <- ends[ends > s][1]
  b <- src[(s + 1):(e - 1)]
  name <- if (any(grepl("/cmh-ci pipeline:", head(b, 5)))) "run_bnma_pipeline.R"
    else if (any(grepl("Step 4 of the /cmh-ci skill", head(b, 5)))) "append_to_qa.R"
    else next
  stopifnot(grepl("cmh-ci embedded script end", tail(b, 1)))  # complete block?
  writeLines(b, file.path(lib, name))
  cat("Extracted", name, "--", length(b), "lines\n")
}
'
```

Fill in `skill_md` with the actual path this SKILL.md was loaded from (the
skill's own location on disk — shown when the skill is invoked; if in
doubt, locate it, e.g. `find ~/.claude -path "*cmh-ci*" -name SKILL.md`).
Each script's last line is a sentinel comment
(`# [cmh-ci embedded script end: <name>]`), so the `stopifnot` catches a
truncated or mispaired code fence at extraction time instead of at fit
time. Both scripts land in `/tmp/$(whoami)/cmh_ci_lib/` in one pass.
Only if the SKILL.md genuinely cannot be located on disk, fall back to
writing the script text out via a heredoc — as a last resort, not the
default.

**One script covers the entire modeling/plotting pipeline** — B1
`run_bnma_pipeline.R`: load+merge → build BATMAN → fit the JAGS model →
optionally fit the pooled-placebo model → render the forest plot, all in
a single R process, no mode-switching. This replaces what used to be nine
separate files (`lib_common.R`, `load_merge_data.R`,
`check_naming_pooling.R`, `build_batman_data.R`, `fit_bnma_model.R`,
`fit_pooled_placebo_model.R`, `make_forest_plot.R`,
`make_placebo_forest_plot.R`, `named_contrast.R`), then an intermediate
two-script/three-mode consolidation that still paid for a second R
startup + package load between fitting and plotting. That intermediate
step is gone too: the separate "explore" and "build-preview" modes are
removed outright — they were dead weight against the actual Steps 1-7
flow, which already does its own data exploration with inline R (Step 1)
rather than by shelling out to this script — and plotting is folded into
the same process as fitting via a `--plot` flag instead of a second
script invocation. The placebo QC plot (`--qc-plot`, formerly
`make_placebo_forest_plot.R`) is dropped entirely — this skill produces
exactly the two forest plots (relative and absolute), rendered together
in one invocation via `--effect both`, and nothing else. The five
embedded JAGS model definitions (Appendix A) live inside
`run_bnma_pipeline.R` itself — the four network models are generated from
one shared body by `make_network_model()`'s two toggles rather than
maintained as four near-identical strings, and the pooled-placebo model
is a standalone string — all passed to `jags.model()` via
`textConnection()`. There's no separate "materialize `model_random.txt`
to a file first" step; Appendix A is reference documentation only, not
something a step instructs you to write to disk.

`append_to_qa.R` (B2) stays its own small file — it's Step 4's rare
promote-to-QA path, not part of the modeling/plotting hot path, and mixing
a shared-Excel-file write into the consolidated script would tangle
unrelated concerns for a rarely-invoked feature.

### B1. `run_bnma_pipeline.R`

One mode: `--manifest` and `--model` are both required. The script always
does the same four things in the same process, in order — load+merge PRD/QA
→ build the BATMAN matrices (manifest fields, phantom-placebo handling)
→ fit the JAGS model (optionally the
pooled-placebo sub-model too, via `--fit-placebo`) → render the forest
plot(s) (`--plot`; `--effect both` with `--plot-out` +
`--plot-out-absolute` renders relative and absolute in this same pass —
Step 7's default — while `--effect relative|absolute` with one
`--plot-out` renders a single plot; `--contrast "a|||b"` prints a named
posterior contrast instead and skips plotting). No `run_r.sh`/
`run_with_jags.sh` wrappers — `module load R jags` runs inline before the
one `Rscript` invocation (see Step 7).

```r
#!/usr/bin/env Rscript
# /cmh-ci pipeline: load+merge -> build BATMAN -> fit JAGS model [-> fit
# pooled-placebo model] -> render forest plot. One file, one mode -- no
# explore/build-preview modes (dead weight against the actual Steps 1-7
# flow, which already explores via inline R at Step 1 -- see SKILL.md's
# Appendix B intro) and no separate plotting script (the forest plot
# renders in this same process via --plot, removing a second R-startup +
# package-load between fit and plot). The placebo QC plot is gone
# entirely -- this script produces exactly the two forest plots.
#
# Usage (single invocation, everything in one process -- Step 7's default,
# which fits the JAGS model once and renders BOTH forest plots):
#   Rscript run_bnma_pipeline.R --prd <p> [--qa <q>] --manifest <m> \
#     --model model_random.txt --cache <samples.rds> \
#     --fit-placebo --placebo-cache <p.rds> \
#     --plot --effect both \
#     --plot-out <forest_relative.png> \
#     --plot-out-absolute <forest_absolute.png> [--force]
#
# Single-plot re-render (--effect relative|absolute, one --plot-out;
# absolute still needs --fit-placebo):
#   Rscript run_bnma_pipeline.R ... --plot --effect relative --plot-out <p.png>
#
# Ad hoc, against an already-cached fit (skips plotting):
#   Rscript run_bnma_pipeline.R --prd <p> [--qa <q>] --manifest <m> \
#     --model model_random.txt --cache <samples.rds> \
#     --contrast "treat1|||treat2"
#
# Needs rjags -- `module load jags` in the same shell before this runs
# (see SKILL.md Step 7's inline `module load`; the old
# run_r.sh/run_with_jags.sh wrapper scripts were dropped for the same
# reason as the modes above).

# R truncates warning/error message text at options("warning.length")
# (default 1000 chars, max 8170) -- the missing-decision study list below
# can legitimately run past 1000 chars on this dataset's ~67 studies,
# silently dropping the last name or two rather than erroring loudly.
# Raise it to the max up front so no message from this script ever
# truncates.
options(warning.length = 8170)

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(yaml)
  library(rjags)
  library(ggplot2)
  library(coda)
  library(ggtext)
})

# --------------------------------------------------------------------------
# Shared helpers (formerly lib_common.R -- inlined here since this is now
# the only pipeline script that needs them; append_to_qa.R keeps its own
# tiny copy of just parse_args()/%||% rather than sourcing a third file).
# --------------------------------------------------------------------------
`%||%` <- function(a, b) if (is.null(a)) b else a

#' Collapse repeated internal whitespace and trim ends -- trimws() alone
#' misses internal double-spaces, which otherwise silently fragments one
#' dose into two separate treatment arms in the BNMA.
squish_ws <- function(x) gsub("[[:space:]]+", " ", trimws(x))

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

#' Read a sheet by name (case-insensitively) with a numeric-index fallback --
#' see load_merge_data.R's original header for the two real workbook traps
#' (arbitrary-sheet misread, lowercase "observed"/"prediction" landing on
#' the wrong positional sheet) this guards against.
read_sheet_with_fallback <- function(path, sheet_name, fallback_index) {
  sheets <- readxl::excel_sheets(path)
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

stringify_all <- function(df) {
  if (is.null(df)) return(NULL)
  dplyr::mutate(df, dplyr::across(dplyr::everything(), as.character))
}

QA_NUMERIC_COLS <- c(
  "n", "baseline_wgt", "pchg_wl_ee", "se_wl_ee", "pchg_wl_tre", "se_wl_tre"
)
recast_numeric_cols <- function(df) {
  present <- intersect(QA_NUMERIC_COLS, names(df))
  dplyr::mutate(df, dplyr::across(dplyr::all_of(present), as.numeric))
}

# --------------------------------------------------------------------------
# Embedded JAGS model text (formerly Appendix A's standalone .txt files),
# passed to jags.model() via textConnection() at fit time -- no file ever
# materialized for these. The four network models are compositions along
# exactly two axes (see Appendix A's table), so they're built here from ONE
# shared likelihood body plus two toggles instead of four near-identical
# hand-maintained strings: `pooled_baseline` picks the phi prior (flat vs.
# hierarchical dnorm(m, tau2_m), which also brings m/sigma_m/mu_new), and
# `fixed_delta` picks the delta[i,j] line (stochastic ~dnorm vs.
# deterministic <-). JAGS is declarative, so the tau2d-before-delta line
# order is valid for both variants. The fixed-delta variants keep the
# dead-but-present sigma/tau2 declarations for structural symmetry, exactly
# as the original standalone model_fixed.txt did. This construction also
# makes model_simultaneous_fixed.txt -- historically described only as
# "A3's baseline + A2's delta block", never spelled out -- correct by
# construction rather than hand-assembled (the gap Appendix A notes).
# --------------------------------------------------------------------------
NETWORK_MODEL_BODY <- '
    for(i in 1:ns){
      for(j in 1:na[i]){
        y[i,j] ~ dnorm(eta[i,j], 1 / se[i,j]^2)
        dev[i,j] <- (y[i,j] - eta[i,j])^2 * (1 / se[i,j]^2)
      }
      devstudy[i] <- sum(dev[i, 1:na[i]])
    }
    for(i in 1:ns){
      eta[i,1] <- phi[i] + delta[i,1]
      for(j in 2:na[i]){
        eta[i,j] <- phi[i] + delta[i,j]
      }
    }
    for(i in 1:ns){
      w[i,1]     <- 0
      delta[i,1] <- 0
      for(j in 2:na[i]){
        tau2d[i,j] <- tau2 * 2 * (j-1) / j
        %s
        w[i,j]     <- delta[i,j] - d[trt[i,j]] + d[trt[i,1]]
        sw[i,j]    <- sum(w[i, 1:(j-1)]) / (j-1)
      }
    }
    Dbar <- sum(devstudy[])
    d[1] <- 0
    for(k in 2:M){
      d[k] ~ dnorm(0, 1e-04)
    }
    sigma  ~ dunif(0, 8)
    sigma2 <- sigma * sigma
    tau2   <- 1 / sigma2'

make_network_model <- function(pooled_baseline, fixed_delta) {
  phi_block <- if (pooled_baseline) '
    for(i in 1:ns){
      phi[i] ~ dnorm(m, tau2_m)
    }
    m ~ dnorm(0, 1e-04)
    tau2_m   <- 1 / sigma2_m
    sigma2_m <- sigma_m * sigma_m
    sigma_m  ~ dunif(0, 8)' else '
    for(i in 1:ns){
      phi[i] ~ dnorm(0.0, 0.0001)
    }'

  delta_line <- if (fixed_delta) {
    'delta[i,j] <- (d[trt[i,j]] - d[trt[i,1]]) + sw[i,j]'
  } else {
    'delta[i,j] ~ dnorm((d[trt[i,j]] - d[trt[i,1]]) + sw[i,j], tau2d[i,j])'
  }

  tail_block <- if (pooled_baseline) '
    mu_new ~ dnorm(m, 1 / sigma_m^2)' else ''

  paste0('\nmodel{', phi_block, '\n',
         sprintf(NETWORK_MODEL_BODY, delta_line),
         tail_block, '\n}')
}

MODEL_TEXTS <- list(
  model_random.txt             = make_network_model(pooled_baseline = FALSE, fixed_delta = FALSE),
  model_fixed.txt              = make_network_model(pooled_baseline = FALSE, fixed_delta = TRUE),
  model_simultaneous.txt       = make_network_model(pooled_baseline = TRUE,  fixed_delta = FALSE),
  model_simultaneous_fixed.txt = make_network_model(pooled_baseline = TRUE,  fixed_delta = TRUE),

  model_placebo_random.txt = '
model{
    for(i in 1:n_obs){
      y_pct[i] ~ dnorm(mu[study_idx[i]], 1/se_pct[i]^2)
    }
    for(i in 1:ns_bl){
      mu[i] ~ dnorm(m, 1/sigma2_m)
    }
    m        ~ dnorm(0, 1e-04)
    sigma_m  ~ dunif(0, 10)
    sigma2_m <- sigma_m * sigma_m
    mu_new   ~ dnorm(m, 1/sigma2_m)
}'
)

args <- parse_args(list(
  prd           = list(default = NULL),
  qa            = list(default = NULL),
  data          = list(default = NULL),
  manifest      = list(required = TRUE),
  model         = list(required = TRUE),
  cache         = list(default = NULL),
  force         = list(flag = TRUE, default = FALSE),
  fit_placebo   = list(flag = TRUE, default = FALSE),
  placebo_cache = list(default = NULL),
  n_adapt       = list(default = "10000"),
  n_burnin      = list(default = "10000"),
  n_iter        = list(default = "20000"),
  thin          = list(default = "10"),
  seed          = list(default = "2026"),
  plot          = list(flag = TRUE, default = FALSE),
  plot_out      = list(default = NULL),
  plot_out_absolute = list(default = NULL),
  effect        = list(default = "relative"),
  title         = list(default = NULL),
  xlab          = list(default = NULL),
  contrast      = list(default = NULL)
))

if (is.null(args$data) && is.null(args$prd) && is.null(args$qa)) {
  stop("At least one of --prd, --qa, or --data must be given.")
}
if (isTRUE(args$plot) && is.null(args$plot_out)) {
  stop("--plot needs --plot-out <path.png>")
}

# ==========================================================================
# ALWAYS: load + merge PRD/QA, UNLESS --data points at an already-merged/
# adapted .rds -- the standalone-workbook adapter path (SKILL.md Step 1's
# note) writes its own already-normalized data.frame for a workbook that
# doesn't match the QA/PRD schema at all; --data lets that .rds feed
# straight into build/fit exactly as if it were this block's own output.
# Re-run fresh on every invocation -- cheap and deterministic, so there's
# never an intermediate merged.rds to hand off between separate processes.
# ==========================================================================
if (!is.null(args$data)) {
  if (!file.exists(args$data)) stop("--data file not found: ", args$data)
  merged <- readRDS(args$data)
} else {

region_sheet_pattern <- "^(.*)\\s+(Observed|Prediction)$"

load_tier <- function(path, tier_label) {
  if (is.null(path)) return(NULL)
  if (!file.exists(path)) stop("File not found for --", tier_label, ": ", path)

  sheets <- readxl::excel_sheets(path)
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

  if (length(parts) == 0) stop("Neither an Observed nor a Prediction sheet was found in ", path)
  bind_rows(parts)
}

prd_data <- load_tier(args$prd, "prd")
qa_data  <- load_tier(args$qa, "qa")

if (is.null(prd_data)) {
  merged <- qa_data
} else if (is.null(qa_data)) {
  merged <- prd_data
} else {
  key <- function(df) paste(df$study_name, df$treatment, sep = "|||")
  prd_keys <- key(prd_data)

  qa_keys  <- key(qa_data)
  merged <- bind_rows(
    prd_data %>% filter(!prd_keys %in% qa_keys),
    qa_data
  )
}

} # end of the --data / --prd+--qa branch opened above

merged <- merged %>% select(-any_of(c("study_ind", "arm_ind", "treat")))
merged <- merged %>%
  mutate(
    compound  = tolower(squish_ws(compound)),
    treatment = tolower(squish_ws(treatment)),
    study_name = tolower(squish_ws(study_name))
  ) %>%
  recast_numeric_cols()

# --------------------------------------------------------------------------
# De-duplicate repeat entries for the same (study_name, treatment) -- e.g.
# a study appended to QA more than once across separate /cmh-ci runs (the
# skill never deletes prior QA rows, so this is expected, not corruption).
# Keep the most recently entered row by time_entry (yyyymmdd) and say so;
# older duplicates are left untouched in the QA file itself, they just
# don't feed this fit. A missing/unparseable time_entry sorts last, so a
# dated row always wins over an undated one.
# --------------------------------------------------------------------------
if ("time_entry" %in% names(merged)) {
  dup_keys <- merged %>% count(study_name, treatment) %>% filter(n > 1)
  if (nrow(dup_keys) > 0) {
    cat("Duplicate (study_name, treatment) entries found -- keeping the most recently entered row for each:\n")
    for (i in seq_len(nrow(dup_keys))) {
      cat("  ", dup_keys$study_name[i], " / ", dup_keys$treatment[i], " (", dup_keys$n[i], " entries)\n", sep = "")
    }
  }
  merged <- merged %>%
    mutate(.time_entry_sort = suppressWarnings(as.numeric(time_entry))) %>%
    arrange(study_name, treatment, dplyr::desc(dplyr::coalesce(.time_entry_sort, -Inf))) %>%
    distinct(study_name, treatment, .keep_all = TRUE) %>%
    select(-.time_entry_sort)
}

cat(
  "Merged", nrow(merged), "rows (",
  sum(merged$source_tier == "prd"), "from PRD,",
  sum(merged$source_tier == "qa"), "from QA ).\n",
  "Studies:", n_distinct(merged$study_name), "  Compounds:", n_distinct(merged$compound), "\n"
)

# ==========================================================================
# BUILD -- manifest fields, phantom-placebo handling.
# Always runs before the fit below; derived fresh from the manifest every
# invocation (no intermediate cache between build and fit, so there's no
# risk of a stale batman_data surviving a manifest edit).
# ==========================================================================
manifest <- yaml::read_yaml(args$manifest)
if (is.null(manifest$studies) || length(manifest$studies) == 0) {
  stop("Manifest has no `studies` entries -- every study needs an explicit include/exclude decision before a model can be run.")
}

effect_col <- manifest$effect_col %||% "pchg_wl_ee"
se_col <- manifest$se_col %||% "se_wl_ee"
effect_direction <- manifest$effect_direction %||% "decrease_is_better"
if (!effect_direction %in% c("decrease_is_better", "increase_is_better")) {
  stop("effect_direction must be 'decrease_is_better' or 'increase_is_better', got: ", effect_direction)
}
if (!effect_col %in% names(merged)) stop("effect_col '", effect_col, "' not found. Available: ", paste(names(merged), collapse = ", "))
if (!se_col %in% names(merged)) stop("se_col '", se_col, "' not found. Available: ", paste(names(merged), collapse = ", "))
cat("Endpoint columns: effect_col='", effect_col, "', se_col='", se_col, "', effect_direction='", effect_direction, "'\n", sep = "")

na_like  <- function(x) if (is.numeric(x)) NA_real_ else NA_character_
one_like <- function(x) if (is.numeric(x)) 1 else "1"

if (isTRUE(manifest$se_fallback)) {
  if (is.null(manifest$se_fallback_reason) || !nzchar(trimws(manifest$se_fallback_reason))) {
    stop("se_fallback is true but se_fallback_reason is missing/blank.")
  }
  fallback_sd <- as.numeric(manifest$se_fallback_sd %||% 10)
  se_num <- suppressWarnings(as.numeric(merged[[se_col]]))
  n_num  <- suppressWarnings(as.numeric(merged$n))
  needs_fallback <- is.na(se_num) & !is.na(n_num) & n_num > 0
  if (sum(needs_fallback) > 0) {
    cat(sum(needs_fallback), "row(s) given a derived SE (", fallback_sd, "/ sqrt(n)) -- reason:", manifest$se_fallback_reason, "\n")
    merged[[se_col]][needs_fallback] <- fallback_sd / sqrt(n_num[needs_fallback])
  }
}

usable <- merged %>% filter(!is.na(suppressWarnings(as.numeric(.data[[se_col]]))))
dropped_unusable <- setdiff(unique(merged$study_name), unique(usable$study_name))
if (length(dropped_unusable) > 0) {
  cat("Dropped as unusable (non-numeric/missing ", se_col, "):\n  ", paste(dropped_unusable, collapse = ", "), "\n", sep = "")
}

if (!is.null(manifest$supplementary_data)) {
  required_fields <- c("study_name", "treatment", "compound", effect_col, se_col, "reason")
  supp_rows <- lapply(seq_along(manifest$supplementary_data), function(i) {
    entry <- manifest$supplementary_data[[i]]
    missing_fields <- setdiff(required_fields, names(entry))
    if (length(missing_fields) > 0) stop("supplementary_data entry ", i, " missing: ", paste(missing_fields, collapse = ", "))
    row_df <- data.frame(
      study_name = tolower(squish_ws(entry$study_name)), treatment = tolower(squish_ws(entry$treatment)),
      compound = tolower(squish_ws(entry$compound)),
      aom = if (is.null(entry$aom)) NA_character_ else tolower(squish_ws(entry$aom)),
      region = tolower(squish_ws(entry$region %||% "global")),
      source_tier = "supplementary", source_sheet = "supplementary", stringsAsFactors = FALSE
    )
    row_df[[effect_col]] <- as.numeric(entry[[effect_col]])
    row_df[[se_col]] <- as.numeric(entry[[se_col]])
    row_df
  })
  supp_df <- bind_rows(supp_rows)
  cat("Supplementary data:", nrow(supp_df), "hand-added row(s) across", n_distinct(supp_df$study_name), "study/ies.\n")
  usable <- bind_rows(usable, supp_df)
}

if (!is.null(manifest$row_exclusions)) {
  for (ex in manifest$row_exclusions) {
    match_idx <- which(usable$study_name == ex$study_name & usable$treatment == ex$treatment)
    if (!is.null(ex$n)) match_idx <- match_idx[usable$n[match_idx] == ex$n]
    if (length(match_idx) == 0) stop("row_exclusions entry matched no rows: study_name='", ex$study_name, "', treatment='", ex$treatment, "'")
    if (length(match_idx) > 1) stop("row_exclusions entry matched ", length(match_idx), " rows (ambiguous) -- add `n`.")
    cat("Excluding row: study='", ex$study_name, "' treatment='", ex$treatment, "' -- reason:", ex$reason %||% "(none)", "\n")
    usable <- usable[-match_idx, ]
  }
}

if (!is.null(manifest$compound_relabels)) {
  for (rl in manifest$compound_relabels) {
    match_idx <- which(usable$compound == rl$from)
    if (length(match_idx) == 0) stop("compound_relabels entry matched no rows: from='", rl$from, "'")
    cat("Relabeling compound '", rl$from, "' -> '", rl$to, "'\n")
    usable$compound[match_idx] <- rl$to
  }
}
if (!is.null(manifest$treatment_relabels)) {
  for (rl in manifest$treatment_relabels) {
    match_idx <- which(usable$treatment == rl$from)
    if (length(match_idx) == 0) stop("treatment_relabels entry matched no rows: from='", rl$from, "'")
    cat("Relabeling treatment '", rl$from, "' -> '", rl$to, "'\n")
    usable$treatment[match_idx] <- rl$to
  }
}

if (isTRUE(manifest$placebo_clamp)) {
  if (is.null(manifest$placebo_clamp_reason) || !nzchar(trimws(manifest$placebo_clamp_reason))) {
    stop("placebo_clamp is true but placebo_clamp_reason is missing/blank.")
  }
  clamp_vals <- suppressWarnings(as.numeric(usable[[effect_col]]))
  wrong_direction <- if (effect_direction == "decrease_is_better") clamp_vals > 0 else clamp_vals < 0
  clamp_idx <- which(usable$compound == "placebo" & wrong_direction)
  if (length(clamp_idx) > 0) {
    cat("Placebo clamp:", length(clamp_idx), "row(s) forced to 0 -- reason:", manifest$placebo_clamp_reason, "\n")
    usable[[effect_col]][clamp_idx] <- 0
  }
}

route_filter <- manifest$route_filter %||% "both"
if (!route_filter %in% c("oral", "injectable", "both")) stop("route_filter must be 'oral', 'injectable', or 'both'")
if (route_filter != "both") {
  before_n <- nrow(usable); before_studies <- n_distinct(usable$study_name)
  qualifying_studies <- usable %>% filter(compound != "placebo", aom == route_filter) %>% pull(study_name) %>% unique()
  usable <- usable %>% filter(study_name %in% qualifying_studies) %>% filter(compound == "placebo" | aom == route_filter)
  cat("Route filter '", route_filter, "':", before_n - nrow(usable), "row(s) dropped,",
      before_studies - n_distinct(usable$study_name), "whole study/ies excluded.\n")
}

evidence_filter <- manifest$evidence_filter %||% "both"
if (!evidence_filter %in% c("observed", "prediction", "both")) stop("evidence_filter must be 'observed', 'prediction', or 'both'")
if (evidence_filter != "both") {
  before_n <- nrow(usable)
  usable <- usable %>% filter(source_sheet == "supplementary" | source_sheet == evidence_filter)
  cat("Evidence filter '", evidence_filter, "':", before_n - nrow(usable), "row(s) dropped.\n")
}

if (!is.null(manifest$compound_filter)) {
  compound_filter <- unlist(manifest$compound_filter)
  before_n <- nrow(usable); before_studies <- n_distinct(usable$study_name)
  qualifying_studies <- usable %>% filter(compound != "placebo", compound %in% compound_filter) %>% pull(study_name) %>% unique()
  usable <- usable %>% filter(study_name %in% qualifying_studies) %>% filter(compound == "placebo" | compound %in% compound_filter)
  cat("Compound filter:", before_n - nrow(usable), "row(s) dropped,",
      before_studies - n_distinct(usable$study_name), "whole study/ies excluded.\n")
}

region_filter <- unlist(manifest$region_filter %||% "global")
if (!"region" %in% names(usable)) usable$region <- "global"
before_n <- nrow(usable)
usable <- usable %>% filter(region %in% region_filter)
if (before_n - nrow(usable) > 0) cat("Region filter:", before_n - nrow(usable), "row(s) dropped.\n")

if (route_filter != "both" || !is.null(manifest$compound_filter)) {
  before_studies <- n_distinct(usable$study_name)
  studies_with_active_arm <- usable %>% filter(compound != "placebo") %>% pull(study_name) %>% unique()
  usable <- usable %>% filter(study_name %in% studies_with_active_arm)
  if (before_studies - n_distinct(usable$study_name) > 0) {
    cat("Cross-filter cleanup:", before_studies - n_distinct(usable$study_name), "placebo-only study/ies excluded.\n")
  }
}

studies_in_data <- unique(usable$study_name)
studies_in_manifest <- vapply(manifest$studies, function(s) s$study_name, character(1))
missing_from_manifest <- setdiff(studies_in_data, studies_in_manifest)
if (length(missing_from_manifest) > 0) {
  stop("Manifest is missing an explicit include/exclude decision for ", length(missing_from_manifest),
       " study/ies:\n  ", paste(missing_from_manifest, collapse = ", "))
}
unknown_in_manifest <- setdiff(studies_in_manifest, studies_in_data)
if (length(unknown_in_manifest) > 0) {
  cat("Note: manifest lists studies not present in this data run (ignored):\n  ", paste(unknown_in_manifest, collapse = ", "), "\n")
}

included_studies <- vapply(Filter(function(s) isTRUE(s$include), manifest$studies), function(s) s$study_name, character(1))
data_sel <- usable %>% filter(study_name %in% included_studies)
if (nrow(data_sel) == 0) stop("No rows remain after applying the manifest's study selection.")
data_sel <- data_sel %>% rename(study = study_name, treat = treatment)

bad_placebo <- data_sel %>% filter(compound == "placebo", treat != "placebo")
if (nrow(bad_placebo) > 0) {
  stop("compound == 'placebo' row(s) found with a non-canonical treatment string: ",
       paste(unique(bad_placebo$treat), collapse = ", "), " -- add a treatment_relabels entry mapping to 'placebo'.")
}

colliding_studies <- data_sel %>% count(study, treat) %>% filter(n > 1) %>% pull(study) %>% unique()
if (length(colliding_studies) > 0) {
  cat("Disambiguating studies with an internal same-treatment collision by source:", paste(colliding_studies, collapse = ", "), "\n")
  data_sel <- data_sel %>% mutate(study = if_else(study %in% colliding_studies, paste0(study, " [", source_sheet, "]"), study))
}

study_list <- unique(data_sel$study)
treatment_list <- unique(data_sel$treat)
if ("placebo" %in% treatment_list) {
  treatment_list <- c("placebo", setdiff(treatment_list, "placebo"))
} else {
  warning("No 'placebo' arm found -- adding as phantom reference.")
  treatment_list <- c("placebo", treatment_list)
}

data_recon <- data_sel %>%
  left_join(data.frame(study = study_list, study_ind = seq_along(study_list)), by = "study") %>%
  left_join(data.frame(treat = treatment_list, arm_ind = seq_along(treatment_list)), by = "treat")

arm_rows <- data_recon %>%
  transmute(study_ind, study_name = study, arm_ind, treatment = treat, compound,
            y = as.numeric(.data[[effect_col]]), se = as.numeric(.data[[se_col]]))

model_type <- manifest$model_type %||% "simultaneous"
if (!model_type %in% c("simultaneous", "rand_effect", "fixed_effect")) {
  stop("model_type must be 'simultaneous', 'rand_effect', or 'fixed_effect', got: ", model_type)
}

studies_with_placebo <- data_recon %>% filter(treat == "placebo") %>% pull(study_ind) %>% unique()
studies_without_placebo <- setdiff(unique(data_recon$study_ind), studies_with_placebo)

if (length(studies_without_placebo) > 0) {
  lookup <- data_recon %>% select(study, study_ind) %>% distinct()
  no_placebo_studies <- lookup %>% filter(study_ind %in% studies_without_placebo) %>% pull(study)

  if (model_type == "simultaneous") {
    cat("Studies without a placebo arm (phantom arm injected):\n  ", paste(no_placebo_studies, collapse = ", "), "\n")
    phantom_rows <- data_recon %>% filter(study_ind %in% studies_without_placebo) %>%
      select(study, study_ind) %>% distinct() %>% mutate(treat = "placebo", arm_ind = 1L, compound = NA_character_)
    phantom_rows[[effect_col]] <- na_like(data_recon[[effect_col]])
    phantom_rows[[se_col]] <- one_like(data_recon[[se_col]])
    data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
  } else {
    bridge_requested <- unique(tolower(squish_ws(unlist(manifest$phantom_placebo_studies %||% list()))))
    if (length(bridge_requested) > 0) {
      reason <- manifest$phantom_placebo_reason
      if (is.null(reason) || !nzchar(trimws(reason))) stop("phantom_placebo_studies is set but phantom_placebo_reason is missing/blank.")
      unknown <- setdiff(bridge_requested, tolower(squish_ws(no_placebo_studies)))
      if (length(unknown) > 0) stop("phantom_placebo_studies lists unknown study/ies: ", paste(unknown, collapse = ", "))
    }
    to_bridge <- lookup %>% filter(study_ind %in% studies_without_placebo, tolower(squish_ws(study)) %in% bridge_requested)
    to_leave <- lookup %>% filter(study_ind %in% studies_without_placebo, !tolower(squish_ws(study)) %in% bridge_requested)
    if (nrow(to_bridge) > 0) {
      cat("Phantom-bridged per phantom_placebo_studies -- reason:", reason, ":\n  ", paste(to_bridge$study, collapse = ", "), "\n")
      phantom_rows <- data_recon %>% filter(study_ind %in% to_bridge$study_ind) %>%
        select(study, study_ind) %>% distinct() %>% mutate(treat = "placebo", arm_ind = 1L, compound = NA_character_)
      phantom_rows[[effect_col]] <- na_like(data_recon[[effect_col]])
      phantom_rows[[se_col]] <- one_like(data_recon[[se_col]])
      data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
    }
    if (nrow(to_leave) > 0) {
      cat("Studies left disconnected (model_type='", model_type, "', not bridged):\n  ", paste(to_leave$study, collapse = ", "), "\n")
    }
  }
}

na_df <- data_recon %>% group_by(study_ind) %>% summarise(na = n_distinct(arm_ind), .groups = "drop") %>% arrange(study_ind)
single_arm_studies <- na_df %>% filter(na < 2) %>% pull(study_ind)
if (length(single_arm_studies) > 0) {
  dropped_names <- data_recon %>% filter(study_ind %in% single_arm_studies) %>% pull(study) %>% unique()
  cat("Dropping single-arm study/ies (no relative-effect information possible):\n  ", paste(dropped_names, collapse = ", "), "\n")
  data_recon <- data_recon %>% filter(!study_ind %in% single_arm_studies)
  study_remap <- data.frame(study_ind_old = sort(unique(data_recon$study_ind)), study_ind = seq_along(unique(data_recon$study_ind)))
  data_recon <- data_recon %>% rename(study_ind_old = study_ind) %>% left_join(study_remap, by = "study_ind_old") %>% select(-study_ind_old)
  na_df <- data_recon %>% group_by(study_ind) %>% summarise(na = n_distinct(arm_ind), .groups = "drop") %>% arrange(study_ind)
}

na_vec <- na_df$na
ns <- max(data_recon$study_ind); M <- max(data_recon$arm_ind); max_na <- max(na_vec)
trt <- matrix(NA_integer_, ns, max_na); y <- matrix(NA_real_, ns, max_na); se <- matrix(NA_real_, ns, max_na)
for (i in seq_len(ns)) {
  arms_i <- data_recon %>% filter(study_ind == i) %>% arrange(arm_ind)
  n_i <- nrow(arms_i)
  if (n_i > 0) {
    trt[i, 1:n_i] <- as.integer(arms_i$arm_ind)
    y[i, 1:n_i]   <- as.numeric(arms_i[[effect_col]])
    se[i, 1:n_i]  <- as.numeric(arms_i[[se_col]])
  }
}
batman_data <- list(na = na_vec, M = M, ns = ns, trt = trt, y = y, se = se)

arm_info <- data_recon %>%
  mutate(node = paste0("d[", arm_ind, "]")) %>%
  select(node, arm_ind, treatment = treat, compound) %>%
  mutate(compound = if_else(treatment == "placebo", "placebo", compound)) %>%
  distinct() %>%
  arrange(arm_ind, is.na(compound)) %>%
  distinct(arm_ind, .keep_all = TRUE)
arm_evidence <- data_recon %>% filter(!is.na(source_sheet)) %>% group_by(arm_ind) %>%
  summarise(evidence_type = paste(sort(unique(source_sheet)), collapse = ","), .groups = "drop")
arm_info <- arm_info %>% left_join(arm_evidence, by = "arm_ind")

study_info <- data_recon %>% select(study_ind, study_name = study) %>% distinct() %>% arrange(study_ind)
has_placebo_study <- data_recon %>% filter(arm_ind == 1, !is.na(.data[[effect_col]])) %>% pull(study_ind) %>% unique()
study_info <- study_info %>% mutate(has_placebo = study_ind %in% has_placebo_study)

cat("BATMAN data built:", ns, "studies,", M, "treatment arms.\n")

# ==========================================================================
# FIT -- always runs (model is a required argument now; there is no
# build-preview exit). Optionally also fits the pooled-placebo model
# (--fit-placebo), then either prints a contrast or renders the forest
# plot (--plot), all still in this one process.
# ==========================================================================
if (!args$model %in% names(MODEL_TEXTS)) {
  stop("--model must be one of: ", paste(names(MODEL_TEXTS), collapse = ", "), " -- got: ", args$model)
}

if (!is.null(args$cache) && file.exists(args$cache) && !isTRUE(args$force)) {
  cat("Loading cached MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))
  base_seed <- as.integer(args$seed) * 1000
  has_pooled_baseline <- args$model %in% c("model_simultaneous.txt", "model_simultaneous_fixed.txt")

  draw_from_vague_prior <- function(n, chain_num) if (chain_num == 1) rep(0, n) else rnorm(n, mean = 0, sd = 100)

  inits.list <- lapply(1:3, function(chain_num) {
    d_init <- c(NA, draw_from_vague_prior(M - 1, chain_num))
    init <- list(
      .RNG.seed = base_seed + chain_num, .RNG.name = "base::Wichmann-Hill",
      phi = draw_from_vague_prior(ns, chain_num), d = d_init
    )
    if (has_pooled_baseline) init$m <- draw_from_vague_prior(1, chain_num)
    init
  })

  cat("Compiling JAGS model:", args$model, "\n")
  jags_model <- jags.model(
    textConnection(MODEL_TEXTS[[args$model]]), batman_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = inits.list
  )
  cat("Burn-in (", args$n_burnin, "iterations)...\n")
  update(jags_model, as.integer(args$n_burnin))

  variable_names <- if (args$model == "model_simultaneous.txt") {
    c("d", "phi", "delta", "m", "sigma", "sigma_m", "mu_new")
  } else if (args$model == "model_simultaneous_fixed.txt") {
    c("d", "phi", "delta", "m", "sigma_m", "mu_new")
  } else {
    c("d", "phi", "delta")
  }

  cat("Sampling (", args$n_iter, "iterations, thin =", args$thin, ")...\n")
  samples <- coda.samples(jags_model, as.integer(args$n_iter), variable.names = variable_names, thin = as.integer(args$thin))
  if (!is.null(args$cache)) { saveRDS(samples, args$cache); cat("Samples saved to", args$cache, "\n") }
}

cat("Posterior summary (d[] treatment-effect nodes):\n")
s <- summary(samples)
d_rows <- grepl("^d\\[", rownames(s[[1]]))
print(round(cbind(s[[1]][d_rows, "Mean", drop = FALSE], s[[2]][d_rows, c("2.5%", "97.5%")]), 2))

# ==========================================================================
# CONTRAST (--contrast given) -- a named head-to-head comparison read off
# this run's own posterior, never a hardcoded d[k] index. Skips
# fit-placebo and plotting entirely.
# ==========================================================================
if (!is.null(args$contrast)) {
  parts <- strsplit(args$contrast, "\\|\\|\\|")[[1]]
  if (length(parts) != 2) stop("--contrast must be \"treat1|||treat2\", got: ", args$contrast)
  treat1 <- trimws(parts[1]); treat2 <- trimws(parts[2])

  samples_mat <- as.matrix(samples)
  find_arm <- function(name) {
    k <- arm_info$arm_ind[tolower(arm_info$treatment) == tolower(name)]
    if (length(k) == 0) {
      stop("Treatment not found: '", name, "'. Available: ",
           paste(head(sort(unique(arm_info$treatment)), 15), collapse = ", "))
    }
    k[1]
  }
  k1 <- find_arm(treat1); k2 <- find_arm(treat2)
  d1_col <- paste0("d[", k1, "]"); d2_col <- paste0("d[", k2, "]")
  diff <- samples_mat[, d1_col] - samples_mat[, d2_col]
  mean_diff <- mean(diff); ci <- quantile(diff, c(0.025, 0.975))
  p_treat1_better <- mean(diff < 0)

  cat(sprintf("%s vs %s\n", treat1, treat2))
  cat(sprintf("  contrast (arm_ind %d - arm_ind %d): %.2f (%.2f, %.2f)\n", k1, k2, mean_diff, ci[1], ci[2]))
  cat(sprintf("  P(%s better) = %.3f\n", treat1, p_treat1_better))
  quit(status = 0, save = "no")
}

if (isTRUE(args$fit_placebo)) {
  placebo_rows <- arm_rows %>% filter(compound == "placebo", !is.na(y), !is.na(se), se > 0, is.finite(se))
  if (nrow(placebo_rows) == 0) stop("No usable placebo rows for the pooled-placebo model.")
  study_map <- data.frame(study_ind = sort(unique(placebo_rows$study_ind)), study_idx = seq_along(unique(placebo_rows$study_ind)))
  placebo_rows <- placebo_rows %>% left_join(study_map, by = "study_ind")
  if (nrow(study_map) < 2) stop("Not enough studies with a usable placebo arm (need >= 2; found ", nrow(study_map), ").")

  cat("Pooled placebo model:", nrow(placebo_rows), "placebo row(s) across", nrow(study_map), "study/ies.\n")

  jags_data <- list(y_pct = placebo_rows$y, se_pct = placebo_rows$se, n_obs = nrow(placebo_rows),
                     ns_bl = nrow(study_map), study_idx = placebo_rows$study_idx)

  if (!is.null(args$placebo_cache) && file.exists(args$placebo_cache) && !isTRUE(args$force)) {
    cat("Loading cached placebo-model MCMC samples from", args$placebo_cache, "\n")
    placebo_samples <- readRDS(args$placebo_cache)
  } else {
    base_seed <- as.integer(args$seed) * 1000
    y_mean <- mean(jags_data$y_pct, na.rm = TRUE)
    inits.list <- lapply(1:3, function(chain_num) {
      list(.RNG.seed = base_seed + chain_num + 500, .RNG.name = "base::Wichmann-Hill",
           m = rnorm(1, y_mean, 0.5), sigma_m = runif(1, 0.3, 1), mu = rnorm(jags_data$ns_bl, y_mean, 0.5))
    })
    cat("Compiling pooled-placebo JAGS model\n")
    placebo_model <- jags.model(textConnection(MODEL_TEXTS[["model_placebo_random.txt"]]), jags_data,
                                 n.adapt = 1000, n.chains = 3, inits = inits.list)
    cat("Burn-in (5000 iterations)...\n")
    update(placebo_model, 5000)
    cat("Sampling (10000 iterations, thin = 10)...\n")
    placebo_samples <- coda.samples(placebo_model, variable.names = c("m", "sigma_m", "mu", "mu_new"), n.iter = 10000, thin = 10)
    if (!is.null(args$placebo_cache)) { saveRDS(placebo_samples, args$placebo_cache); cat("Saved:", args$placebo_cache, "\n") }
  }

  ps <- summary(placebo_samples)
  cat(sprintf("Pooled placebo baseline: m = %.3f (95%% CrI %.3f, %.3f)  sigma_m = %.3f\n",
              ps$statistics["m", "Mean"], ps$quantiles["m", "2.5%"], ps$quantiles["m", "97.5%"], ps$statistics["sigma_m", "Mean"]))
}

if (!isTRUE(args$plot)) {
  cat("No --plot given -- fit complete, nothing rendered.\n")
  quit(status = 0, save = "no")
}

# ==========================================================================
# PLOT (--plot given) -- forest plot(s), rendered in this same process so
# there's no second R startup / package-reload between fitting and
# plotting. `--effect both` renders the relative AND absolute plots from
# this one invocation (one MCMC fit, two ggsave calls) -- Step 7's default,
# replacing the old two-invocation flow whose second run repaid a full R
# startup, package load, Excel read, and BATMAN build just to re-plot from
# cache. `--effect relative|absolute` still renders a single plot for ad
# hoc re-renders.
# ==========================================================================
if (!args$effect %in% c("relative", "absolute", "both")) stop("--effect must be 'relative', 'absolute', or 'both'")
if (args$effect %in% c("absolute", "both") && !isTRUE(args$fit_placebo)) {
  stop("--effect ", args$effect, " needs --fit-placebo (with --placebo-cache) in this same invocation.")
}
if (args$effect == "both" && is.null(args$plot_out_absolute)) {
  stop("--effect both needs both --plot-out (relative png) and --plot-out-absolute (absolute png).")
}

render_forest <- function(effect, out_path) {

samples_mat <- as.matrix(samples)
if (effect == "absolute") {
  placebo_samples_mat <- as.matrix(placebo_samples)
  m_samples <- sample(placebo_samples_mat[, "m"], nrow(samples_mat), replace = TRUE)
  sigma_m_samples <- sample(placebo_samples_mat[, "sigma_m"], nrow(samples_mat), replace = TRUE)
  cat("Pooled placebo baseline loaded -- mean m =", round(mean(m_samples), 3), "\n")
}

plot_treatments <- manifest$plot_treatments
if (is.null(plot_treatments) || length(plot_treatments) == 0) {
  plot_treatments <- arm_info %>% filter(treatment != "placebo") %>% pull(treatment) %>% unique()
}

arm_lookup <- arm_info %>% filter(treatment %in% c(plot_treatments, "placebo")) %>% group_by(arm_ind) %>% slice(1) %>% ungroup()

rows <- lapply(seq_len(nrow(arm_lookup)), function(i) {
  arm_k <- arm_lookup$arm_ind[i]; trt_name <- arm_lookup$treatment[i]; cmpd <- arm_lookup$compound[i]
  if (effect == "relative") {
    post <- if (arm_k == 1) rep(0, nrow(samples_mat)) else samples_mat[, paste0("d[", arm_k, "]")]
  } else {
    post <- if (arm_k == 1) m_samples else m_samples + samples_mat[, paste0("d[", arm_k, "]")]
  }
  data.frame(treatment = trt_name, compound = if (trt_name == "placebo") "placebo" else cmpd,
             evidence_type = arm_lookup$evidence_type[i], mean = mean(post),
             val2.5pc = quantile(post, 0.025), val97.5pc = quantile(post, 0.975))
})

data_plot <- bind_rows(rows) %>%
  filter(treatment %in% plot_treatments | (effect == "absolute" & treatment == "placebo")) %>%
  arrange(match(treatment, c("placebo", plot_treatments))) %>%
  mutate(Label = paste0(round(mean, 1), " (", round(val2.5pc, 1), ", ", round(val97.5pc, 1), ")"))

type_code <- c(observed = "o", prediction = "p", supplementary = "s")
data_plot <- data_plot %>%
  mutate(
    evidence_marker = vapply(evidence_type, function(et) {
      if (is.na(et) || !nzchar(et)) return("")
      codes <- type_code[strsplit(et, ",")[[1]]]
      paste0("^", paste(codes, collapse = ","), "^")
    }, character(1)),
    treatment_label = paste0(treatment, evidence_marker)
  )

trt_order <- unique(data_plot$treatment_label)

endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
ylab_text <- args$xlab %||% sprintf("Mean (95%% CI) of %s Percent Change in %s (%%)",
                                     if (effect == "relative") "Pbo-adj" else "Absolute", endpoint_label)
title_text <- args$title %||% sprintf("%s Percent %s Change",
                                       if (effect == "relative") "Placebo-Adjusted" else "Absolute", endpoint_label)

subtitle_text <- NULL
if (effect == "absolute") {
  mu_mean <- mean(m_samples); mu_ci <- quantile(m_samples, c(0.025, 0.975))
  sigma_mu_mean <- mean(sigma_m_samples)
  mu_part <- sprintf("Absolute = pooled placebo μ (%.1f%%; 95%% CrI: %.1f, %.1f; between-study σ=%.2f, standalone placebo-only model) + d[j]",
                      mu_mean, mu_ci[1], mu_ci[2], sigma_mu_mean)
  if ("sigma" %in% colnames(samples_mat)) {
    tau_mean <- mean(samples_mat[, "sigma"]); tau_ci <- quantile(samples_mat[, "sigma"], c(0.025, 0.975))
    subtitle_text <- sprintf("%s    τ = %.2f (95%% CrI: %.2f, %.2f)", mu_part, tau_mean, tau_ci[1], tau_ci[2])
  } else {
    subtitle_text <- paste0(mu_part, "    (no τ for this fit -- either a fixed-effect delta model, or refit to capture 'sigma')")
  }
}

n_compounds <- length(unique(data_plot$compound))
max_label_chars <- max(nchar(data_plot$Label))
plot_width <- 10 + 0.15 * max_label_chars + 0.25 * n_compounds
footnote_wrap_width <- max(40, floor(plot_width * 11))

if (!is.null(subtitle_text)) {
  subtitle_wrap_width <- max(40, floor(plot_width * 9))
  subtitle_text <- paste(strwrap(subtitle_text, width = subtitle_wrap_width), collapse = "\n")
}

by_treatment <- arm_rows %>% filter(treatment %in% c(plot_treatments, "placebo")) %>%
  distinct(treatment, study_name) %>% group_by(treatment) %>%
  summarise(studies = paste(sort(study_name), collapse = ", "), .groups = "drop")
by_treatment <- by_treatment[match(c(plot_treatments, "placebo"), by_treatment$treatment), ]
by_treatment <- by_treatment[!is.na(by_treatment$treatment), ]
contributing_lines <- c(
  "Contributing studies by treatment:",
  unlist(lapply(seq_len(nrow(by_treatment)), function(i) {
    strwrap(paste0(by_treatment$treatment[i], ": ", by_treatment$studies[i]), width = footnote_wrap_width)
  }))
)
footnote_lines <- c(
  contributing_lines,
  strwrap(paste0("Source data: ", manifest$source_data$prd %||% "(not recorded)",
                 if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""), width = footnote_wrap_width),
  strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = footnote_wrap_width)
)
footnote_lines <- c(footnote_lines, "^o^ = observed, ^p^ = projection, ^s^ = supplementary (hand-added, not yet in QA/PRD)")
footnote_text <- paste(footnote_lines, collapse = "\n")

FIXED_COMPOUND_COLORS <- c(
  semaglutide = "#7B241C", cagrisema = "#1B4F72", maritide = "#D68910", retatrutide = "#000000",
  berobenatide = "#E74C3C", tirzepatide = "#85C1E9", vk2735 = "#6C3483", brenipatide = "#00BFC4", placebo = "#7F8C8D"
)
compounds_in_plot <- unique(data_plot$compound)
unmapped_compounds <- setdiff(compounds_in_plot, names(FIXED_COMPOUND_COLORS))
generate_fallback_colors <- function(compounds) {
  n <- length(compounds)
  if (n == 0) return(character(0))
  base_colors <- RColorBrewer::brewer.pal(max(min(n, 12), 3), "Set3")
  if (n > 12) base_colors <- grDevices::colorRampPalette(RColorBrewer::brewer.pal(12, "Set3"))(n)
  setNames(colorspace::darken(base_colors[seq_len(n)], amount = 0.3), compounds)
}
fallback_colors <- generate_fallback_colors(unmapped_compounds)
compound_colors <- c(FIXED_COMPOUND_COLORS, fallback_colors)

pforest <- ggplot(
  data_plot,
  aes(x = factor(treatment_label, levels = rev(trt_order)), y = mean, ymin = val2.5pc, ymax = val97.5pc)
) +
  geom_pointrange(aes(col = compound), size = 0.5) +
  geom_hline(yintercept = 0, linewidth = 1, linetype = 2) +
  geom_text(aes(y = mean, label = Label), position = position_nudge(x = 0.32), vjust = 0, size = 4.2, color = "black", show.legend = FALSE) +
  scale_color_manual(values = compound_colors, name = "Compound") +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.08))) +
  scale_x_discrete(expand = expansion(add = c(0.6, 0.6))) +
  coord_flip() +
  xlab("") + ylab(ylab_text) +
  ggtitle(title_text, subtitle = subtitle_text) +
  theme_bw() +
  theme(
    axis.title = element_text(size = 16),
    axis.text.y = ggtext::element_markdown(size = 14),
    axis.text.x = element_text(size = 14),
    plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 11, color = "grey35", hjust = 0.5),
    legend.text = element_text(size = 13),
    legend.title = element_text(size = 13)
  )

subtitle_lines <- if (is.null(subtitle_text)) 0 else lengths(regmatches(subtitle_text, gregexpr("\n", subtitle_text))) + 1
plot_height <- max(4, 0.6 * length(trt_order)) + 0.18 * subtitle_lines
ggsave(out_path, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot (", effect, ") saved to:", out_path, "\n")
cat("Footnote (not rendered on the plot -- console record only):\n", footnote_text, "\n")

}  # end render_forest()

if (args$effect == "both") {
  render_forest("relative", args$plot_out)
  render_forest("absolute", args$plot_out_absolute)
} else {
  render_forest(args$effect, args$plot_out)
}

# [cmh-ci embedded script end: run_bnma_pipeline.R]
```
### B2. `append_to_qa.R`

Step 4's "promote to QA" path — appends new rows to an existing QA workbook in-place, creating it directly from the PRD schema if it doesn't exist yet (no separate user confirmation beyond Step 3's row-table confirmation). Called once per session when new data is being promoted to the shared QA file before fitting. No longer sources a separate `lib_common.R` (retired along with the other consolidated scripts) — its own tiny `parse_args()`/`%||%` copy is inlined instead. Also fixed: appending to a QA sheet that currently has 0 rows used to crash `bind_rows()` with a type-mismatch error, because `read.xlsx` infers an all-logical-NA schema for an empty sheet, which conflicts with `new_rows`' real types — a genuinely common case, since a freshly created or not-yet-populated QA sheet is blank far more often than not. A related but distinct case is also fixed now: a *non-empty* sheet where a column already holds real values of one type (e.g. `time_entry` written as numeric by an earlier run) while this run's `new_rows` built that same column as character — `bind_rows()` can't guess a common type there the way it can for an all-NA column, so `new_rows` is now coerced to match whatever real type already exists in each column before binding.

```r
#!/usr/bin/env Rscript
# Step 4 of the /cmh-ci skill (the "promote to QA" branch): append new rows
# to the QA workbook.
#
# The QA file is the living working copy of the landscape data. New entries
# (from press releases, digitized slides, subsets of other workbooks) land
# here first, then eventually get promoted to PRD through the normal team
# process. This script handles the physical append (and create-if-missing);
# the skill's Step 3 handles getting the rows confirmed before this runs.
#
# Usage:
#   Rscript append_to_qa.R --qa <path.xlsx> --sheet <Observed|Prediction> \
#     --rows <rows.rds> --create-from <prd_path.xlsx>

suppressPackageStartupMessages({
  library(openxlsx)
  library(readxl)
  library(dplyr)
})

`%||%` <- function(a, b) if (is.null(a)) b else a
parse_args <- function(spec) {
  raw <- commandArgs(trailingOnly = TRUE)
  out <- list()
  for (name in names(spec)) out[[name]] <- spec[[name]]$default
  i <- 1
  while (i <= length(raw)) {
    key <- gsub("-", "_", sub("^--", "", raw[i]))
    if (!key %in% names(spec)) stop("Unknown argument: --", raw[i])
    if (i == length(raw)) stop("Missing value for --", raw[i])
    out[[key]] <- raw[i + 1]
    i <- i + 2
  }
  for (name in names(spec)) if (isTRUE(spec[[name]]$required) && is.null(out[[name]])) stop("Missing required argument: --", name)
  out
}

args <- parse_args(list(
  qa          = list(required = TRUE),
  sheet       = list(required = TRUE),
  rows        = list(required = TRUE),
  create_from = list(default = NULL)
))

if (!args$sheet %in% c("Observed", "Prediction")) {
  stop("--sheet must be 'Observed' or 'Prediction', got: ", args$sheet)
}

if (!file.exists(args$rows)) stop("--rows file not found: ", args$rows)
new_rows <- readRDS(args$rows)
if (!is.data.frame(new_rows) || nrow(new_rows) == 0) {
  stop("--rows must be a non-empty data.frame, got ", nrow(new_rows), " rows.")
}

if (!file.exists(args$qa)) {
  if (is.null(args$create_from)) {
    stop("QA file does not exist (", args$qa, ") and --create-from was not provided.\n",
         "Step 4 always passes --create-from so a missing QA file is created directly.")
  }
  if (!file.exists(args$create_from)) stop("--create-from file not found: ", args$create_from)

  cat("Creating new QA workbook from PRD schema:", args$create_from, "\n")
  prd_obs_cols <- names(read_excel(args$create_from, sheet = "Observed", n_max = 0))
  prd_pred_cols <- tryCatch(
    names(read_excel(args$create_from, sheet = "Prediction", n_max = 0)),
    error = function(e) prd_obs_cols
  )

  wb <- createWorkbook()
  addWorksheet(wb, "Observed")
  writeData(wb, "Observed", as.data.frame(matrix(nrow = 0, ncol = length(prd_obs_cols), dimnames = list(NULL, prd_obs_cols))))
  addWorksheet(wb, "Prediction")
  writeData(wb, "Prediction", as.data.frame(matrix(nrow = 0, ncol = length(prd_pred_cols), dimnames = list(NULL, prd_pred_cols))))

  dir.create(dirname(args$qa), recursive = TRUE, showWarnings = FALSE)
  saveWorkbook(wb, args$qa, overwrite = TRUE)
  cat("Created:", args$qa, "\n")
}

wb <- loadWorkbook(args$qa)
sheets <- names(wb)
if (!args$sheet %in% sheets) stop("Sheet '", args$sheet, "' not found in ", args$qa, ". Available: ", paste(sheets, collapse = ", "))

existing <- read.xlsx(wb, sheet = args$sheet)
if (is.null(existing)) existing <- data.frame()

existing_cols <- names(existing)
for (col in existing_cols) if (!col %in% names(new_rows)) new_rows[[col]] <- NA
new_rows <- new_rows[, intersect(names(new_rows), existing_cols), drop = FALSE]
new_rows <- new_rows[, existing_cols, drop = FALSE]

# A non-empty existing sheet can have a column already holding real
# (non-NA) values of one type -- e.g. time_entry written as numeric by an
# earlier run -- while this run's new_rows built that same column as
# character. bind_rows()/vctrs coerces an all-NA column to anything for
# free, but refuses to guess a common type once both sides have actual
# values of genuinely different types (numeric vs character is the one
# that bites in practice). Match new_rows to whatever real type already
# exists in that column before binding, column by column; skip columns
# where existing is all-NA, since vctrs already handles those without help
# and coercing new_rows there could silently mangle real new values (e.g.
# as.logical() on a real string turns it into NA).
for (col in existing_cols) {
  existing_col <- existing[[col]]
  if (all(is.na(existing_col))) next
  target_class <- class(existing_col)[1]
  if (identical(target_class, class(new_rows[[col]])[1])) next
  new_rows[[col]] <- switch(target_class,
    numeric   = suppressWarnings(as.numeric(new_rows[[col]])),
    integer   = suppressWarnings(as.integer(new_rows[[col]])),
    character = as.character(new_rows[[col]]),
    logical   = as.logical(new_rows[[col]]),
    new_rows[[col]]
  )
}

# An existing sheet with 0 rows (a QA workbook that was just created, or a
# sheet nobody has populated yet) has every column inferred as logical NA
# by read.xlsx -- there's no data to infer real types from. bind_rows then
# errors on the type mismatch against new_rows' actual types (character,
# numeric, ...), even though there's nothing of substance in `existing` to
# lose. Skip the bind in that case; new_rows (already reordered to
# existing_cols above) is the whole answer.
combined <- if (nrow(existing) == 0) new_rows else bind_rows(existing, new_rows)

removeWorksheet(wb, args$sheet)
addWorksheet(wb, args$sheet)
writeData(wb, args$sheet, combined)

desired_order <- intersect(c("Summary", "Observed", "Prediction"), names(wb))
remaining <- setdiff(names(wb), desired_order)
worksheetOrder(wb) <- match(c(desired_order, remaining), names(wb))

saveWorkbook(wb, args$qa, overwrite = TRUE)

cat(
  "Appended", nrow(new_rows), "rows to sheet '", args$sheet, "' of ", args$qa, ".\n",
  "New studies:", paste(unique(new_rows$study_name), collapse = ", "), "\n",
  "Total rows in '", args$sheet, "' now:", nrow(combined), "\n",
  sep = ""
)

# [cmh-ci embedded script end: append_to_qa.R]
```

