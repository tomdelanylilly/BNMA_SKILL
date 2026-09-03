# `/cmh-ci` skill — design doc

> **Note (2026-08-26):** this skill was scoped and originally built under
> the working name `/bnma`; it was later renamed to `/cmh-ci` (see
> `SKILL.md`'s own name and the "Sixth design iteration" below). References
> to `/bnma` in the Background/Goals/original design sections immediately
> below reflect that original name at the time they were written. Likewise,
> the "Step 1–6" outline in the original `/bnma` skill design section is the
> *first pitch*, not the shipped pipeline — it was superseded first by
> Steps 0–7a (Second/Third design iterations) and then rebuilt into the
> current **Step 1–10** structure (Fourth design iteration onward), which is
> what `SKILL.md` actually implements today. Read the numbered "design
> iteration" sections below in order for the real history.

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

This doc scopes building what was then called the `/bnma` skill (renamed
`/cmh-ci` — see the note above) from scratch to close both gaps, plus a
data-quality feature requested separately: detecting near-duplicate
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
2. **Build `/bnma`** (later renamed `/cmh-ci`) as a real, reusable Claude
   Code skill that forces explicit decisions instead of running end-to-end
   on hardcoded vectors.

## `/bnma` skill design (original pitch)

*See the numbered design-iteration sections further down for how this
evolved into the shipped `/cmh-ci` structure.*

Location (at the time): `.claude/skills/bnma/SKILL.md` + `scripts/` for
anything that must be deterministic code rather than LLM judgment (matching
the existing `extract-publication` skill's pattern of SKILL.md +
`scripts/extract.py`). The shipped skill lives at
`.claude/skills/cmh-ci/SKILL.md` instead, with every script embedded in its
own appendices rather than kept as separate files (see README.md).

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
- Run `/bnma` (later renamed `/cmh-ci`) end-to-end against the local misc5
  files and confirm it: (a) surfaces at least one realistic naming/pooling
  flag against deliberately-seeded near-duplicate/route-collision rows, (b)
  lists every study/phase/data-type combination present in the real merged
  data, (c) refuses to proceed without explicit confirmation, (d) produces
  the same forest plot as the current script when given the same selection
  that script currently hardcodes, and (e) writes a manifest documenting
  both the naming/pooling resolutions and the study selection.

## Second design iteration: workflow ordering (August 2026 meeting)

By the time the skill had grown through Steps 0–7a (see SKILL.md), it
already forced explicit study selection and a naming/pooling QA gate — the
two problems this doc originally scoped. But the team (Ran Liao, Tom
Delany, Godwill Zulu, Xiang Zhang, Xian Yao Gwee) met on 2026-08-25 and
identified a third, structural problem: a session could go from "here's a
data file" straight to a full BNMA with no guided introduction to what the
data actually contained, and folder/manifest setup happened as soon as a
dataset was located — before the statistician had even seen what was
available, let alone decided whether they wanted to run anything at all.

**Ran's core argument:** workflow *order* is the requirement, not just the
presence of a confirmation gate somewhere in the pipeline. Users need to be
guided through introduce → select → review subset → confirm sufficiency →
optionally augment → run, in that order — not asked to make discretionary
decisions before they've been told what they're choosing from.

**Agreed changes, implemented as Step 0's rewrite + two new steps
(3.5/3.6) in SKILL.md:**

1. **Introduce the data before asking for anything.** Step 0 now always
   shows a summary of what's in the located PRD/QA data (studies,
   compounds, phases, evidence tiers) before Step 3's consolidated ask —
   even when the initial prompt was already specific, so the guided order
   is consistent for everyone, not just users who show up without a plan.
2. **An explicit explore-vs-run fork.** Xian Yao and Xiang's clarifying
   questions surfaced that some users just want to browse the PRD data with
   no intention of running a BNMA at all. Step 0c now asks this directly
   when the initial prompt gives no run signal, and exploring never
   triggers folder/manifest/naming-gate-resolution pressure.
3. **Folder creation moved later, to Step 3.5.** Previously proposed as
   soon as a dataset was located (old Step 0c) — now proposed only once the
   study subset is confirmed and the statistician has said the subset is
   sufficient. Matches Tom's point in the meeting that folder setup
   shouldn't precede knowing whether there's even a run to set up for.
4. **Custom/external data moved after subset confirmation, to Step 3.6.**
   Previously offered immediately after locating the base dataset (old Step
   0b), before any PRD-only selection happened. Xiang's framing — filter
   PRD first, then merge additional project-specific data — is now the
   literal order: Step 3's ask covers the PRD-only subset; Step 3.5 asks
   whether it's sufficient; only if not does Step 3.6 bring in anything
   else.
5. **Custom data defaults to a temporary, project-scoped merge, not a
   shared-QA write.** Ran's clarification: PRD is only updated semi-annually,
   so most custom data belongs to one project, not the shared tier. Step
   3.6 now defaults to the existing `supplementary_data` manifest field
   (manifest-local, no shared file touched) and treats writing to the
   shared QA workbook as an explicit opt-in ("promote to QA"), reversing
   the old default (QA-append first, `supplementary_data` as the rare
   exception).

**Explicitly not changed:** the statistical pipeline (BATMAN, JAGS models,
forest plot), the naming/pooling QA gate's own logic, and (at the time)
Step 3's "one consolidated round trip" principle for its own scope/naming/
study items — Godwill's point that the skill already supported most of
what was being discussed, just not in the right order, held up: this was a
reordering and one new gate, not a rewrite. See the third iteration below
for why that last point didn't hold for long.

## Third design iteration: scope questions as a sequence, not a form (August 2026)

One day after the second iteration shipped, explicit direction reversed
the "one consolidated round trip" principle for Step 3's SCOPE items
specifically: endpoint, route, evidence, region, heterogeneity, and effect
type are now asked as individual questions, one at a time, each waited on
before the next is asked — not bundled into one message with a stated
default per line. The examples given were concrete: "do you want oral/
injectable," "analysis type (placebo-adjusted or absolute)" — genuine
questions, not declarative defaults to override.

This only applies to the small, closed-choice scope items (now Step 3a).
The naming/pooling flags and the study list (now Step 3b) stay a grouped
confirmation — those are variable-length and data-dependent (potentially
dozens of studies on a real landscape run), so a question-per-item
treatment isn't practical there the way it is for six closed-choice scope
questions. Step 3.5/3.6 (subset sufficiency, custom data, folders) are
unaffected — they were never part of the original "one round trip" scope
anyway.

## Fourth design iteration: rebuilding the master step numbering (August 2026)

The user gave an explicit 9-item outline for the entire pipeline — introduce
the PRD dataset, ask which studies, create/review a subset, ask about
non-PRD data, convert it, merge it, generate the BNMA, collect modelling
preferences, produce outputs — and asked for the whole Step 0–7a numbering
to be rebuilt around it, not just Step 0. Two placement calls were
confirmed explicitly: route/evidence/region scope filters fold into "which
studies are you interested in" rather than "modelling preferences," and the
new outline replaces the entire master numbering.

This was a full renumbering, not a new gate — nearly everything from the
third iteration (the naming/pooling gate, the manifest schema, JAGS/MCMC
specifics, the forest plot, the driver script) already existed and only
needed to move under the step it narratively belonged to:

- **Steps 1–3** (introduce, ask which studies, review the subset) are the
  old Step 0/2.5/3a/3b content, reordered: scope questions (endpoint,
  route, evidence, region) move into "which studies," heterogeneity and
  effect type move out entirely — they're modelling preferences now, not
  data-selection choices.
- **Steps 4–6** (ask about custom data, convert it, merge it) split what
  used to be Step 3.5/3.6 into three narrower steps, matching the meeting's
  own "ask → convert → merge" phrasing instead of one combined intake flow.
- **Step 7** ("generate the BNMA") folds in the folder/CLAUDE.md proposal
  (moved from old 3.5) and old Step 4's manifest write, then runs
  `build_batman_data.R` — but *only* the BATMAN-build call, not the fit.
- **Step 8** ("collect modelling preferences") is the genuine improvement
  this reordering produces for free: heterogeneity and effect type used to
  be asked *before* `build_batman_data.R`'s star-network check ran (old
  Step 3a), which meant the doc had to explain "don't auto-correct, the
  earlier answer stands unless the statistician changes it after seeing the
  finding." Now that check has already run (Step 7), so Step 8 just states
  the real recommendation directly — there's no earlier answer to
  reconcile, because nothing was asked until the actual network structure
  was known.
- **Step 9** ("produce outputs") is old Step 5's fit + Step 6's forest plot
  + Step 7/7a's driver script and promote/discard offer, unchanged in
  substance.

No R script logic changed — this was purely a matter of which step number
each existing chunk of prose and each script invocation lives under.

## Fifth design iteration: named studies and an explicit run/no-run checkpoint (August 2026)

Two follow-on requests, both integrated into the fourth iteration's
numbering rather than bolted on separately:

1. **Step 2 resolves named studies, not just named compounds.** A
   statistician might open with "I want ATTAIN-1 vs. SURMOUNT-4" rather
   than naming compounds/treatments — the same up-front resolution 2a
   already did for compounds now also matches against `study_name` values
   (case/punctuation-insensitive, same fuzzy-match mechanism as the
   naming/pooling gate). Naming a study up front sets its *proposed*
   decision in Step 3 to "include, per your request" — it does not skip
   Step 3's enumeration. This matters specifically for phase 1/2 studies:
   naming one by name **is** the explicit decision the "no silent default"
   rule requires, so it doesn't need a second ask, but it still has to
   appear in Step 3's list with that reason shown — visibility is never
   traded away for convenience, even when the decision was made in the
   original request rather than in reply to a question.
2. **A new Step 7 ("confirm whether to proceed to a BNMA run") sits
   between the old Steps 6 and 7.** Explicit rationale: a statistician's
   goal for a session might genuinely be narrower than "produce a forest
   plot" — reviewing what PRD has, or getting their own data into QA —
   and that's a complete outcome, not an incomplete one. This is a second,
   later opt-out, distinct from Step 1d's explore-or-run fork: Step 1d
   catches someone who shows no run signal *before* any work happens;
   Step 7 catches the case where run-intent looked clear at the start but
   the actual goal turns out to be narrower once the statistician has seen
   the data and made real selections (possibly including a real QA
   promotion in Steps 5-6). Inserting a genuine new checkpoint got a real
   top-level step number, not a decimal patch (e.g. "6.5") — the old Steps
   7/8/9 (and every sub-step: 7a-7c, 8a-8c, 9a-9e, plus every cross-reference
   in the appendix R-script comments) shifted to 8/9/10 to make room, the
   same full-renumbering approach as the fourth iteration, rather than
   layering a new step onto the existing structure without adjusting what
   was already there.

## Sixth design iteration: Step 1 is PRD-first and genuinely explore-first (August 2026)

Step 1a previously tried the QA path first, falling back to PRD — leftover
from the pre-`cmh-ci` design, and inconsistent with Step 1's own title
("introduce the available **PRD** dataset"). Rebuilt around PRD as the
primary, default search target:

- **Locating the base dataset now only searches for PRD files.** A newer,
  not-yet-promoted QA file is Step 4's concern ("additional, non-PRD
  data"), not something Step 1 discovers or substitutes on the
  statistician's behalf. If a directory is given (or nothing is — default
  to the project's own working directory), search it depth-limited for PRD
  files specifically, list every candidate with modified dates, and get an
  explicit pick, same "never silently pick the newest" rule as everywhere
  else.
- **Step 1b never passes `--qa` to `load_merge_data.R`**, even if the
  statistician named both a PRD and QA path in the same initial message —
  merging QA in is Step 4's question to ask, not a side effect of loading
  the PRD file. If both were given up front, the QA path is held onto (not
  dropped) and offered as Step 4's stated default answer instead.
- **The naming/pooling gate (Step 1c) no longer runs automatically.** It
  used to fire unconditionally right after loading the data, before Step
  1d's explore-or-run fork was even checked — so a pure "what's in this
  data" session paid for materializing scripts and running NMA-specific QA
  machinery it never needed. Found on a real session, 2026-08-26: prompt
  was "I want to use this skill, how can it help me" (no run signal at
  all) → PRD file located and confirmed → the skill jumped straight into
  writing `check_naming_pooling.R` and narrating "now running the
  naming/pooling QA gate," never asking the explore-or-run question at
  all. Root cause: a bare confirmation reply to 1a's "should I use this
  file?" ("yes, proceed") was being treated as run-intent, and 1c's own
  instructions had no gating condition at all. Fixed by making 1c check for
  real run-intent first (an endpoint, named studies/compounds, a mention of
  a BNMA/forest plot) and explicitly defer to 1d's fork when there isn't
  any — 1d's own "if exploring" branch was corrected to match (it no longer
  assumes 1c already ran).
- **Step 1b stopped materializing Appendix D3's `run_with_jags.sh`.** That
  wrapper only matters for the JAGS-fitting step (Step 5/9), unreachable
  that early regardless of explore-or-run — writing it during Step 1 was
  pure waste even on the run path, not just the exploring one.

## Seventh design iteration: two bugs found running the corrected pipeline against real data (August 2026)

Testing the sixth iteration's fixes against a real weight-loss/oral/phase-3
subset of the full landscape PRD surfaced two further problems — not design
oversights caught by discussion this time, but bugs an actual end-to-end run
exposed:

1. **`route_filter`/`compound_filter` orphaned placebo rows instead of
   dropping studies outright.** Both filters exempted `compound ==
   "placebo"` rows globally (placebo is the network's shared reference arm,
   so it shouldn't be dropped just because it's tagged with a route that
   doesn't match the filter) — but the exemption applied to *every* study in
   the dataset, not just ones that had a real, matching-route row. Filtering
   the full landscape dataset to `route_filter: oral` pulled in 22
   injectable-only studies (`surmount-1`, `step-1`, etc.) this way, each
   surviving with exactly one row — its own placebo — and forcing an
   explicit include/exclude decision in the manifest on studies that were
   never actually in scope. The statistician's own framing of the fix:
   "I want the studies in which those compounds exist, along with the
   placebo arm they come with, not the ones outside that remit." Both
   filters are now study-level — a study only qualifies if it has at least
   one *real* (non-placebo) row matching the filter; a non-qualifying study
   is dropped entirely, including its placebo row. A second, cross-filter
   safety net runs after all four filters (route, evidence, compound,
   region), to catch the same artifact when evidence_filter — not
   route/compound — is what empties a study's last qualifying row; it's
   gated so it never fires with no filter active, since a genuinely
   single-arm study in the source data must still surface via the normal
   completeness check, not be silently dropped.
2. **`programs/`/`output/shared/` folders defaulted to nesting under
   wherever the PRD file happened to sit.** The same real run ended up with
   its working folders at `/lillyce/prd/.../weight/programs/...` — inside
   the PRD tree itself. PRD is the curated, semi-annual read tier; QA is
   the live working copy, and an analyst's own work products belong there.
   Step 8a now derives a QA-rooted base directory before proposing folders:
   reuse an already-known QA path if one exists this session, else derive
   one from the PRD path via the same `/prd/` → `/qa/` swap Step 6 already
   uses to find the corresponding QA file, else ask rather than guess (e.g.
   a personal project directory with no PRD/QA tier structure at all).

## Eighth design iteration: the report becomes a genuinely runnable
`.Rmd` + `.html` pair, and appended QA files get a date-rename (2026-08-31)

1. **The per-run report is no longer a single self-contained document
   with the pipeline script embedded as reference text.** It's now a
   real `.Rmd` with six runnable code chunks — Setup (`library()` calls,
   paths, MCMC config), Data load, Build BATMAN, Fit model, Results, and
   Forest plots — each self-contained enough to re-run from that point if
   earlier objects are already in the workspace. Chunks default to
   `eval=FALSE`, so immediately after writing the `.Rmd`, the same shell
   renders it to `.html` (`rmarkdown::render(..., output_format =
   "html_document")`) in seconds — it typesets the narrative and code
   without re-running JAGS. The programs folder now holds both files: the
   `.Rmd` for a statistician to open in RStudio and step through, and the
   `.html` for something shareable immediately, without RStudio. This
   replaces the prior "one file, script embedded inside it" design (see
   the "no sibling script file to keep in sync" reasoning above) with two
   files that serve genuinely different purposes rather than one file
   trying to serve both.
2. **`append_to_qa.R` renames the QA file after appending.** Its
   filename carries a date (e.g. `cwm_wl_nont2d_qa_20260827.xlsx`), and
   until now that date only ever reflected when the file was first
   created, not when it was last updated — a new `--rename-date`
   argument does an in-place `mv` to the append date (e.g. `_qa_20260827`
   → `_qa_20260831` for an append run on 2026-08-31), one QA file at a
   time, no stale copies left behind. Whichever step calls this must
   carry the renamed path forward — Step 7's `--qa` argument needs the
   new filename, not the one it started with.
3. **Landing-page and Step-4 wording clarity** — the workflow-at-a-glance
   list's Step 3 and Step 7 lines were reworded for clarity (explicit
   "studies, compounds, treatments, phases" review list; explicit
   enumeration of what Step 7 now produces). No behavior change, just
   text that more accurately previews what the corresponding step
   actually does.

## Ninth design iteration: removing redundant prose (2026-09-01)

A pass over the whole file to find text stated in two or more places that
could drift out of sync surfaced a consistent pattern: "What this skill
does NOT do" (a standalone section near the end of the numbered steps)
re-explained, in compressed form, facts already stated in full in Steps
5–7 and Appendix B — and it had already started drifting (its
programs-folder bullet omitted a detail Step 7's own version still had).
Separately, several of the embedded R scripts' own comments fully
re-derived design rationale the surrounding SKILL.md prose already
covers, instead of pointing back to it.

1. **The "What this skill does NOT do" section was deleted outright.**
   Every substantive bullet was a paraphrase of something Steps 5–7 or
   Appendix B already say in full; the two genuinely unique bullets (a
   note that `/cmh-ci-explain` was replaced by the always-shown landing
   page, and "no Project CLAUDE.md generation") were historical footnotes
   with no effect on current behavior, safe to drop rather than relocate.
2. **Five R-script comments were trimmed to short pointers** instead of
   full restatements: the four-network-model "two axes" comment now
   points at Appendix A instead of re-deriving its table; the manifest
   `include: true` comment now points at Step 5; the cross-tier
   "momentum" disambiguation comment now points at Step 1 (dropping the
   duplicated example); the `time_entry` dedup comment now points at Step
   4; and `run_bnma_pipeline.R`'s own header comment now points at the
   Appendix B intro instead of re-explaining the 9-scripts-to-2
   consolidation history. In every case the actual usage examples and any
   implementation detail the prose didn't already cover were kept —
   only the restated narrative was cut.

Deliberately left alone: the workflow enumerated three times (the ASCII
diagram, the "do not skip steps" paragraph, and the landing page's own
verbatim block) — each serves a different display purpose, and the
landing page is explicitly fixed, print-verbatim text, so collapsing them
risked more than it saved. Also left alone: the intentionally duplicated
`%||%`/`parse_args()` helpers between `run_bnma_pipeline.R` and
`append_to_qa.R` — real functional code, and the file already explains
why B2 keeps its own copy rather than sourcing a third file.

## Tenth design iteration: Step 1 efficiency — deterministic naming
check and dropping the redundant compound field (2026-09-01)

Step 1's PRD introduction was reported as slow. Investigating surfaced
two independent costs, only one of which was worth fixing:

1. **Emitting the full per-study list is a roughly fixed cost** tied to
   how many studies exist and how much detail Step 1 insists on showing
   per study — not something to optimize away without trading off the
   transparency Step 1 is built around (never collapsing the Prediction
   sheet into a summary paragraph, per the existing rule a few lines
   above). Left alone.
2. **The naming/pooling anomaly detection — exact `study_name` collisions
   across tiers, and same-compound near-duplicate names across tiers
   (e.g. "maritide" vs. "maritide_ph2") — was pure unassisted reasoning**,
   done by reading the entire printed study list and comparing every name
   against every other name from scratch, every single time Step 1 runs.
   This was the genuinely variable, expensive part.

**Fix:** the R script itself now computes both checks deterministically
before printing anything — an exact collision via `count(study_name)`,
and a same-compound near-duplicate via base R's `adist()` (Levenshtein
distance ≤ 5; no new package). It prints a "Naming/pooling anomalies"
block directly, restricted to cross-tier pairs so legitimate same-tier
subgroup splits (e.g. "(bmi<35)" vs. "(bmi>=35)") never get falsely
flagged. Step 1's own instructions now say to relay that block, not
re-derive it — the model's job shrinks from an open-ended pairwise
comparison to confirming a short, pre-computed list. What the heuristic
deliberately doesn't catch (a same-tier trial-and-its-extension pair)
still needs a human look; Step 1 says so explicitly rather than
implying full coverage. Verified against synthetic fixtures covering
exact duplicates, near duplicates, no anomalies, and a single-study edge
case before shipping.

**Separately, a real duplication was found in the display format
itself:** each study line showed both a comma-joined `compound` list and
a `treatment` list right after it — e.g. "ct-996, placebo: ct-996;
placebo" — even though treatment strings already name the compound (a
dose/frequency string like "orforglipron 36mg qd" makes the compound
clear on its own). The standalone `<compound>:` segment was dropped from
both the R script's print loop and the confirmation-echo format; compound
values are still computed and carried internally (the anomaly pre-pass
above still needs them), just no longer surfaced as a separate,
redundant field in the visible list.

## Eleventh design iteration: splitting the report deliverable again,
and a real forest-plot rendering bug (2026-09-03)

1. **The per-run report splits into two files again — but not back to
   the pre-Eighth-iteration design.** The Eighth iteration's `.Rmd` (real
   code chunks, `eval=FALSE`, run interactively in RStudio) worked but
   asked something of the reader every other artifact this skill
   produces doesn't: open RStudio and step through chunks by hand just
   to reproduce a result. Feedback was direct — the actual reproduction
   mechanism should be a plain script, runnable top to bottom with one
   `Rscript` call, and the `.Rmd` should be what a reader opens to
   understand what happened, not what they execute. So `report.R` now
   carries everything Chunks 1–6 held (the seeded inits, the
   pattern-resolved QA path, the real `render_forest()` code — all of
   Ninth/Tenth iteration's fixes carry forward unchanged, just relocated
   out of chunk markers into plain sequential code), and `report.Rmd`
   drops its chunks entirely: a short per-step workflow summary plus the
   same provenance/design-choices/results sections it already had.
   `report.html` is faster to render than ever, since there's now no
   code in the `.Rmd` to skip executing — it never had much to run
   anyway (chunks defaulted to `eval=FALSE`), but now there's nothing to
   reason about at all.
2. **A genuine rendering bug, not a design gap this time.** Real forest
   plots showed dashed zero-reference lines running visibly through
   several CI labels — any label whose mean sat close to zero, which is
   common (a lot of studied doses aren't statistically distinguishable
   from placebo). Root cause: `geom_text()` has no background, so
   whatever's drawn underneath — here, `geom_hline(yintercept = 0)` —
   shows through the glyphs. A separate, rarer failure mode was also
   closed: the CI label for the single most extreme point in a plot,
   centered exactly on that point by default, could have its leading
   character (often the minus sign) clipped at the panel edge if the
   axis expansion wasn't wide enough to fit half the label's width
   past the data range. Fixed by switching to `geom_label()` (opaque
   white fill masks the line), widening `scale_y_continuous()`'s
   expansion, and setting `coord_flip(clip = "off")` so an overflowing
   label is never hard-clipped regardless of exact width. Verified
   against a synthetic 26-row plot matching the real dataset's scale —
   the biggest deliverable this skill produces, and the one users
   actually screenshot into decks, so illegible labels were a real
   problem, not a cosmetic one.

