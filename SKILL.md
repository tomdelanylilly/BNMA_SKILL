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
  figures". Also triggers on "/cmh-ci-explain" or a plain request to walk
  through/outline what this workflow does -- that variant only explains the
  steps in plain language and touches no data, file, or folder.
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
Step 1  Introduce and explain the available PRD dataset (always first)
Step 2  Ask which studies you're interested in (named studies and/or
        compounds first, then endpoint/route/evidence/region -- one
        question at a time)
Step 3  Create and review a subset of the PRD data based on those
        selections (naming/pooling flags + study list, grouped confirmation)
Step 4  Ask whether additional, non-PRD data should be incorporated
Step 5  Convert and structure any additional data into the QA format
        (only if Step 4 said yes)
Step 6  Merge the supplemental data with the selected PRD subset
        (only if Step 4 said yes; loops back to Step 4)
Step 7  Confirm whether to proceed to a BNMA run, or stop here (the goal
        may have just been reviewing/updating the data)
Step 8  Generate the BNMA using the prepared dataset (propose folders,
        write the manifest, build the BATMAN data structure)
Step 9  Collect modelling preferences (heterogeneity, effect type,
        no-placebo-arm bridging -- informed by Step 8's real network)
Step 10 Produce analysis outputs and visualisations (fit, forest plot,
        driver script, promote/discard a scratch run)
```

**Do not skip steps or assume defaults on the user's behalf on anything
genuinely discretionary.** The whole point of this skill is that a low-dose
Phase 2 study or an oral/injectable mix-up must never enter a model silently
again. **Step 2's scope items (endpoint, route, evidence, region) are asked
as individual questions, one at a time** — each with a stated, recommended
default so a quick reply is enough, but each is a real question waited on
before the next is asked (2026-08-26, per explicit direction, superseding
an earlier single-consolidated-message design for these items
specifically). Step 3 then presents the naming/pooling flags and the study
list as one grouped confirmation, since those are variable-length and
data-dependent rather than a small closed set of choices — a
study-by-study interview isn't practical on a 70+ study landscape run.
Step 4 adds one more, deliberate checkpoint after that — confirming the
subset is actually sufficient and offering custom data — before anything
is written to disk. Step 7 asks explicitly whether the goal is a full run
at all — some sessions are just about reviewing the data or getting custom
data into QA, and that's a complete outcome, not a shortfall. Heterogeneity
and effect type aren't asked until Step 9, *after* Step 8 has already
built the real network structure — so that question states the actual
recommendation directly instead of asking blind and correcting later.

## `/cmh-ci-explain` — describe the workflow, touch nothing

A distinct, self-contained path for a statistician who wants to understand
what this skill actually does before running it, or wants to explain it to
a colleague — not a shortcut into the workflow itself. Only triggers on an
explicit ask for an explanation of the workflow (literally
`/cmh-ci-explain`, or "what does this skill do," "walk me through the
steps," "what happens if I run this") — never inferred from a data
question like "what's in this data," which is Step 1's own job and does
load real data.

When this fires: **do not** search for a PRD/QA file, run
`run_bnma_pipeline.R`, propose folders, write a
manifest, or touch `compound_registry.yaml` — nothing on this path reads or
writes anything outside this response. Reply with the outline below, then
end the turn. Only move into the real workflow (starting at Step 1) if the
statistician separately says so afterward — nothing carries over from this
explanation, since nothing was touched.

```
1. Show what's actually in the PRD/QA data -- studies, compounds, phases,
   evidence tiers -- before asking for any decision.
2. Ask which studies/compounds you care about, then settle endpoint,
   route, evidence, and region -- one short question at a time, each with
   a stated default.
3. Show the exact study list and any naming/route conflicts as one
   grouped confirmation -- nothing is silently assumed, especially not a
   Phase 1/2 or prediction-tier study.
4. Ask whether that confirmed subset is enough, or whether outside data
   (a press release, a hand-digitized slide, another workbook) should be
   folded in.
5-6. If yes: get that data into the right shape and merge it in, looping
   back to #4 until the subset is confirmed sufficient.
7. Confirm the goal is actually to fit a model at all -- reviewing or
   updating the data can be the whole point of a session, and that's a
   complete outcome on its own.
8. Build the real model input: propose working folders, write a manifest
   recording every decision made so far, build the dataset the model will
   actually see.
9. Now that the real study network is known, recommend random- vs.
   fixed-effects and relative- vs. absolute-effect -- informed by that
   real network, not asked blind.
10. Fit the model, render the forest plot, and write a standalone,
   re-runnable R script -- nothing about reproducing the run depends on
   this chat still existing.
```

Frame it for a statistician, not a developer: what each step asks *them*
to decide and why the decision is forced into the open, not the R/JAGS
mechanics underneath. If they want more depth than this outline (why a
given step exists, what incident it traces back to), point them at
`DESIGN.md` in this skill's repo rather than reproducing that history here.

**The one thing that always still interrupts, even after that reply: a hard
gate failure** — `run_bnma_pipeline.R` refusing to run because a study is
missing from the manifest. Continuing silently past that would defeat the
actual purpose of the skill, not just its UX.

**This skill does not run any automated post-fit diagnostics** (no Rhat/ESS
convergence check, no network-connectivity/consistency/DIC check) — matches
the real production `EliLillyCo/CMH.BNMA` app's own behavior (confirmed
2026-08-24: it fits and plots with no such checks). If a fit's plausibility
needs verifying, inspect the posterior manually (`coda::gelman.diag()`,
`coda::effectiveSize()` on the cached `samples.rds`) rather than expecting
this skill to flag it.

## Step 1 — Introduce and explain the available PRD dataset

Runs at the very start of every trigger, before anything else. This is the
entry experience for someone opening this skill against a folder that
already has PRD/QA data sitting in it (the common case: a statistician's
own project directory) — and, per the team's 2026-08-26 workflow-narrative
discussion (see DESIGN.md's design-iteration history), the mandatory first
stop for *everyone*, whether they already know exactly what they want or
are just asking "what's in this data?" This step never proposes folders,
never asks about custom data, and never *forces* a study-selection
decision before moving on — those firm commitments come later (Steps 2-3,
4, and 8), so someone who only wants to look around never gets dragged into
project setup. It does, however (2026-08-27, per explicit direction),
always list the actual study names and explicitly *invite* a subset
selection right here in 1b — a plain "no, show me everything" is a
complete, valid answer that keeps things in explore mode; the point is that
the real list and the invitation are never withheld or deferred.

**1a. Locate the base dataset — PRD-first.** This step is specifically
about the PRD tier (a newer QA file, if one exists, is Step 4's concern —
"additional, non-PRD data" — not this one). Only ask if the initial prompt
didn't already make this clear:
- **An exact file path was given.** Use exactly what's given — don't guess
  a filename. If the statistician explicitly names a QA file instead of a
  PRD one, that's fine (use it directly), but don't substitute a QA file on
  their behalf when they asked for or pointed at PRD.
- **Both a PRD and a QA path were given together up front.** Load only the
  PRD path here (1b) — same "never merge before Step 4 asks" rule as
  everywhere else in this step — but don't silently drop the QA path
  either: hold onto it and offer it as the stated default answer when Step
  4 asks about additional data, so the statistician isn't asked to repeat
  themselves for something they already told you.
- **No specific file was given** — a working directory was named, or
  nothing was given at all (default to the project's own working
  directory, the common case: a statistician's own project folder). Either
  way, **search that directory for PRD files** — depth-limited (e.g. `find
  <dir> -maxdepth 6 -iname "*.xlsx"` — never a full recursive walk, and
  never a directory that's itself a mount root, see the org's
  filesystem-search policy). **Use `-maxdepth 6`, not a shallower guess** —
  confirmed real case, 2026-08-27: pointed at `/lillyce/prd/diabetes/bnma/`,
  the actual PRD file lived 5 levels down at
  `obesity/data/shared/weight/cwm_wl_nont2d_prd_*.xlsx`; a shallower depth
  (3, used previously) silently found nothing and looked like "no PRD data
  here" when the file was right there, just nested deeper than expected. If
  a depth-6 search still finds nothing, that's a real empty result worth
  reporting as such — don't keep escalating the depth unprompted, ask the
  statistician for a more specific path instead (see below). Match this
  project's own PRD naming convention, not QA's. **Always list every PRD
  candidate found, with modified dates, and get an explicit pick — even
  when only one file looks
  plausible.** Silently choosing "the newest" or "the best name match" is
  exactly the class of silent assumption this skill exists to eliminate
  everywhere else; the directory search finds candidates, it never
  substitutes for confirming which one. Don't ask "where's your data?"
  first when a depth-limited local search can answer it directly — search,
  then present the list for a pick.
- **No PRD files found at all** in the searched directory — say so plainly
  and ask the statistician for a path (or a different directory to search)
  before doing anything else. Don't silently fall back to a QA file here
  even if one is sitting right next to where a PRD file was expected.

**1b. Load & merge, then introduce what's actually in it.** Once the base
dataset is located, materialize Appendix D1/D2 (`_resolve_rscript.sh`,
`run_r.sh` — **not** D3's `run_with_jags.sh`, not needed until Step 10's
JAGS fit) and Appendix B1 (`run_bnma_pipeline.R`) to this session's lib dir
(e.g. `/tmp/$(whoami)/cmh_ci_lib/` before Step 8's folders exist,
`programs/<slug>/lib/` after) if not already done this session, then run:

```bash
scripts/run_r.sh scripts/run_bnma_pipeline.R --prd <prd_path.xlsx>
```

**One call now covers both this step and 1c below** — explore mode always
computes the data summary *and* the naming/pooling report together (see
Appendix B1), since it's the same load+merge either way and there's no
separate script to avoid running a second time anymore. What differs by
run-intent (1c, below) is purely **what you do with the naming/pooling half
of that same output** — surface and propose resolutions now, or hold onto
it quietly until Step 1d's fork resolves to "set up a run." Nothing is
written to disk by this call — everything is read straight from its stdout.

**PRD only here — never pass `--qa` at this step, even if the statistician
happened to name a QA file back in 1a.** Merging QA/custom data in is
Step 6's job, reached only after Step 4 explicitly asks and the
statistician says yes; running it here would pre-empt that question with
data they never confirmed they wanted merged in yet. (When `--qa` is
omitted, the merge branch never executes — `merged <- prd_data` unchanged —
so this is a real behavioral guarantee, not just a documentation nicety.)

**Nothing from this call persists anywhere, on purpose.** The run's real
`programs/YYYYMMDD_<slug>/` folder isn't created until Step 8 (Step 4 has
to confirm the subset is sufficient first), so there's nothing durable to
write yet — and even once it exists, re-running this same call is a cheap,
deterministic re-derivation from the source file(s), never something a
later step depends on having been cached anywhere.

Use its printed summary to give the statistician a real answer to "what's
available here" *before* asking them to decide anything: distinct studies,
compounds, phases, evidence tiers (observed vs. prediction row counts), and
regions present.

**Always list the actual study names, not just a count** (2026-08-27, per
explicit direction — a bare "70 studies" tells the statistician nothing
about *which* studies are actually here, and that's exactly the kind of
gap this skill exists to close). Group the list for readability on a real
landscape run — e.g. by phase and evidence tier ("Phase 3 observed (42):
surmount-1, surmount-4, ... / Phase 1-2 or prediction-tier (11): ...") —
rather than one flat, unscannable list. This is always shown, even when the
initial prompt already named specific studies/compounds.

**Immediately after the list, explicitly ask whether they want to work
with the full set or select specific studies from it** — e.g. "Do you want
to use all of these, or focus on a subset (name the studies/compounds, a
phase, an endpoint, or anything else to narrow by)?" This is a real,
standalone question waited on before continuing, not a line folded into
other text or deferred to a later step. Its answer is what resolves **Step
1d's explore-or-run fork** below:
- A reply naming specific studies/compounds, or asking to narrow by
  phase/endpoint/route/etc., **is** the run signal — 2a below already
  knows how to resolve named studies/compounds against this same list, so
  hand it off there; then 1c's naming/pooling gate should now surface,
  followed by the rest of Step 2.
- A reply like "use all of them," "just show me everything," or a further
  exploratory question instead of narrowing is **not** a run signal — stay
  in Step 1d's exploring branch.

Loading and summarizing the data is never itself the cue to start
surfacing the naming/pooling gate or anything past it — that's this
question's answer to make, not an automatic continuation.

**1c. Naming/pooling QA gate — only surfaced once run-intent is
established.** This gate exists to protect an eventual model fit (route
mix-ups, placebo-naming collisions corrupting the network) — it has no
reason to matter before there's a run in sight. **Check this before doing
anything else in this step:**
- If the initial prompt already signaled run-intent (an endpoint, named
  studies/compounds, a mention of a BNMA/forest plot), surface this gate's
  findings now, as before.
- If it didn't, **resolve Step 1d's explore-or-run fork first** and only
  come back to surface these findings once the answer is "set up a run" —
  never as an automatic mention during pure exploration, even though 1b's
  call already computed them. A reply merely confirming *which file* to
  load (1a's "should I use this file?") — "yes, proceed," "yes," "that's
  the one" — is **not** a run signal; a real session this tripped up had
  exactly that exchange (prompt: "I want to use this skill, how can it help
  me" → file located and confirmed → the correct next stop was still Step
  1d's fork, not a jump straight into surfacing this gate).

Read the naming/pooling report from 1b's own output, but **do not stop
here to resolve flags one at a time** — for every active (non-suppressed)
`compound_flags`/`pooling_flags` entry, work out a proposed resolution to
carry into Step 3's message instead:

- A compound-name flag: propose `different` unless the substring/prefix
  signal is strong (one name is literally a substring of the other — the
  higher-confidence signal), in which case propose `same`.
- A route-pooling collision (identical `treatment` string under two `aom`
  values): propose `split_by_route` — collapsing two genuinely different
  routes into one arm is almost never the intended outcome.

These are proposals the statistician can override in their one reply, not
silent auto-resolutions — Step 3 must show every active flag and its
proposed resolution explicitly. If there are zero active flags, note that
plainly in Step 3's message rather than a separate line here. At this
step, just mention the flag *count* as part of introducing the dataset
(e.g. "…and 2 naming flags to resolve once you pick studies") — full
resolution is Step 3's job.

Once an answer is confirmed (in Step 3), persist compound-name resolutions
to `compound_registry.yaml` (Edit tool, this skill's own repo copy) so the
same pair is never re-flagged; pooling-flag resolutions go in the manifest
only (Step 8), since they're data-specific rather than a general
compound-identity fact. **Skip the `compound_registry.yaml` write entirely
for a scratch run** (Step 4/8) — the resolution still applies to this
run's own manifest, it just isn't remembered for next time, same as every
other artifact a scratch run doesn't persist.

The report also lists `placebo_naming_flags` (Check 4a) — rows where
`compound == "placebo"` but `treatment` isn't literally `"placebo"` (real
case, 2026-08-20: a T2D HbA1c workbook recorded placebo arms as `"oral
placebo qd"`, `"injectable placebo qw"`, `"injectable placebo qd"`, `"placebo
qw"`). This is not cosmetic — `arm_ind` is derived from the treatment string
alone, so each differently-worded placebo row becomes its own disconnected,
single-study network node instead of sharing the one placebo reference arm
every other study anchors to. Propose a `treatment_relabels` entry to
`"placebo"` for each variant in Step 3, same "shown, never silently applied"
treatment as any other naming flag. `run_bnma_pipeline.R`'s build step
hard-errors if a
`compound == "placebo"` row ever reaches arm assignment under a
non-canonical treatment string — the backstop if this proposal is skipped
or missed, not just a style nit.

`no_placebo_flags` (Check 4b) — studies with no `placebo`-**compound** row
at all (computed after accounting for Check 4a's variants, so a study whose
only placebo arm is spelled `"oral placebo qd"` is correctly NOT flagged
here). Carry every flagged study's name into Step 3's list so it's visible
alongside the rest of the study review — the actual bridge-or-leave
decision for these studies happens in Step 9, once `model_type` is known
(only `rand_effect`/`fixed_effect` leave such a study disconnected by
default; see Step 9).

Also flagged (in `integrity_flags`, alongside the existing placebo-mistag
check): `compound == "pbo"` — confirmed 2026-08-20 against the real
production package's own `placebo_name()`, which recognizes exactly
`"placebo"` or `"pbo"` (case-insensitive) as the reference arm. Every check/
filter in this skill's own pipeline keys off `compound == "placebo"`
specifically, and `"placebo"` is excluded from Check 1's own compound-
similarity comparison set — so `"pbo"` previously went completely
unflagged, never compared against `"placebo"` at all, and would have been
silently treated as some unrelated extra compound. Propose a
`compound_relabels` entry (`pbo` → `placebo`) when this fires.

**1d. Explore, or set up a run?** As of 2026-08-27, 1b's own study list
already carries an explicit "use all, or select a subset?" question, so
this fork is normally resolved by that answer, not asked a second time.
Two cases:
- **The initial prompt already named specific studies/compounds** (an
  endpoint, a BNMA/forest-plot mention, "I want ATTAIN-1 vs. SURMOUNT-4")
  — 1b's list is still shown in full for context, but don't re-ask the
  question it already answered; hand off straight to 2a to resolve those
  names against the list, then proceed to Step 2 after the 1b/1c preamble.
- **Otherwise** — wait for the reply to 1b's own question before doing
  anything else in this step.

- **If exploring:** stay conversational. Answer whatever breakdowns they
  ask for — studies by phase, compounds by route, coverage by region, the
  actual list of study names — using 1b's already-loaded data alone. 1c's
  naming/pooling gate has **not** run yet at this point, and shouldn't —
  don't materialize or run it, don't run Step 2's questions or Step 3's
  study confirmation, don't propose folders, don't mention the manifest.
  Naming a subset of studies conversationally here ("let's focus on these
  five") is still exploration, not a run commitment. Only move into the
  guided-selection pipeline once the statistician explicitly signals they
  want to move toward a run (e.g. "ok, let's set up a BNMA using these
  studies").
- **If setting up a run** (whether stated up front or reached from the
  exploring branch above): go back and run 1c's naming/pooling gate now if
  it hasn't run yet this session, then proceed to Step 2.

**If the user attaches a standalone workbook instead of a QA/PRD path**
(confirmed real case, 2026-08-20: `Global_ADA_Oral_KAI7535_*.xlsx`, sheets
named `weight`/`WC` with generic `study_ind`/`arm_ind`/`y`/`se`/`Treatment`/
`Compound`/`Study` columns, not `Observed`/`Prediction` sheets with
`study_name`/`treatment`/`compound`/`aom`/`region`/`pchg_wl_ee`/`se_wl_ee`
columns) — check the actual sheet names and columns with R/readxl **before**
running `run_bnma_pipeline.R` on it. Its sheet-fallback logic
(`read_sheet_with_fallback`, "Observed"/"Prediction" by name — case-
insensitively, fixed 2026-08-20, see below — else positional index 2/3)
will silently misread an arbitrary sheet as "Observed" and silently drop
any sheet beyond position 3 if the workbook doesn't use that naming at all
— exactly the kind of silent, undetected data error this skill exists to
prevent, and worse than asking, because it looks like it worked.

**A workbook using the standard schema but with lowercase (or otherwise
differently-cased) sheet names is a related but distinct trap, found in a
real T2D HbA1c workbook, 2026-08-20** — sheets literally named
`observed`/`prediction` (correct schema, wrong case) with an unrelated
`chinese population` sheet sitting between them. Exact-case matching missed
both, and the positional fallback for "Prediction" landed on `chinese
population` (position 3) instead of the real `prediction` sheet (position
4), silently mislabeling China-specific data as the prediction tier while
the real prediction data was never read at all. Fixed generally in
`read_sheet_with_fallback` (case-insensitive name matching, tried before any
positional fallback) — so a same-schema workbook with differently-cased
sheet names is now read correctly without an adapter. The positional
fallback is now reached only when a workbook truly has no `Observed`/
`Prediction`-named sheet at all (any case) — e.g. the standalone-workbook
case above — where the same silent-misread risk still applies and still
needs the adapter approach, not a further loosening of the fallback.

If the schema doesn't match, don't force it through 1b. Instead:
1. Write a small one-off adapter script (save it as `adapt_standalone.R`
   next to this run's manifest, not in `/tmp` — Step 10's driver script needs
   a permanent path to call it from) that maps the file's own columns into
   the shape `run_bnma_pipeline.R`'s build step expects: lowercase +
   `squish_ws()` `study_name`/`treatment`/`compound`; derive
   `aom`/`region`/`source_sheet` from context (e.g. a study name containing
   "Prediction" → `source_sheet = "prediction"`, else `"observed"`); keep
   the file's own effect/SE column names as-is — no need to rename to
   `pchg_wl_ee`/`se_wl_ee`, the manifest's `effect_col`/`se_col` can name
   whatever columns actually exist. Save the result as an `.rds`.
2. Feed that `.rds` into `run_bnma_pipeline.R` via `--data <adapted.rds>`
   (instead of `--prd`/`--qa`) at every step from 1c onward — explore,
   build-preview, and fit modes all accept it as a substitute for their own
   load+merge, exactly as if it were that step's own output.
3. In the manifest, put the adapter script's path in `source_program` and
   the original workbook's path in `source_data.prd` (not a custom key) —
   `make_forest_plot.R`'s footnote only reads `source_data.prd/qa` and
   `source_program`, so a custom key silently prints "(not recorded)"
   instead of the real path.

Also: a manifest's `effect_col`/`se_col` value of literally `y` or `n` must
be quoted (`effect_col: "y"`) — bare `y`/`n`/`yes`/`no`/`on`/`off` parse as
YAML 1.1 booleans, not strings, and `run_bnma_pipeline.R` fails with a
confusing "effect_col 'TRUE' not found" error. Same root cause as the
`row_exclusions` `"n"` gotcha documented under Step 8.


## Step 2 — Ask which studies you're interested in

**2a. Study/compound-first entry point (if requested).** If the initial
prompt already named specific studies, compounds, or treatments (e.g. "I
need these 21 treatments," "I want ATTAIN-1 vs. SURMOUNT-4," "compare
ATTAIN-1 to what we have on tirzepatide"), resolve them now, silently where
unambiguous:

- **Named studies** — match each requested name against the merged data's
  actual `study_name` values, case/punctuation-insensitively (e.g. "attain
  1" and "ATTAIN-1" should match the same row) — same fuzzy-match mechanism
  Step 1c already uses for compound names. Report exact matches plainly;
  for anything without a clean match, surface the closest candidates and
  ask rather than guessing which study was meant. A named study still goes
  through Step 3's full enumeration like every other study — naming it
  up front sets the *proposed* decision to "include, per your request" (with
  that as the stated reason), it doesn't skip the confirmation. This
  matters most for phase 1/2 studies: naming one by name **does** count as
  an explicit decision (the statistician said so directly), so it doesn't
  need a *second* ask — but it still must appear in Step 3's list with its
  reason shown, same visibility guarantee as everything else, not silently
  dropped from the enumeration.
- **Named compounds/treatments** — match each requested string against the
  merged data's actual `treatment` values (report exact matches plainly;
  for anything without an exact match, use edit-distance/substring
  candidates, same mechanism as Step 1c). A missing dose suffix (e.g.
  "Tirzepatide 5mg" vs. "tirzepatide 5mg qw") is usually resolvable without
  asking. **Only a genuine ambiguity still needs its own question** — e.g.
  "X Pooled" that doesn't correspond to any single row in the source data
  needs an explicit decision (which single arm to use, or whether to
  compute a genuinely new derived value); never invent one silently, but
  don't manufacture a question where the match is actually clear either.
- **A named comparison** ("I have a list to compare," "X vs. Y") — resolve
  both sides the same way (study and/or compound matching above), and carry
  the resolved list forward as the proposed `plot_treatments` default for
  Step 10's forest plot, in addition to driving Step 3's study list.

Derive the distinct compound list from the resolved treatments and carry it
into Step 3 as the proposed `compound_filter` (a list of compound names).
`run_bnma_pipeline.R`'s build step applies this as a **study-level** filter (corrected
2026-08-26 — see the script's own comment for the real run that surfaced
this): a study qualifies only if at least one of its rows has a wanted
compound, and a study mixing a wanted compound with an unwanted one keeps
only its wanted-compound rows (plus its own placebo row). A study with
**none** of the requested compounds is dropped entirely, including its
placebo row — "I want these 5 compounds" means the studies those compounds
actually appear in, not every study's placebo row across the whole
dataset. Only studies that qualify (or are ambiguous — see below) need
enumerating in Step 3; a study with no requested compound is simply out of
scope, not a decision to make.

If the initial prompt did not name specific studies or compounds, propose
the default in Step 3: every study/treatment surviving the other filters,
in the order first
seen.

**2b. Scope questions (one at a time).** Per explicit 2026-08-26 direction,
these are not bundled into one wall-of-text message — ask each as its own
short question, one at a time, and wait for a reply before asking the next.
Each names its recommended default in the same message so a quick
"yes"/"default" reply is enough, but each is a genuine question the
statistician answers before you move to the next — not a line item in a
bundled ask. Fill in every value from the actual data/report; never leave a
placeholder.

1. **Endpoint** — e.g. "This looks like a weight-loss dataset (`effect_col:
   pchg_wl_ee`, `se_col: se_wl_ee`) — is that the endpoint you want, or a
   different one?" **Only state it plainly instead of asking** when the
   dataset's own columns unambiguously match a known schema *and* the
   initial prompt already made the endpoint clear — otherwise always ask,
   since this determines `effect_col`/`se_col`/`effect_label`/
   `effect_direction` for everything downstream. For any endpoint other
   than weight loss (HbA1c, physical function, etc.), state the real
   column names in the question itself — e.g. "HbA1c (`effect_col:
   chg_hba1c`, `se_col: se_chg_hba1c`) — sound right?" — and also propose
   an `effect_label` (a short phrase for the plot's axis/title) and, if
   `placebo_clamp` might be used this run, an `effect_direction`
   (`decrease_is_better` | `increase_is_better` — weight loss and HbA1c
   reduction are `decrease_is_better`; a physical-function score where
   higher is healthier would be `increase_is_better`).
2. **Route** — "Oral, injectable, or both?" State the default (usually
   "both," if the data has both routes present).
3. **Evidence** — "Observed only, prediction only, or both?"
4. **Region** — "Global only, or include `<other regions actually found in
   the data>`?"

Once all four are answered, echo the locked-in scope back in one line
before moving to Step 3. (Heterogeneity and effect type are asked later, in
Step 9, once the real network structure is known — see that step for why.)

## Step 3 — Create and review a subset of the PRD data based on those selections

Present everything computed in Step 1c and Step 2, filtered by Step 2b's
now-confirmed scope, as **one message** — this part stays a grouped
confirmation rather than one question per item, since the naming/pooling
flags and the study list are both variable-length and data-dependent
(potentially dozens of studies on a real landscape run), not a small closed
set of choices like Step 2b's items:

```
╭──────────────────────────────────────────────────────────────────╮
│  /cmh-ci · study confirmation                                     │
├──────────────────────────────────────────────────────────────────┤
│  Reply with just what you want to change, plus anything else to   │
│  flag -- everything else proceeds on the default/proposal shown.  │
╰──────────────────────────────────────────────────────────────────╯

  SCOPE (confirmed in Step 2b)
   Dataset <path(s)> -- Endpoint <effect_col>/<se_col> -- Route <route> --
   Evidence <evidence> -- Region <region>

  NAMING / POOLING  (N active flags)
   - <compound_a> vs <compound_b> -- proposed: <same|different>, because <signal>
   - <treatment string> under two routes -- proposed: split_by_route
   [or: "No naming/pooling flags found."]

  STUDIES  (X total)
   - Y phase 3 observed  -- proposed: include all
   - Z phase 1/2 / prediction-tier -- YOUR CALL, no default assumed:
       <study_name> (<phase>, <data_type>) -- proposed reason if you accept: <reason>
       ...

  STUDIES WITHOUT A PLACEBO ARM  (N found, informational -- whether this
  matters depends on the model type chosen in Step 9; the bridge/leave
  decision itself happens there, once that's known)
   - <study_name> (<treatments in this study>)
     ...
```

Notes:
- **Phase 1/2 and prediction-tier studies never get a silent proposed
  decision baked into the default path** — list each one individually and
  require the statistician to actually say include or exclude, even though
  everything else above is a normal accept-the-default item. (A *proposed
  reason* is fine to show for when they do decide to include one, per Step
  8's manifest schema — the decision itself is never pre-filled.)
- **Studies without a placebo arm are surfaced here for visibility, but the
  decision is deferred to Step 9** — whether it matters at all depends on
  `model_type`, which isn't chosen until then. Listing them now means the
  statistician isn't surprised by a new list appearing later; the actual
  "bridge or leave disconnected" call happens in Step 9, once `model_type`
  is known.
- End with an open invitation: "anything else to flag — a study you know
  about that should be excluded, a data-quality concern, a specific
  treatment format — say so now or after the fact; I'll fold it in before
  Step 8."
- Echo back exactly what was locked in (Step 2b's scope answers + this
  step's defaults accepted/overrides + any free-form concerns folded in)
  once the statistician replies, before moving to Step 4's sufficiency
  check. Folder proposals and the Project CLAUDE.md offer are **not** part
  of this ask — those wait for Step 8, which only runs once Step 7 has
  confirmed the statistician actually wants a BNMA run, not just to
  review/update the data (Step 1d covers the earlier, no-run-signal-at-all
  version of that same fork).

## Step 4 — Ask whether additional, non-PRD data should be incorporated

This is the checkpoint the team's workflow discussion added: study
selection is confirmed (Step 3), but nothing has been written to disk yet.
One more message, in reply to the statistician's Step 3 answer:

```
╭──────────────────────────────────────────────────────────────────╮
│  /cmh-ci · subset confirmed -- anything else before we run?       │
├──────────────────────────────────────────────────────────────────┤
│  Locked in: <one-line recap of Step 3's confirmed scope + study   │
│  count>.                                                          │
╰──────────────────────────────────────────────────────────────────╯

  Is this subset sufficient, or is there external/custom data (a press
  release, a new readout, a hand-digitized slide, a subset from another
  workbook) you'd like added before running? Reply "add data" to bring
  something in (Steps 5-6) -- otherwise this proceeds straight to Step 8.
```

Notes:
- **If the statistician wants to add custom/external data**, go to Step 5,
  then come back to this same sufficiency question once it's merged in
  (Step 6) — loop until they confirm the subset (base + any custom
  additions) is actually sufficient.
- **If sufficient with no custom data**, proceed straight to Step 8.

## Step 5 — Convert and structure any additional data into the expected QA format

Only runs if Step 4's answer was "add data." Per the team's discussion (see
DESIGN.md's design-iteration history): PRD is only updated on a
semi-annual cadence, so most custom data belongs to one project, not the
shared tier — see Step 6 for how that plays out in the merge itself. This
step is just about getting the data into the right shape:

1. **Get the new data.** Accept it in any of three forms:
   - **Pasted into the prompt** — rows given inline (study, treatment,
     compound, y, se, etc.). Parse into a data.frame matching the QA
     schema; fill as many columns as possible from context (`aom`, `phase`,
     `data_type`, `source`), leave the rest NA (optional metadata columns
     like `curator_note`, `qc_name` are routinely blank in real QA files).
   - **A file path** (xlsx, csv, rds) — read it and extract the relevant
     rows. If the schema doesn't match QA (e.g. a standalone workbook with
     `Study`/`Treatment`/`y`/`se` columns instead of `study_name`/
     `treatment`/`pchg_wl_ee`/`se_wl_ee`), map the columns into the QA
     schema the same way the standalone-workbook adapter does (Step 1's
     note).
   - **A subset of another file** — "take the X data from this dataset."
     Read that file, filter to the named studies/treatments, map into QA
     schema if needed.

2. **Show the user exactly what rows will be added** — a table with all
   populated columns, same confirmation gate as any other data-affecting
   decision in this skill:
   - `study_name`, `treatment`, `compound`, this run's `effect_col`/`se_col`
     values
   - `aom`, `phase`, `data_type`, `source` (if known)
   - A `reason` (why this data is being added — matches
     `supplementary_data`'s own required field, see Step 8).

Once the rows are confirmed, proceed to Step 6 to actually merge them.

## Step 6 — Merge the supplemental data with the selected PRD subset

1. **Default: add as `supplementary_data` in this run's manifest.** These
   rows flow through the entire normal pipeline exactly as documented under
   Step 8's `supplementary_data` field (row_exclusions, relabels,
   `placebo_clamp`, `route_filter`/`compound_filter`/`region_filter` all
   apply) — nothing new to build, this is the existing fallback mechanism
   promoted to the default path for genuinely new/custom data. No shared
   file is touched; a scratch run's own `/tmp` manifest carries it exactly
   the same way a persisted run's `programs/<slug>/manifest.yaml` does.

2. **Offer to promote instead (or in addition).** State plainly: "if you
   want this saved to the shared QA file so future runs see it too, reply
   'promote to QA' — otherwise this stays with this run only." If accepted,
   follow the QA-append path:
   - **Identify the corresponding QA file.** Convention:
     - PRD at `/lillyce/prd/diabetes/bnma/obesity/data/shared/weight/
       cwm_wl_nont2d_prd_YYYYMMDD.xlsx`
     - → QA at `/lillyce/qa/diabetes/bnma/obesity/data/shared/weight/
       cwm_wl_nont2d_qa_YYYYMMDD.xlsx`
     - (Swap `/prd/` → `/qa/` in the directory path; `_prd_` → `_qa_` in
       the filename. Same date suffix, same `wl`/`t2d`/`nont2d` segment.)
     - If the user already provided a QA path, use it directly — don't
       guess.
     - **If the QA file doesn't exist yet:** ask the user whether to
       create it (with the PRD's own column schema — sheets
       `Observed`/`Prediction`, same columns, zero data rows) or to
       provide a different path. **Never auto-create silently** — this is
       a write to a shared drive with no version control.
     - Sometimes the QA file exists but is empty (just headers) — that's
       the normal "waiting for entries" state, not an error.
   - Add `time_entry` = today's date to the rows shown in Step 5 (the
     QA schema's own "when was this entered" field — only relevant once
     something is actually going to QA).
   - **Ask the user to confirm the write.** A clear "I'll append these N
     rows to `<qa_path>`, sheet `<sheet>` — confirm?"
   - **Once confirmed: append rows to the QA xlsx in-place** via
     `append_to_qa.R` (see Appendix B). The script reads the existing
     workbook, appends to the target sheet, writes back. No backup copy
     (the mount has no version control anyway — but the manifest records
     exactly which rows were added and when, so the audit trail is the
     manifest + `time_entry`, not file versions).
   - **Show an append summary:** N rows added, which studies, which sheet,
     total rows now in that sheet.
   - The promoted rows still also flow into this run via
     `supplementary_data` (or a re-run of Step 1b's load against the
     updated QA file, if simpler) — promoting to QA is about *future* runs
     seeing it, not a substitute for this run actually using it.

3. **Re-run the naming/pooling checks (`run_bnma_pipeline.R`, explore mode) against the combined data right
   away** — newly-added data is precisely when a naming collision or route
   mismatch is most likely (a new study using a slightly different
   spelling for an existing compound, or the wrong `aom` tag). Surface any
   new flags in a short follow-up, resolved the same way Step 1c/3 resolve
   any other flag — don't silently skip this just because Step 3's main
   naming/pooling pass already happened.

4. **Loop back to Step 4's sufficiency question.** The statistician may
   want to add more data, or confirm the (now-enlarged) subset is
   sufficient and move on to Step 7.

## Step 7 — Confirm whether to proceed to a BNMA run

Per explicit direction: the subset is confirmed sufficient (Steps 4-6 are
done, looping back to Step 4 as needed), but nothing has established that
the statistician actually wants to *run* anything yet. Their goal might
genuinely stop here — reviewing what's in the PRD data, or getting their
own data added to QA — without ever wanting a fitted model or a forest
plot this session. Ask plainly, in reply to however Step 4 resolved:

```
Subset confirmed: <one-line recap — dataset, scope, study count, any
custom data merged in>.

Ready to move on to a BNMA run — folders, manifest, model fit, forest
plot? Or was the goal for this session just to review/update the data
(e.g. getting your own data added to QA)? Either is a complete outcome.
```

- **If the goal was just reviewing/updating the data:** end the turn here.
  Summarize plainly what happened this session (e.g. "reviewed the
  weight-loss subset: 42 studies in scope" / "added 3 rows to QA as
  discussed" / both) — there's nothing further to do, and nothing about
  folders, a manifest, or a model fit should be mentioned. This is
  functionally the same ending as Step 1d's "exploring" branch, just
  reached later — after real study selection and possibly a real QA
  promotion — rather than before any of that happened. Both are legitimate,
  complete sessions; neither is a failure to reach Step 8.
- **If ready to run:** proceed to Step 8 normally.

This is a distinct checkpoint from Step 1d's explore-or-run fork — Step 1d
catches someone who shows no run signal *before* any work happens; this
step catches the case where run-intent looked clear at the start but the
statistician's actual goal for the session turns out to be narrower once
they've seen the data and made their selections. Don't skip this step by
assuming the initial prompt's apparent intent still holds — ask, the same
way every other genuinely discretionary point in this workflow asks rather
than assumes.

## Step 8 — Generate the BNMA using the prepared dataset

**8a. Propose the run's `programs/` and `output/` folders — rooted under
QA, not PRD — don't create them yet.** PRD is the curated,
semi-annual-cadence read tier; QA is the live working copy, so an
analyst's own `programs/`/`output/shared/` work products belong there, not
mixed into the PRD directory tree (confirmed 2026-08-26 — a real run
defaulted to wherever the PRD file happened to sit and nested them under
`/lillyce/prd/.../weight/programs/...`, which was wrong). Work out the
QA-rooted base directory, in this priority order:
1. **A QA path is already known this session** (held onto from 1a's "both
   a PRD and QA path given together" case, or an actual QA file identified
   during Step 4-6) — use that file's own directory.
2. **Otherwise, derive it from the PRD path** (Step 1a) by swapping `/prd/`
   → `/qa/` in the directory portion — the same convention Step 6 already
   uses to find the corresponding QA file.
3. **If neither applies** (e.g. a personal project directory, or a
   standalone workbook with no PRD/QA tier structure at all) — don't guess
   a QA-shaped path. Ask the statistician directly where
   `programs/`/`output/shared/` should live for this run, same as any
   other genuinely discretionary location choice.

Once the base is known, work out a proposed `<slug>` and both paths under
it — `<qa_root>/programs/YYYYMMDD_<slug>/` /
`<qa_root>/output/shared/YYYYMMDD_<slug>/` — and a Project CLAUDE.md offer,
in one message:

```
  Working folders  ► <qa_root>/programs/YYYYMMDD_<slug>/,
                      <qa_root>/output/shared/YYYYMMDD_<slug>/
                      (not yet created; reply "scratch" for a /tmp-only dry run)
  Project CLAUDE.md ► skip (default for a single run) -- reply "add CLAUDE.md"
                      if this is a larger/ongoing project
```

- `<slug>` is your best guess at a short, meaningful label for this run,
  derived from the dataset/endpoint (e.g. `cwm_wl_nont2d`, `ada_oral_full`);
  if nothing obvious presents itself, propose your best guess rather than
  leaving it blank.
- **Replying "scratch" or "dry run" instead of accepting/renaming the
  folders** keeps the whole run in `/tmp/$(whoami)/bnma_scratch_<slug>/` —
  `manifest.yaml`, the JAGS cache, and the forest plot all land there
  instead of `programs/`/`output/shared/`, Step 1c's naming resolution is
  never written to `compound_registry.yaml`, and Step 10's driver script is
  skipped in favor of an explicit promote-or-discard offer. Everything else
  about the run — the fit, the plot, the footnote — is identical either
  way.
- **Project CLAUDE.md defaults to skip** — most runs are a single,
  self-contained ask and don't need one. Accept "add CLAUDE.md" (or
  anything that signals this is a bigger/ongoing initiative — a conference
  submission, a project the statistician says they'll keep coming back to)
  at face value rather than second-guessing it. If accepted, Step 10 writes
  it alongside the driver script.

**8b. Create the folders and write the manifest.** Apply everything
confirmed in Steps 2-6. Create `<qa_root>/programs/YYYYMMDD_<slug>/` and
`<qa_root>/output/shared/YYYYMMDD_<slug>/` (`<qa_root>` per 8a's derived or
stated base, `<slug>` per 8a's confirmed or renamed value, dated with
today's date) — now that the statistician has seen and confirmed the name
and confirmed the subset is sufficient. Everything from here on (manifest,
naming report, cached samples) writes into `<qa_root>/programs/<slug>/`;
forest plots go into `<qa_root>/output/shared/<slug>/` (Step 10).
**The merged dataset (Step 1b's load+merge) never moves in
from `/tmp`** — per the workflow guide, the PRD+QA merge happens in code
and leaves no separate merged file on the share; re-deriving it from the
source file(s) is cheap and deterministic, so there's nothing worth
persisting. Then write a YAML manifest capturing everything from Steps
2-6 — this is the traceable artifact that replaces a commented-out R
vector. Example shape:

**Scratch run:** skip folder creation entirely. Create one directory,
`/tmp/$(whoami)/bnma_scratch_<slug>/`, and write `manifest.yaml` there instead — same
content, same schema below, only the destination differs. Steps 9/10 point
their own outputs at this same directory (see each step).

```yaml
created_at: "2026-08-14"
source_data:
  prd: /lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_20260805.xlsx
  qa: null
effect_col: pchg_wl_ee # from Step 2b's Endpoint question -- the QA/PRD column holding this run's effect estimate; omit = pchg_wl_ee (weight loss), unchanged for every existing manifest
se_col: se_wl_ee # from Step 2b -- the matching SE column; omit = se_wl_ee (weight loss), unchanged for every existing manifest
effect_label: "Body Weight" # optional -- short phrase for the plot's default axis/title text (e.g. "HbA1c", "Physical Function Score"); omit = "Body Weight" only when effect_col is pchg_wl_ee, else falls back to the raw effect_col name (unpolished but not wrong) -- --xlab/--title on make_forest_plot.R always override regardless
effect_direction: decrease_is_better # decrease_is_better | increase_is_better -- from Step 2b, only matters if placebo_clamp is used; controls which sign placebo_clamp treats as "wrong direction". omit = decrease_is_better (weight loss/HbA1c-reduction convention), unchanged for every existing manifest
source_program: <path to whatever script/session produced this run>
route_filter: both # oral | injectable | both -- from Step 2b; omit or "both" = no route filtering
evidence_filter: both # observed | prediction | both -- from Step 2b; omit or "both" = no evidence filtering
compound_filter: null # optional list of compound names -- from Step 2a's compound-first entry point; omit/null = no compound filtering
region_filter: [global] # list of regions to include -- from Step 2b; omit = ["global"] only, unlike route/evidence_filter's "both" default
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
placebo_clamp: false # optional -- set true to force any placebo row's wrong-direction (per effect_direction) effect_col value to 0; requires placebo_clamp_reason
se_fallback: false # optional -- set true to derive se_col = se_fallback_sd/sqrt(n) for rows missing se_col but with a known n; requires se_fallback_reason
supplementary_data: [] # optional -- literal rows for data not yet in the QA/PRD workbook; see below
model_type: rand_effect # rand_effect (recommended default for new runs) | fixed_effect | simultaneous (legacy) | simultaneous_fixed (legacy, fixed-effect delta -- use instead of simultaneous whenever effect_type: absolute + a full star network, see Step 9) -- from Step 9; omit or "simultaneous" = today's unconditional phantom-bridging behavior, unchanged; see Step 9
plot_treatments:
  - tirzepatide 5mg qw
  - tirzepatide 10mg qw
  - tirzepatide 15mg qw
effect_type: relative # from Step 9
```

`compound_relabels` is for a naming-QA flag resolved as "these rows were
mislabeled, merge into the canonical spelling" -- applied globally by
compound string. `treatment_relabels` is the same idea but for the
`treatment` string itself (changes which arm a row maps to, not just which
compound it's attributed to). `row_exclusions` is for a single anomalous or
duplicate row within an otherwise-included study; add `"n"` (quoted) when
two rows share the same `(study_name, treatment)` and need a third field to
tell them apart.

**`placebo_clamp`** forces any placebo row reporting a "wrong direction"
`effect_col` value to 0 before fitting — for the `decrease_is_better` default
(weight loss, HbA1c reduction) that means a positive (e.g. weight-*gain*)
value; for an `increase_is_better` endpoint it's the mirror, a negative
value. Found in a real analyst script (`bnma-nonadj-11AUG2026.R`, applied
unconditionally there with no traceability, and without an
`effect_direction` concept at all since it only ever ran on weight-loss data
— "Yongming advised setting the placebo effect to zero"). Opt-in and
reasoned here like everything else in this manifest: absent means no
clamping (today's behavior, unchanged). Setting `placebo_clamp: true`
without a non-blank `placebo_clamp_reason` is a hard error — this rewrites
an arbitrary number of rows' values across the whole run, so (unlike a
single `row_exclusions` entry) it needs a documented reason, not just a
logged default:
```yaml
placebo_clamp: true
placebo_clamp_reason: "Placebo arms occasionally report a small positive
  (noise-driven) value; forced to 0 per <analyst>'s guidance on this run,
  not treated as a real placebo effect."
```

**`se_fallback`** derives `se_col = se_fallback_sd / sqrt(n)` for any row
missing `se_col` but with a known arm sample size `n` — rescuing a row the
unusable-row filter would otherwise silently drop. This is a real, repeated
team convention for the weight-loss endpoint specifically, not a one-off
(unlike `placebo_clamp`, which stays a per-run judgment call): `redefine1`'s
own `curator_note` documents the exact formula ("se is calculated with
10/sqrt(n) where sd=10 is commonly used for %change in body weight in
nont2d"), and it's actually applied — not just written down — in
`brenipatide_gzmu_misc5.R` and `brenipatide_gzmu_gzmd.R`. The default
`se_fallback_sd: 10` reflects that weight-loss-specific convention — a
different endpoint's own team convention (if one exists) needs its own
`se_fallback_sd`, not this one reused by default. Still opt-in and still
requires a reason, same hard-error pattern as `placebo_clamp` — fabricating
an SE is always a visible, deliberate choice for a given run, never a silent
default:
```yaml
se_fallback: true
se_fallback_reason: "redefine1's own curator_note documents this exact
  derivation but never applied it -- applying it here to include a large
  Phase 3 study that would otherwise be dropped for a missing SE."
se_fallback_sd: 10  # optional, default 10 -- the team's stated standard
                     # assumption for %change in body weight in nont2d;
                     # override with a different value (and document why)
                     # for any other endpoint -- this default is NOT a
                     # generic statistical constant, it's specific to that
                     # one convention.
```

**`phantom_placebo_studies`** opts specific no-placebo studies into
BATMAN's phantom-placebo bridging (`se=1, y=NA`) even when `model_type` is
`rand_effect`/`fixed_effect` — those two model types leave a no-placebo
study disconnected from the network by default (matching the real
production tool's own behavior; `model_type: simultaneous` already bridges
every no-placebo study unconditionally, unaffected by this field). A real,
recurring judgment call (confirmed 2026-08-20, comes up "in some analyses" —
e.g. an isolated head-to-head trial that would otherwise sit outside the
network entirely), not a one-off — every study listed here must be one
Step 1c's `no_placebo_flags` actually found, Step 3 surfaced for visibility,
and Step 9 turned into an explicit per-study decision;
`run_bnma_pipeline.R` errors on an unrecognized study name (spelling
mismatch against `study_name`) rather than silently ignoring it. Same
hard-error-if-no-reason pattern as `placebo_clamp`/`se_fallback` — a phantom
placebo row is a fabricated, zero-information data point, so bridging one in
is always a visible, deliberate choice, never a silent default either
direction:
```yaml
phantom_placebo_studies: [oral hrs9531 ph2 china to global prediction]
phantom_placebo_reason: "Head-to-head-only trial with no placebo arm --
  bridging it in so its two dose arms connect to the rest of the network,
  per analyst's request 2026-08-20."
```
Omit or leave empty (the default) — every no-placebo study stays
disconnected, contributing a baseline (`phi`) estimate only, no
relative-effect information. This is still a stated decision from Step 9,
not a silent fallthrough, even when nothing is listed here.

**Phantom-bridging a fully isolated *multi-node* component can still fail
to converge, even after a large iteration increase — that's a real
possibility, not just a hypothetical.** Found 2026-08-20 on a real T2D
HbA1c landscape run: two studies (`duration6`, a 2-node isolated pair;
`pioneer plus`, a 3-node isolated triangle) had zero connection to the main
72-node network. Phantom-bridging both produced hard non-convergence on
manual inspection (`coda::gelman.diag()` Rhat 8.3–36, `coda::effectiveSize()`
6–10) — refitting with 5x the adaptation/burn-in/
iterations *did not fix it*, it just moved which node looked worst. Root
cause: the phantom placebo's `se=1` is a very weak anchor, and when the
bridged component's own treatments are themselves single-study nodes with
no other anchor either, the model ends up only weakly identifying that
whole component's absolute position relative to the rest of the network —
a real statistical property of the model+data, not slow mixing that more
iterations resolves. Bridging a *single disconnected study* whose
treatments already have other real network connections is the well-behaved
case this feature was originally built for; bridging a study that is
itself the *entire* isolated component is a materially different, weaker
case. If non-convergence persists after a substantial iteration increase
(not just the first refit) following a phantom bridge — check manually,
since this isn't caught automatically — treat that as a signal to
fall back to excluding the study/studies rather than continuing to push
iterations — surface this explicitly rather than silently excluding, since
it reverses an already-confirmed decision.

**`supplementary_data`** is for a small, deliberately-curated addition that
hasn't been promoted into the QA/PRD workbook yet — e.g. a hand-digitized
dose-response series pulled from a slide deck, the same situation
`bnma-nonadj-11AUG2026.R` handles by `bind_rows()`-ing a hand-typed tibble
straight into its analysis with no traceability at all. **This is the
default destination for custom/external data brought in via Steps 5-6** —
temporary and project-scoped by design (PRD/QA are the team's shared,
persistent tiers; this manifest field is this run's own). The row can still
be promoted to a real QA row later (Step 6's "promote to QA" option, or
the project CLAUDE.md's Flow 1) once it's ready for the whole team to
reuse — but that's opt-in, not required. Each entry requires `study_name`,
`treatment`, `compound`, this run's `effect_col`/`se_col` values, and
`reason`; `aom`/`region` are optional:
```yaml
supplementary_data:
  - study_name: "GZMD+GZMU"
    treatment: "brenipatide 8mg q4w"
    compound: brenipatide
    pchg_wl_ee: -13.86 # key name must match this manifest's own effect_col (pchg_wl_ee here, since it's the default)
    se_wl_ee: 0.26      # key name must match this manifest's own se_col
    aom: injectable
    reason: "Hand-digitized from GZMU_MISC5_Unblinded.pptx (Aug 2026 data
      cut) -- not yet entered as a QA row."
```
These rows flow through the entire normal pipeline (row_exclusions,
relabels, `placebo_clamp`, `route_filter`/`compound_filter`/`region_filter`
all apply exactly as they would to any other row) — the only exemption is
`evidence_filter`, since "supplementary" isn't a meaningful point on the
observed/prediction axis; these rows always survive regardless of that
filter's setting. The originating `study_name` still needs its own explicit
entry under `studies:`, same as any other study — no exemption from the
completeness check just because the data was hand-added.

**Any study lacking a literal placebo row gets a phantom placebo arm
(SE=1, y=NA) injected automatically — but only when `model_type` is
`simultaneous` (the legacy hierarchical model) or omitted.** Matches
`efficacy_bnma_v3_gzmu_misc5.R`'s own logic exactly, and this is not
something the skill second-guesses or gates on a per-study decision for that
model. For `model_type: rand_effect`/`fixed_effect` (the recommended
defaults for new runs — see Step 9), **no bridging happens at all**: a study
with no placebo row simply doesn't connect to the network. This isn't a gap
— it's confirmed, documented real-tool behavior (see Step 9), unlike the
earlier connectivity-aware bridging attempt this skill tried and reverted
mid-session for having no such documentation anywhere.

Save it into `programs/<slug>/` (created moments ago, above), e.g.
`study_selection_manifest.yaml`.

**Every study found in Step 1's merged data must appear under `studies:`.**
`run_bnma_pipeline.R`'s build step (below) enforces this itself and will
refuse to run otherwise — that's intentional, not a bug to work around.

**8c. Build-preview: confirm the manifest is complete and see the real
network.** Materialize Appendix D1/D2 (if not already done) and Appendix
B1 (`run_bnma_pipeline.R`, if not already done this session — it's the
same file 1b already materialized), then run in **build-preview mode** —
`--manifest` given, no `--model` yet:

```bash
scripts/run_r.sh scripts/run_bnma_pipeline.R \
  --prd <prd_path.xlsx> --manifest <manifest.yaml>
```

No `rjags`/`run_with_jags.sh` needed for this call — it loads+merges,
applies the manifest, builds the BATMAN matrices, prints the
heterogeneity-estimability check (feeds Step 9's question), and exits
without writing anything to disk. **Nothing from this call is reused
later** — Step 10a's fit re-derives everything fresh, in the same process
as the fit itself, once `model_type` is actually known (see that step for
why: reusing a build artifact across the Step 9 boundary would silently
carry stale phantom-placebo-bridging decisions if `model_type` changes).

If this errors because studies are missing from the manifest, that's the
intended guard — go back to steps 2-7 with the user, don't patch around it.

Any study left with only one arm after all filtering/exclusion (route,
evidence, compound, row_exclusions, study include/exclude) is dropped
automatically, with a log line naming which — matches the real production
package's own defensive behavior (confirmed 2026-08-20: `prepare_model_data()`
"Drop studies with only one arm, JAGS requires at least 2 arms per study").
Not a crash risk in this skill's own model files (JAGS's `for(j in 2:na[i])`
is a bounded loop that runs zero times when `na[i]<2`, unlike R's own `:`
operator — a real single-arm study converged fine in testing, 2026-08-20),
but it's dead weight (a `phi[i]` baseline node with zero relative-effect
information) not worth carrying into the fit or its convergence scoring.

## Step 9 — Collect modelling preferences

`run_bnma_pipeline.R`'s build step (Step 8c) also prints a **heterogeneity estimability**
check — for every non-placebo treatment node, how many distinct studies
feed it. Because this step now runs *after* the dataset is finalized and
the network structure is actually known, the heterogeneity and effect-type
questions below can state the real recommendation directly — no "ask blind,
then correct after the fact" needed, unlike this same pair of questions
under the old step ordering.

**9a. Heterogeneity.** If the check reports a **star network** (zero nodes
with ≥2 contributing studies — the exact situation in `pf_nma.R`, a
physical-function sub-network where every comparison has exactly one
supporting study), between-study heterogeneity literally cannot be
estimated from the data, and `model_type: fixed_effect` is the appropriate
primary analysis, not a stylistic preference — quote `pf_nma.R`'s own
rationale ("with only 1 study per comparison, between-study heterogeneity
cannot be estimated; fixed-effects is the appropriate primary analysis").
Ask plainly, stating the real finding as the reason for the recommendation:
- The network is a full star (every non-placebo node has exactly 1
  contributing study).
- `sigma` (between-study heterogeneity) cannot be estimated from the data
  and will be entirely prior-driven if random-effects is used — this
  inflates every CI with a ~4-point SD on top of the arm's own reported SE
  (documented in the `kai7535_bnma_v3.R` comparison, 2026-08-20).
- Recommend `fixed_effect`, but proceed with `rand_effect` if the user
  explicitly says so (e.g. as a sensitivity analysis, or because they want
  the inflated CIs to reflect genuine uncertainty about heterogeneity even
  when it can't be estimated).

When the network isn't a full star (some nodes have multi-study support,
even if most don't — this is the common case for the obesity landscape
data, where dozens of single-study nodes coexist with a handful of
well-replicated ones), heterogeneity is estimable from the network as a
whole; state the default as `rand_effect` (recommended for new runs),
surface the node counts for information, and let `rand_effect` vs.
`fixed_effect` be the analyst's own call, same as always.

**9b. Effect to report.** "Placebo-adjusted (relative), or absolute?" **The
same star-network finding from 9a applies here too, on
`model_simultaneous.txt`/`model_simultaneous_fixed.txt`** — a full star
means `model_simultaneous_fixed.txt` is recommended (deterministic delta)
whenever `effect_type: absolute` is requested on that network, but if the
user explicitly wants `model_simultaneous.txt` after being informed,
proceed with it and note the CI-inflation risk in the footnote.

Which model file to use is driven by the answers to 9a/9b — pass the
matching file to Step 10's fit:
- `model_type: rand_effect` (recommended default for new runs) →
  `--model model_random.txt`
- `model_type: fixed_effect` → `--model model_fixed.txt`
- `model_type: simultaneous` (legacy) or omitted → `--model
  model_simultaneous.txt`
- `model_type: simultaneous_fixed` (legacy, fixed-effect delta) → `--model
  model_simultaneous_fixed.txt` — use this instead of `simultaneous` whenever
  `effect_type: absolute` is requested **and** the network is a full star.

**9c. No-placebo-arm studies (only if 9a lands on `rand_effect`/
`fixed_effect`; skip this entirely if Step 3's list was empty).** Those two
model types leave a no-placebo study disconnected from the network by
default, matching the real production tool's own behavior (`model_type:
simultaneous` already bridges every no-placebo study unconditionally,
unaffected by this decision). Carry every study from Step 3's list into an
explicit, no-silent-default ask here — propose "leave disconnected" (the
default, and the one that matches production behavior) but require an
explicit per-study answer, not a blanket accept, same treatment as a phase
1/2 study got in Step 3.

**Do NOT auto-correct anything from an earlier turn.** Because heterogeneity
and effect type are both asked here, after Step 8c's real network structure
is known, there's no earlier answer to reconcile — state the recommendation
and let the statistician confirm or override it once, directly.

## Step 10 — Produce analysis outputs and visualisations

**10a. Fit the model.** Fit (or load a cached fit of) the model in the same
call as the build — **fit mode** is `run_bnma_pipeline.R` with both
`--manifest` and `--model` given; it re-derives the BATMAN matrices fresh
(same as 8c's build-preview, cheap) before fitting, so there's no
`--batman-in`/intermediate file to hand off and no risk of fitting against
a build that predates the `model_type` decided in Step 9. **Must go through
the JAGS wrapper** — plain `Rscript` will fail to load `rjags` in this
environment. Materialize Appendix D (wrappers, if not already done) — no
new R script to materialize, `run_bnma_pipeline.R` is the same file 1b/8c
already wrote — then run:

```bash
scripts/run_with_jags.sh scripts/run_bnma_pipeline.R \
  --prd <prd_path.xlsx> --manifest <manifest.yaml> --model model_random.txt \
  --out <programs_folder>/model_output.rds --cache <programs_folder>/samples_<run_name>.rds
```
**Scratch run:** point both `--out`/`--cache` at
`/tmp/$(whoami)/bnma_scratch_<slug>/` instead.

**Which model file to use is driven by the manifest's `model_type` field**
(from Step 9) — pass the matching file here:
- `model_type: rand_effect` (recommended default for new runs) →
  `--model model_random.txt`
- `model_type: fixed_effect` → `--model model_fixed.txt`
- `model_type: simultaneous` (legacy) or omitted → `--model
  model_simultaneous.txt`
- `model_type: simultaneous_fixed` (legacy, fixed-effect delta) → `--model
  model_simultaneous_fixed.txt` — use this instead of `simultaneous` whenever
  `effect_type: absolute` is requested **and** the network is a full star
  (per Step 9's heterogeneity-estimability check).

**MCMC settings and chain initialization follow the real production
package's own documentation** (`EliLillyCo/CMH.BNMA`, provided 2026-08-20 —
supersedes the NMA Output Review Process Guide-derived settings this skill
used before) — n.adapt 10,000, burn-in 10,000, 20,000 sampling iterations
thinned by 10 (3 chains), with chain 1 initialized to exactly 0 on
the baseline (`phi`, and `m` for `model_simultaneous.txt`/
`model_simultaneous_fixed.txt`) and
treatment-effect (`d`) nodes and chains 2–3 drawing from those same nodes'
own vague priors (Normal(0, SD=100)) — all built into `run_bnma_pipeline.R`
itself, nothing to configure per run. Override via `--n_adapt`/`--n_burnin`/
`--n_iter`/`--thin` if a specific run needs more (e.g. after manually
inspecting the posterior and finding it under-mixed).


`model_random.txt`/`model_fixed.txt` are copied verbatim from the real
production BNMA Shiny app (`BNMA_forest_plot-main.zip`, confirmed
2026-08-17) — non-hierarchical `phi[i]~dnorm(0,0.0001)` baseline per study
(the "separate model per Dias 2013" the NMA Output Review Process Guide
already said was the team's stated standard), `sigma~dunif(0,8)`. The app's
own UI defaults to the random-effect model, which is why this skill now
does too. `run_bnma_pipeline.R` infers which variables to monitor from the
`--model` value — no extra flag needed, and every existing driver
script that already passes `--model model_simultaneous.txt` explicitly
keeps working unchanged.

`model_simultaneous.txt` (hierarchical/pooled baseline, `sigma~dunif(0,8)`,
corrected 2026-08-19 to match the NMA Output Review Process Guide's explicit
spec for this parameter) stays as a legacy option — it's the only one with a
pooled baseline `m` node, which is required if you need `effect_type: absolute`
(see Step 9b); the real production tool has no absolute-effect view at all,
since a non-hierarchical model has no single global baseline to compute one
from.

**On a full star network, `model_simultaneous.txt` will hugely inflate every
credible interval — use `model_simultaneous_fixed.txt` instead.** Found by
testing (2026-08-19, the ADA oral compounds run — 21 treatments, every
non-placebo node single-study): fitting `model_simultaneous.txt`'s *random*
`delta[i,j]~dnorm(..., tau2)` on a star network produced CIs like
orforglipron 6mg's -8.3 (95% CrI -18.1, 1.6) — nearly 20 points wide, versus
that arm's own reported SE of 0.306. Root cause: with zero studies per node,
`sigma` (delta's between-study SD) has no replication to estimate it from and
is almost entirely prior-driven (posterior mean landed ~3.9, prior
`dunif(0,8)`) — that ~4-point SD gets added on top of every arm's own much
smaller trial SE. This is the exact same "fixed-effect is the objectively
correct choice for a star network" argument already used above for
`rand_effect`→`fixed_effect`; it applies equally to `model_simultaneous.txt`'s
own delta structure. `model_simultaneous_fixed.txt` pairs the same
hierarchical/pooled `phi`/`m` (still needed for the absolute-effect baseline)
with a **deterministic** `delta[i,j]` (no `sigma`, same pattern as
`model_fixed.txt`'s own delta block) — refitting the same data with this file
tightened that same orforglipron 6mg arm to -8.4 (95% CrI -9.3, -7.5), tracking
its own reported SE as expected. **Whenever `effect_type: absolute` is
requested on a full-star network, recommend `model_simultaneous_fixed.txt`
over `model_simultaneous.txt`** — same "inform the user and let them decide"
rule as `rand_effect`→`fixed_effect` above (recommend fixed, but honour
their explicit choice if they want random after being warned). `make_forest_plot.R`'s absolute-effect subtitle
reports `τ` (`sigma`) when it exists and says so plainly when it doesn't
(either this fixed-effect model, or an older cache predating `sigma`
monitoring) rather than guessing which.

**Independently reconfirmed 2026-08-20** against `kai7535_bnma_v3.R`, a real
hand-written team script (found in the shared output tree this skill writes
to) fit on this exact same ADA-oral dataset. That script always uses a
`model_random.txt`-equivalent spec (independent `phi[i]~dnorm(0,0.0001)`,
`sigma~dunif(0,8)`, one global `sigma` shared across every study-arm
deviation) with no star-network check at all. Result: point estimates
matched this skill's fixed-effect fit almost exactly (e.g. orforglipron 6mg
-6.8 vs. this skill's -6.9), but every single one of its 18 d-node CIs came
out ~20-22 points wide regardless of that arm's own reported SE (0.3-2.1) —
the uniform width across arms of wildly different precision is the
tell-tale sign of one global, prior-dominated `sigma` swamping every
interval, not real data-driven heterogeneity. This is the same mechanism as
the `model_simultaneous.txt` finding above, just via `model_random.txt`'s
structurally equivalent single-global-`sigma` delta instead — confirming
that a hand-written random-effects script run on a full-star network,
whichever model file it happens to use, will produce this same inflation,
and that this skill's auto-correction to fixed-effect (or
`model_simultaneous_fixed.txt`) is the one that actually tracks the source
data's own precision.

**10b. Pooled-placebo model (only for `effect_type: absolute`).**
`effect_type: absolute`'s pooled baseline comes from a separate,
standalone pooled-placebo model — not the main model's own `m`/`phi[i]`
nodes at all. Adopted 2026-08-20 from the real production package's own
pooled-placebo feature (`EliLillyCo/CMH.BNMA`,
`pooled_placebo_model_utils.R`), superseding a 2026-08-19 fix that averaged
`phi[i]` across only the studies with a real placebo arm from
`model_simultaneous.txt`'s own fit. That fix was correct in spirit (a
no-placebo study's `phi[i]` is purely a hierarchical-prior artifact with
nothing real anchoring it — two such studies had `phi[i]` of -15 and -25
against every real-placebo study's -3 to +1, dragging the naive `m`-based
pooled baseline from a plausible ~-2% to an implausible -5.9%), but it was
architecturally coupled to one specific legacy model file. A genuinely
independent fit that only ever sees placebo data is cleaner, and — the
actual payoff — it means `effect_type: absolute` now works with **any**
`model_type`, including `rand_effect`/`fixed_effect` (the real production
relative-effect models, which have no pooled baseline of their own at all
and previously couldn't support an absolute view for exactly that reason).

**No separate script call** — add `--fit-placebo --placebo-cache
<placebo_samples.rds> --placebo-out <placebo_data.rds>` to 10a's own fit-mode
command. It runs against the same in-memory `arm_rows` that call already
built (no `arm_rows.rds` hand-off file needed):
```bash
scripts/run_with_jags.sh scripts/run_bnma_pipeline.R \
  --prd <prd_path.xlsx> --manifest <manifest.yaml> --model model_random.txt \
  --out <programs_folder>/model_output.rds --cache <programs_folder>/samples_<run_name>.rds \
  --fit-placebo --placebo-cache <programs_folder>/placebo_samples_<run_name>.rds \
  --placebo-out <programs_folder>/placebo_data_<run_name>.rds
```
Then pass `--placebo-samples <placebo_samples.rds>` to `make_forest_plot.R`
alongside `--effect absolute`. MCMC settings for this model are its own,
lighter budget (n.adapt 1,000, burn-in 5,000, sampling 10,000, thin 10) —
matching the production package's own settings for this specific model, not
the main model's canonical 10k/10k/20k/10 (see 10a's MCMC settings note).
Stops with an error if fewer than 2 studies have a usable placebo arm — same
identifiability problem as the main model's own star-network check, just for
`sigma_m` instead of `sigma`: with 1 study, there's no between-study
variance to estimate at all.

**Recommended: also render the pooled-placebo model's own QC plot**, so a
reviewer can see the model is sane rather than trusting the number blind —
10c's own forest plot only ever *consumes* `m`/`sigma_m`, it never shows the
underlying per-study shrinkage. Same script as 10c, with `--qc-plot`:
```bash
scripts/run_r.sh scripts/make_forest_plot.R \
  --model-output <model_output.rds> --manifest <manifest.yaml> \
  --qc-plot <placebo_forest_plot.png> --placebo-data <placebo_data.rds> \
  --placebo-samples <placebo_samples.rds>
```
Shows each contributing study's observed vs. posterior-shrunk placebo effect,
the pooled `m`, and the predictive `mu_new` for a hypothetical new study —
adapted 2026-08-21 from a colleague's independent implementation
(`godwill-bnma` branch), which itself mirrors the production app's own
`placebo_forest_plot()`. Not a numbered pipeline step (nothing downstream
consumes its output) — render it whenever `effect_type: absolute` is used,
same "always do this, don't wait to be asked" expectation as 10d's driver
script.

The plot's subtitle reports the pooled baseline (`μ`, with its own 95% CrI
and the placebo model's own between-study `σ`) and `τ` (the between-study SD
of the *relative* treatment effect — `sigma` from the MAIN model, not the
placebo model's `sigma_m` — per the user's explicit convention), so a
reviewer sees the method, not just the number.

**This is a modelled, shrunk placebo level, not any single trial's observed
placebo** — footnote it as such (this caveat, from a colleague's parallel
`atlas` skill's `model_spec.md`, applies equally to our own exchangeable-
baseline model) so it isn't mistaken for a directly-observed value.

Give the cache file a run-specific name (per the workflow doc's "cached MCMC
samples are expensive to regenerate, version-specific name" rule) — don't
reuse another run's cache path. For a scratch run this is the *only* copy
of the fit (not just pre-Step-7 scratch space) — don't let anything delete
`/tmp/$(whoami)/bnma_scratch_<slug>/` until the statistician decides promote or
discard (10e).

**10c. Forest plot + footnote.**

Materialize Appendix B3 (`make_forest_plot.R`) to this run's lib dir if not
already done this session, then run:

```bash
scripts/run_r.sh scripts/make_forest_plot.R \
  --model-output <programs_folder>/model_output.rds --samples <cache.rds> \
  --manifest <manifest.yaml> \
  --effect relative --out <output_folder>/forest_plot.png
```

**The footnote is no longer rendered on the plot image itself** (per
2026-08-27 request — the plot ships clean, no caption). The script still
prints the footnote text to the console — surface that back to the user so
they have a traceability record in the chat transcript, even though it's not
on the PNG. `--model-output` carries `arm_rows` as part of its bundle (built
into every fit-mode run by default now, not an opt-in flag), so the printed
footnote breaks "Contributing studies" out **per treatment** — e.g.
`semaglutide: surmount-1, surmount-4` on its own line — rather than one
flat list for the whole plot, so a reviewer can tell which studies fed
which specific estimate. Without it (older driver scripts), the footnote
falls back to the old flat, plot-wide list. Either way it also includes the
source data path(s) and source program. Save the plot into the matching
dated `output/shared/YYYYMMDD_.../`
folder, not next to the manifest in `programs/`.

**Scratch run:** `--out /tmp/$(whoami)/bnma_scratch_<slug>/forest_plot.png` instead.
**Display the image itself either way** (Read tool, same as 10d already
requires for the driver script) — a scratch run's entire point is seeing
the result, just without persisting it.

Every plotted treatment label carries a superscript marking its evidence
type — `°` for observed, `ᵖ` for projection, `°ᵖ` for an arm fed by both
(e.g. a shared placebo arm) — so a reviewer QC'ing the PNG can tell which
arms are real trial data vs. modeled without cross-referencing the manifest.
A one-line legend ("° = observed, ᵖ = projection") is appended to the
console-printed footnote automatically — not on the image itself, since the
footnote is no longer rendered there (see above).

**Never produce both `--effect relative` and `--effect absolute` "for
completeness" unless the user explicitly asked, or the manifest states
`effect_type: both`** — this doubles unrequested output, and the absolute
view needs its own footnote caveat (see 10b's "modelled, shrunk placebo
level" note) that's easy to skip if it wasn't deliberately asked for
(cherry-picked from `atlas`'s own anti-pattern table, 2026-08-19).

**Layout and color palette (aligned 2026-08-19 to the team's own T2D forest
plot reference):** each row's value label sits directly above its own point
(nudged along the treatment axis), not in a fixed side column, and
`Compound` (capitalized) is the legend title, not the aes name. Colors are a
fixed, named palette (`FIXED_COMPOUND_COLORS` in `make_forest_plot.R`) for
the compounds the reference plot showed — `semaglutide`, `cagrisema`,
`maritide`, `retatrutide`, `berobenatide`, `tirzepatide`, `placebo` — so
runs plotting any of these line up with that convention exactly. Any other
compound falls back to `generate_fallback_colors()` (RColorBrewer `"Set3"`,
darkened 0.3, extended via `colorRampPalette` beyond 12 compounds) rather
than erroring or rendering blank — matches the real production package's
own `generate_color_palette()` (confirmed 2026-08-20, `EliLillyCo/CMH.BNMA`
`R/plot_utils.R`, used by that package's own BNMA-results forest plot
specifically — checked call sites directly: that package's dose-*shaded*
`build_color_map()` turned out to feed an unrelated raw-data bar chart, not
its forest plot, so it was deliberately not adopted here). Extend
`FIXED_COMPOUND_COLORS` as more of the team's own conventions are confirmed,
don't just hardcode a one-off run's colors elsewhere.

**10d. Generate the driver script.**

**Applies to persisted runs only.** For a scratch run (Step 4/8), skip this
part entirely — a driver script pointing at `/tmp` paths that vanish on
reboot isn't reproducible, so there's nothing useful to generate yet. End
the turn instead with the promote-or-discard offer in 10e.

**Do this for every persisted run, without being asked — a run is not
finished until this step happens and its output is shown.** Found by a
colleague testing this skill (2026-08-20, twice in one session, `godwill-bnma` branch): once a
plot is on screen it's easy to treat the turn as done and skip straight to
summarizing results — this step was silently dropped entirely on one run,
and even after being reinstated, the next run wrote the file but never
displayed it. Both are the same failure: the user has no R code to inspect,
audit, or re-run unless it's actually shown to them. **Immediately after
writing the driver script, use the Read tool (or otherwise print) its full
contents back to the user in the same turn — a "driver script written to
`<path>`" message with no code shown does not satisfy this step.**

Once the manifest-driven run is finished (BATMAN built, model fit, plot(s)
rendered) and the user is happy with the plot, write a driver script into
the same dated `programs/YYYYMMDD_.../` folder, e.g. `run_bnma_<slug>.R`,
that reproduces the run from scratch as a **fully standalone, self-contained
R script** — no `system2()`, no `source()` to skill scripts, no dependency
on `.claude/skills/` being installed. A colleague with just R + JAGS can
`Rscript run_bnma_<slug>.R` and reproduce the entire run without this skill,
without Claude Code. This matches the team's own convention
(`kai7535_bnma_v3.R`, `efficacy_bnma_v3_misc8.R`, `BNMA_sex.R`).

The skill's own scripts are used **internally during the session only** to
run gates and catch problems interactively. The standalone script is the
frozen, already-validated result that comes out the other end.

**Structure (mandatory, matching the real team convention):**

1. **Lilly SOH header** (the standard `#/*soh*...` block):
   - CODE NAME: `programs/YYYYMMDD_reason/run_bnma_<slug>.R`
   - PROJECT NAME: `<plot title or run description>`
   - DESCRIPTION: `BNMA for <endpoint> — <N> treatments from <N> studies`
   - DATA INPUT: `<source xlsx path(s)>`
   - OUTPUT: `output/shared/YYYYMMDD_reason/<plot filenames>`
   - REVISION HISTORY: `1.0  Generated by bnma skill  Original version`

2. **Libraries** — `rm(list=ls())` then:
   `library(dplyr)`, `library(rjags)`, `library(readxl)`, `library(ggplot2)`,
   `library(stringr)`, `library(coda)`, `library(magrittr)`

3. **CONFIG block** — all editable knobs as plain variables at the top:
   - `out_dir` — points to the `output/shared/YYYYMMDD_reason/` folder
   - `data_file` — source Excel path
   - `EXCLUDED_STUDIES` — named character vector of studies to exclude (can
     be empty `c()` if all included)
   - `PLACEBO_VARIANTS` — character vector of placebo subgroup labels to
     consolidate into "Placebo" (e.g. `c("Placebo (pseudo)", ...)`)
   - `inits.list` — 3-chain Wichmann-Hill seeds

4. **JAGS model** — written inline via `cat('model{...}', file = model_path)`
   where `model_path <- file.path(out_dir, "model_flat.txt")`. The exact
   model text for this run, verbatim — NOT read from an external file.

5. **`run_nma()` helper function** — takes `(data_subset, rds_tag)`, returns
   `list(BNMA_out, arm_info)`. Internally:
   - Filters out `EXCLUDED_STUDIES`, consolidates `PLACEBO_VARIANTS`
   - Drops existing `study_ind`/`arm_ind`, re-derives from unique lists
     (Placebo forced to arm_ind 1)
   - Builds BATMAN matrices with explicit for-loops (the team's style)
   - **RDS caching**: `if (file.exists(rds_path)) readRDS() else { fit; saveRDS() }`
   - Returns `list(BNMA_out = data.frame(node, mean, val2.5pc, val97.5pc), arm_info)`

6. **`make_forest()` helper function** — takes `(res, trt_levels, plot_file)`:
   - Joins arm_info to BNMA_out, filters/orders by `trt_levels`
   - Colour map from sorted compounds (alphabetical → reference palette)
   - `geom_pointrange(aes(col=Compound))` + `coord_flip()` +
     `geom_text(label, vjust=1.6, size=4.5)`
   - Font sizes: axis 18pt, title 14pt bold, legend 18pt
   - No caption on the plot itself (matches the interactive session's own
     make_forest_plot.R — see Step 10c) — trace the run via the manifest and
     this script's own header instead.
   - `ggsave(width=14, height=max(8, 0.45*n_trts+2), dpi=150)`

7. **Read data + call helpers** — `read_excel() %>% rename(study=Study, treat=Treatment)`,
   optionally merge supplementary `.rds` via `bind_rows()`, then call
   `run_nma()` and `make_forest()` one or more times (e.g. "without X" then
   "with X").

**What the standalone script does NOT include** (by design):
- The naming/pooling QA check (resolved during the session)
- Any `system2()` or `source()` to the skill's own scripts
- Any dependency on `.claude/skills/` existing

Fill in every value from the actual run — no `<...>` placeholders left. It
must be directly `Rscript run_bnma_<slug>.R`-runnable with no editing.

**If Step 8a's Project CLAUDE.md item was accepted**, write
`programs/<slug>/CLAUDE.md` in the same turn as the driver script, and show
its contents too (same "must be shown, not just written" rule). Populate it
entirely from the manifest and Steps 3/9a's answers already in hand — this is
not a new round of data collection:

```markdown
# <slug>

<one-line purpose -- from Step 3's free-form context if the statistician
gave one, else derived from the endpoint/dataset, e.g. "Weight-loss BNMA,
oral compounds, for the ADA submission">

## Data
- Source: <manifest source_data.prd path> [+ <source_data.qa path>]
- Endpoint: <effect_col> / <se_col>
- Filters: route=<route_filter>, evidence=<evidence_filter>, region=<region_filter>

## Key decisions
- model_type: <model_type>, decided in Step 9 with the real network structure already known
- Studies excluded: <list + reasons, from manifest, or "none">
- Naming/pooling resolutions: <list, from manifest, or "none">

## Re-running
See `run_bnma_<slug>.R` in this folder — reproduces the fit and plot from
scratch. Full decision record: `manifest.yaml`.
```

**10e. Promoting (or discarding) a scratch run.**

For a scratch run, end the turn with an explicit summary instead of 10d's
driver script:

> **SCRATCH RUN** — nothing written to `programs/`, `output/shared/`, or
> `compound_registry.yaml`. Artifacts are in `/tmp/$(whoami)/bnma_scratch_<slug>/` and
> won't survive a reboot. Reply **promote** to write this exact run for
> real, or just move on and it's discarded automatically.

**If the statistician replies "promote":**
1. Create `programs/YYYYMMDD_<slug>/` and `output/shared/YYYYMMDD_<slug>/`
   now (same naming Step 8 would have used had this not been a scratch
   run).
2. Copy `manifest.yaml` and `samples.rds` from `/tmp/$(whoami)/bnma_scratch_<slug>/`
   into `programs/<slug>/`; copy `forest_plot.png` into
   `output/shared/<slug>/`. **No refitting** — a scratch run's outputs are
   byte-identical to what a persisted run would have produced, since
   nothing in Steps 1-6 branches on where the file ends up, only on what
   path gets passed. Promoting is a filesystem operation, not a re-run.
3. If Step 2 held back a naming-registry resolution for this run, persist
   it now (Edit tool → `compound_registry.yaml`) — it's no longer a
   throwaway decision.
4. Run Step 8 for real: generate and show the driver script.

This is also the answer to "I want to redo this without documenting a
failed attempt" — a scratch run *is* that undocumented iteration space.
Nothing about a discarded scratch run needs mentioning again; there is no
partial artifact on the shared drive to explain away, unlike a persisted
run that turned out wrong.

## Utilities (not numbered pipeline steps)

**`make_forest_plot.R --contrast`** — resolves a contrast between two
treatments by name from an already-fitted run, instead of a hardcoded
posterior index (the exact anti-pattern this replaces, seen in real analyst
code: `TZP15_vs_Sema72 <- d[18] - d[89]`, silently wrong if treatment order
ever shifts). Cherry-picked from `atlas`, 2026-08-19; folded into
`make_forest_plot.R` (Appendix B3) as a mode rather than its own file
(consolidated 2026-08-27). No new script to materialize:
```bash
scripts/run_r.sh scripts/make_forest_plot.R \
  --model-output <model_output.rds> --samples <cache.rds> --manifest <manifest.yaml> \
  --contrast "<treatment name 1>|||<treatment name 2>"
```
Use whenever a specific head-to-head comparison is needed from a run that's
already been fit — not part of the numbered pipeline above.

## Non-goals

- No external grounding (ClinicalTrials.gov/INN lookups) for the naming
  check — string-similarity + same-study disconfirmation + a persisted
  registry only.
- Does not touch `/home/l138303/BNMA` (an unrelated LLM-extraction/curation
  app project that happens to share the name).
- ~~No absolute-effect view for `model_type: rand_effect`/`fixed_effect`~~
  — **no longer true, superseded 2026-08-20.** The standalone pooled-placebo
  model (Step 10b's `run_bnma_pipeline.R --fit-placebo`, adopted from
  `EliLillyCo/CMH.BNMA`) supplies the baseline independently of the main
  model, so `effect_type: absolute` now works with every `model_type`
  including `rand_effect`/`fixed_effect`. `BNMA_forest_plot-main.zip`'s own
  lack of an absolute view (confirmed 2026-08-17) reflected that *older*
  reference tool specifically, not a structural limitation of
  `model_random.txt`/`model_fixed.txt` — CMH.BNMA (the newer, preferred
  reference — confirmed 2026-08-20) has one via this separate model.
- No automated post-fit diagnostics — no Rhat/ESS convergence check, no
  network-connectivity/consistency/DIC check (removed 2026-08-24, matching
  `EliLillyCo/CMH.BNMA`'s own behavior). A fit's plausibility is on the
  analyst to verify by hand if there's reason to doubt it.

---

## Appendix A — JAGS Model Text (reference documentation)

These are the exact model definitions this skill uses. **This is reference
documentation only, not something a step instructs you to materialize** —
the operative copy of every one of these lives as an R string constant
(`MODEL_TEXTS`) inside Appendix B1's `run_bnma_pipeline.R`, passed to
`jags.model()` via `textConnection()` at fit time, so no `model_*.txt` file
is ever written to disk during a session (consolidated 2026-08-27 — see
Appendix B's intro). In the standalone driver script (Step 10d), the model
text is still written inline via `cat('...', file = model_path)`, matching
the team's own existing convention for a script meant to run outside any
Claude session.

### A1. Random-effects, flat baselines (DEFAULT — `model_random.txt`)

Use for: placebo-adjusted forest (the standard deliverable). Production default.

```jags
model{
    for(i in 1:ns){
        phi[i]~dnorm(0.0, 0.0001)
    }
    for(i in 1:ns){
        for(j in 1:na[i]){
            y[i,j]~dnorm(eta[i,j], 1/se[i,j]^2)
            dev[i,j] <- (y[i,j]-eta[i,j])*(y[i,j]-eta[i,j])*(1/se[i,j]^2)
        }
        devstudy[i] <- sum(dev[i,1:na[i]])
    }
    for(i in 1:ns){
        eta[i,1]<-phi[i]+delta[i,1]
        for(j in 2:na[i]){
            eta[i,j]<-phi[i] + delta[i,j]
        }
    }
    for(i in 1:ns){
        w[i,1]<-0
        delta[i,1]<-0
        for(j in 2:na[i]){
            delta[i,j]~dnorm((d[trt[i,j]]-d[trt[i,1]])+sw[i,j], tau2d[i,j])
            tau2d[i,j]<-tau2*2*(j-1)/j
            w[i,j]<-delta[i,j]-d[trt[i,j]] + d[trt[i,1]]
            sw[i,j]<-sum(w[i,1:(j-1)])/(j-1)
        }
    }
    Dbar <- sum(devstudy[])
    d[1]<-0
    for(k in 2:M){
        d[k]~dnorm(0,1e-04)
    }
    sigma~dunif(0,8)
    sigma2<-sigma*sigma
    tau2<-1/sigma2
}
```

### A2. Fixed-effect, flat baselines (`model_fixed.txt`)

Use for: star networks where sigma can't be estimated, or as sensitivity check.
Only difference from A1: `delta[i,j]` is deterministic (`<-`), not stochastic (`~dnorm`).

```jags
model{
    for(i in 1:ns){
        phi[i]~dnorm(0.0, 0.0001)
    }
    for(i in 1:ns){
        for(j in 1:na[i]){
            y[i,j]~dnorm(eta[i,j], 1/se[i,j]^2)
            dev[i,j] <- (y[i,j]-eta[i,j])*(y[i,j]-eta[i,j])*(1/se[i,j]^2)
        }
        devstudy[i] <- sum(dev[i,1:na[i]])
    }
    for(i in 1:ns){
        eta[i,1]<-phi[i]+delta[i,1]
        for(j in 2:na[i]){
            eta[i,j]<-phi[i] + delta[i,j]
        }
    }
    for(i in 1:ns){
        w[i,1]<-0
        delta[i,1]<-0
        for(j in 2:na[i]){
            tau2d[i,j]<-tau2*2*(j-1)/j
            delta[i, j] <- (d[trt[i, j]]-d[trt[i, 1]])+sw[i, j]
            w[i,j]<-delta[i,j]-d[trt[i,j]] + d[trt[i,1]]
            sw[i,j]<-sum(w[i,1:(j-1)])/(j-1)
        }
    }
    Dbar <- sum(devstudy[])
    d[1]<-0
    for(k in 2:M){
        d[k]~dnorm(0,1e-04)
    }
    sigma~dunif(0,8)
    sigma2<-sigma*sigma
    tau2<-1/sigma2
}
```

### A3. Random-effects, exchangeable/pooled baselines (`model_simultaneous.txt`)

Use for: absolute-effect forest (`m + d[k]`). Has `m`, `sigma_m`, `mu_new`.

```jags
model{
    for(i in 1:ns){
      phi[i] ~ dnorm(m, tau2_m)
    }
    m ~ dnorm(0, 1e-04)
    tau2_m   <- 1 / sigma2_m
    sigma2_m <- sigma_m * sigma_m
    sigma_m  ~ dunif(0, 8)

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
        delta[i,j] ~ dnorm((d[trt[i,j]] - d[trt[i,1]]) + sw[i,j], tau2d[i,j])
        tau2d[i,j] <- tau2 * 2 * (j-1) / j
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
    tau2   <- 1 / sigma2
    mu_new ~ dnorm(m, 1 / sigma_m^2)
}
```

### A4. Random-effects baseline, fixed-effect delta (`model_simultaneous_fixed.txt`)

Use for: absolute-effect forest on a full-star network (see Step 9b/10a) —
same hierarchical/pooled `phi`/`m` as A3 (still needed for the
absolute-effect baseline), but with A2's **deterministic** `delta[i,j]`
instead of A3's stochastic one, so a star network's CIs track the arms' own
reported SE instead of an unreplicated, prior-driven `sigma`. Not present
as a standalone file in this branch's history before 2026-08-27 — every
place that referenced it described the composition (A3's baseline + A2's
delta block) without ever spelling out the resulting text; reconstructed
here from that description, now embedded directly in `run_bnma_pipeline.R`
(Appendix B1).

```jags
model{
    for(i in 1:ns){
      phi[i] ~ dnorm(m, tau2_m)
    }
    m ~ dnorm(0, 1e-04)
    tau2_m   <- 1 / sigma2_m
    sigma2_m <- sigma_m * sigma_m
    sigma_m  ~ dunif(0, 8)

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
        delta[i,j] <- (d[trt[i,j]] - d[trt[i,1]]) + sw[i,j]
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
    tau2   <- 1 / sigma2
    mu_new ~ dnorm(m, 1 / sigma_m^2)
}
```

### A5. Pooled-placebo meta-analysis (`model_placebo_random.txt`)

Use for: estimating the overall placebo effect + predicting a new study's placebo.

```jags
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
}
```

---


## Appendix B — R Scripts (embedded, no external files needed)

These are the exact, tested scripts this skill's pipeline runs. During the
session, materialize whichever ones a step needs to a real file (e.g.
`/tmp/$(whoami)/cmh_ci_lib/<name>.R` before Step 8's folders exist,
`programs/<slug>/lib/<name>.R` after) via `cat('...', file = <path>)`, then
invoke it exactly as shown in the step that references it.

**Just two scripts cover the entire modeling/plotting pipeline** — B1
`run_bnma_pipeline.R` (load → naming/pooling check → build BATMAN → fit,
all in one file, mode-selected by which flags are passed) and B3
`make_forest_plot.R` (plot / QC-plot / named-contrast, same one-file,
mode-selected shape). This replaces what used to be nine separate files
(`lib_common.R`, `load_merge_data.R`, `check_naming_pooling.R`,
`build_batman_data.R`, `fit_bnma_model.R`, `fit_pooled_placebo_model.R`,
`make_forest_plot.R`, `make_placebo_forest_plot.R`, `named_contrast.R`) —
consolidated 2026-08-27 because running each pipeline stage as its own
subprocess (re-loading R packages, re-reading the workbook, re-running
`module load jags`) made even a simple run take 6-7 separate invocations.
The five embedded JAGS model definitions (Appendix A) are now R string
constants inside `run_bnma_pipeline.R` itself, passed to `jags.model()` via
`textConnection()` — there's no more separate "materialize
`model_random.txt` to a file first" step; Appendix A is reference
documentation only now, not something a step instructs you to write to
disk.

`append_to_qa.R` (B2) stays its own small file — it's Step 6's rare
promote-to-QA path, not part of the modeling/plotting hot path, and mixing
a shared-Excel-file write into either of the two consolidated scripts would
tangle unrelated concerns for a rarely-invoked feature.

### B1. `run_bnma_pipeline.R`

Three modes, selected by which arguments are given — covers Steps 1b/1c
(explore), 8c/9 (build-preview), and 10a/10b (fit):

- **explore** (no `--manifest`): load + merge PRD/QA, run every naming/
  pooling check, print the data summary + naming report to stdout, exit.
  Never touches `rjags` — doesn't need the `jags` module loaded, so use
  `run_r.sh`, not `run_with_jags.sh`.
- **build-preview** (`--manifest`, no `--model`): re-loads+merges (cheap,
  deterministic — nothing from explore mode is reused or cached), applies
  every manifest field, builds the BATMAN matrices, prints the
  heterogeneity-estimability check, then **exits without fitting or writing
  anything** — this call exists purely so Step 9's model-type question can
  state a real recommendation. Still no `rjags`/`run_with_jags.sh` needed.
- **fit** (`--manifest` **and** `--model` both given): does the same
  load+merge+build as build-preview (always fresh from the manifest — this
  is what fixes a real staleness risk the old two-separate-scripts design
  had: if `model_type` changes between Step 8c and Step 9, a `--batman-in`
  file built under the old `model_type` would silently carry stale
  phantom-placebo-bridging decisions into the fit. Rebuilding fresh inside
  the same fit-mode call every time removes that risk entirely), then fits
  the JAGS model via `textConnection()`, then optionally the pooled-placebo
  sub-model (`--fit-placebo`), and writes the two files
  `make_forest_plot.R` needs: `--out <model_output.rds>` (bundles
  `arm_info`/`study_info`/`arm_rows`/`batman_data`) and `--cache
  <samples.rds>`. Needs `run_with_jags.sh`.

```r
#!/usr/bin/env Rscript
# Consolidated /cmh-ci pipeline: load+merge -> naming/pooling QA -> build
# BATMAN -> fit JAGS model [-> pooled-placebo model]. Replaces
# lib_common.R/load_merge_data.R/check_naming_pooling.R/build_batman_data.R/
# fit_bnma_model.R/fit_pooled_placebo_model.R (see SKILL.md's Appendix B
# intro for why). One file, three modes selected by which args are given --
# see SKILL.md Steps 1b/1c (explore), 8c/9 (build-preview), 10a/10b (fit).
#
# Usage:
#   Explore:       Rscript run_bnma_pipeline.R --prd <p> [--qa <q>] [--registry <r>]
#   Build-preview: Rscript run_bnma_pipeline.R --prd <p> [--qa <q>] --manifest <m>
#   Fit:           Rscript run_bnma_pipeline.R --prd <p> [--qa <q>] --manifest <m> \
#                    --model model_random.txt --cache <samples.rds> --out <model_output.rds> \
#                    [--fit-placebo --placebo-cache <p.rds> --placebo-out <pd.rds>] [--force]
#
# Explore and build-preview modes never load rjags -- run them via
# run_r.sh. Fit mode needs run_with_jags.sh (module load jags).

suppressPackageStartupMessages({
  library(dplyr)
  library(readxl)
  library(yaml)
  library(jsonlite)
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

#' Whether this network's data can actually support a random-effects
#' heterogeneity estimate (see pf_nma.R's star-network precedent, quoted at
#' length in SKILL.md Step 9a) -- per non-placebo treatment node, how many
#' distinct studies feed it.
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

# --------------------------------------------------------------------------
# Embedded JAGS model text (formerly Appendix A's standalone .txt files).
# Selected by manifest model_type -> --model name, passed to jags.model()
# via textConnection() at fit time -- no file ever materialized for these.
# model_simultaneous_fixed.txt is model_simultaneous.txt's hierarchical/
# pooled phi/m paired with model_fixed.txt's deterministic delta[i,j] block
# (no sigma actually drives delta here, same dead-but-present sigma/tau2
# declaration model_fixed.txt itself keeps for structural symmetry) --
# reconstructed from SKILL.md Step 10a's own description of this file,
# since the source repo's Appendix A never actually spelled it out
# (confirmed gap, fixed here 2026-08-27).
# --------------------------------------------------------------------------
MODEL_TEXTS <- list(

  model_random.txt = '
model{
    for(i in 1:ns){
        phi[i]~dnorm(0.0, 0.0001)
    }
    for(i in 1:ns){
        for(j in 1:na[i]){
            y[i,j]~dnorm(eta[i,j], 1/se[i,j]^2)
            dev[i,j] <- (y[i,j]-eta[i,j])*(y[i,j]-eta[i,j])*(1/se[i,j]^2)
        }
        devstudy[i] <- sum(dev[i,1:na[i]])
    }
    for(i in 1:ns){
        eta[i,1]<-phi[i]+delta[i,1]
        for(j in 2:na[i]){
            eta[i,j]<-phi[i] + delta[i,j]
        }
    }
    for(i in 1:ns){
        w[i,1]<-0
        delta[i,1]<-0
        for(j in 2:na[i]){
            delta[i,j]~dnorm((d[trt[i,j]]-d[trt[i,1]])+sw[i,j], tau2d[i,j])
            tau2d[i,j]<-tau2*2*(j-1)/j
            w[i,j]<-delta[i,j]-d[trt[i,j]] + d[trt[i,1]]
            sw[i,j]<-sum(w[i,1:(j-1)])/(j-1)
        }
    }
    Dbar <- sum(devstudy[])
    d[1]<-0
    for(k in 2:M){
        d[k]~dnorm(0,1e-04)
    }
    sigma~dunif(0,8)
    sigma2<-sigma*sigma
    tau2<-1/sigma2
}',

  model_fixed.txt = '
model{
    for(i in 1:ns){
        phi[i]~dnorm(0.0, 0.0001)
    }
    for(i in 1:ns){
        for(j in 1:na[i]){
            y[i,j]~dnorm(eta[i,j], 1/se[i,j]^2)
            dev[i,j] <- (y[i,j]-eta[i,j])*(y[i,j]-eta[i,j])*(1/se[i,j]^2)
        }
        devstudy[i] <- sum(dev[i,1:na[i]])
    }
    for(i in 1:ns){
        eta[i,1]<-phi[i]+delta[i,1]
        for(j in 2:na[i]){
            eta[i,j]<-phi[i] + delta[i,j]
        }
    }
    for(i in 1:ns){
        w[i,1]<-0
        delta[i,1]<-0
        for(j in 2:na[i]){
            tau2d[i,j]<-tau2*2*(j-1)/j
            delta[i, j] <- (d[trt[i, j]]-d[trt[i, 1]])+sw[i, j]
            w[i,j]<-delta[i,j]-d[trt[i,j]] + d[trt[i,1]]
            sw[i,j]<-sum(w[i,1:(j-1)])/(j-1)
        }
    }
    Dbar <- sum(devstudy[])
    d[1]<-0
    for(k in 2:M){
        d[k]~dnorm(0,1e-04)
    }
    sigma~dunif(0,8)
    sigma2<-sigma*sigma
    tau2<-1/sigma2
}',

  model_simultaneous.txt = '
model{
    for(i in 1:ns){
      phi[i] ~ dnorm(m, tau2_m)
    }
    m ~ dnorm(0, 1e-04)
    tau2_m   <- 1 / sigma2_m
    sigma2_m <- sigma_m * sigma_m
    sigma_m  ~ dunif(0, 8)

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
        delta[i,j] ~ dnorm((d[trt[i,j]] - d[trt[i,1]]) + sw[i,j], tau2d[i,j])
        tau2d[i,j] <- tau2 * 2 * (j-1) / j
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
    tau2   <- 1 / sigma2
    mu_new ~ dnorm(m, 1 / sigma_m^2)
}',

  model_simultaneous_fixed.txt = '
model{
    for(i in 1:ns){
      phi[i] ~ dnorm(m, tau2_m)
    }
    m ~ dnorm(0, 1e-04)
    tau2_m   <- 1 / sigma2_m
    sigma2_m <- sigma_m * sigma_m
    sigma_m  ~ dunif(0, 8)

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
        delta[i,j] <- (d[trt[i,j]] - d[trt[i,1]]) + sw[i,j]
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
    tau2   <- 1 / sigma2
    mu_new ~ dnorm(m, 1 / sigma_m^2)
}',

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
  manifest      = list(default = NULL),
  model         = list(default = NULL),
  out           = list(default = NULL),
  cache         = list(default = NULL),
  force         = list(flag = TRUE, default = FALSE),
  fit_placebo   = list(flag = TRUE, default = FALSE),
  placebo_cache = list(default = NULL),
  placebo_out   = list(default = NULL),
  registry      = list(default = NULL),
  n_adapt       = list(default = "10000"),
  n_burnin      = list(default = "10000"),
  n_iter        = list(default = "20000"),
  thin          = list(default = "10"),
  seed          = list(default = "2026")
))

if (is.null(args$data) && is.null(args$prd) && is.null(args$qa)) {
  stop("At least one of --prd, --qa, or --data must be given.")
}

# ==========================================================================
# ALWAYS: load + merge PRD/QA (formerly load_merge_data.R), UNLESS --data
# points at an already-merged/adapted .rds -- the standalone-workbook
# adapter path (SKILL.md Step 1's note) writes its own already-normalized
# data.frame for a workbook that doesn't match the QA/PRD schema at all;
# --data lets that .rds feed straight into naming-check/build/fit exactly
# as if it were this block's own output, same substitution the old
# separate-scripts design supported via check_naming_pooling.R/
# build_batman_data.R's own `--data` argument.  Re-run fresh on every
# invocation, every mode, when NOT using --data -- cheap and deterministic,
# so there's never an intermediate merged.rds to hand off between separate
# processes.
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
  key <- function(df) paste(df$study_name, df$treatment, sep = "")
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

cat(
  "Merged", nrow(merged), "rows (",
  sum(merged$source_tier == "prd"), "from PRD,",
  sum(merged$source_tier == "qa"), "from QA ).\n",
  "Studies:", n_distinct(merged$study_name), "  Compounds:", n_distinct(merged$compound), "\n"
)

# ==========================================================================
# EXPLORE MODE (no --manifest): data summary + naming/pooling checks,
# stdout only, exit. Covers Steps 1b+1c in one call. Formerly
# check_naming_pooling.R's logic.
# ==========================================================================
if (is.null(args$manifest)) {

  cat("\n=== Dataset summary ===\n")
  cat("Phases:", paste(sort(unique(merged$phase)), collapse = ", "), "\n")
  cat("Evidence tiers: observed=", sum(merged$source_sheet == "observed"),
      " prediction=", sum(merged$source_sheet == "prediction"), "\n", sep = "")
  cat("Regions:", paste(sort(unique(merged$region)), collapse = ", "), "\n")

  registry_path <- args$registry
  registry <- if (!is.null(registry_path) && file.exists(registry_path)) yaml::read_yaml(registry_path) else list()
  resolved_pairs <- registry$resolved_pairs %||% list()
  pair_key <- function(a, b) paste(sort(c(a, b)), collapse = "|||")
  is_resolved <- function(a, b) {
    if (length(resolved_pairs) == 0) return(FALSE)
    target <- pair_key(a, b)
    any(vapply(resolved_pairs, function(p) pair_key(p$a, p$b) == target, logical(1)))
  }

  EDIT_THRESHOLD <- 0.25
  compounds <- merged$compound %>% unique() %>% na.omit() %>% setdiff("placebo") %>% sort()
  studies_by_compound <- split(merged$study_name, merged$compound)

  compound_flags <- list()
  if (length(compounds) >= 2) {
    for (p in combn(compounds, 2, simplify = FALSE)) {
      a <- p[1]; b <- p[2]
      if (a == b || is_resolved(a, b)) next
      is_substring <- (nchar(a) >= 4 && nchar(b) >= 4) && (grepl(a, b, fixed = TRUE) || grepl(b, a, fixed = TRUE))
      edit_ratio <- adist(a, b)[1, 1] / max(nchar(a), nchar(b))
      tier <- if (is_substring) "high" else if (edit_ratio <= EDIT_THRESHOLD) "low" else NA_character_
      if (is.na(tier)) next
      shared_studies <- intersect(studies_by_compound[[a]], studies_by_compound[[b]])
      suppressed <- length(shared_studies) > 0
      compound_flags[[length(compound_flags) + 1]] <- list(
        compound_a = a, compound_b = b, tier = tier,
        edit_distance_ratio = round(edit_ratio, 3), is_substring = is_substring,
        suppressed = suppressed,
        suppressed_reason = if (suppressed) paste0("co-occur as separate arms in ", length(shared_studies), " shared study/ies (e.g. '", shared_studies[1], "')") else NA_character_
      )
    }
  }

  pooling_flags <- list()
  if ("aom" %in% names(merged)) {
    by_compound <- merged %>% filter(compound != "placebo") %>%
      group_by(compound) %>% summarise(aom_values = list(unique(aom)), .groups = "drop")
    for (i in seq_len(nrow(by_compound))) {
      cmpd <- by_compound$compound[i]; aoms <- by_compound$aom_values[[i]]
      distinct_non_na <- unique(na.omit(aoms))
      if (length(distinct_non_na) < 2 && !any(is.na(aoms))) next
      rows <- merged %>% filter(compound == cmpd)
      if (length(distinct_non_na) >= 2) {
        collisions <- rows %>% filter(!is.na(aom)) %>% group_by(treatment) %>%
          summarise(n_routes = n_distinct(aom), routes = list(unique(aom)), .groups = "drop") %>%
          filter(n_routes > 1)
        for (j in seq_len(nrow(collisions))) {
          pooling_flags[[length(pooling_flags) + 1]] <- list(
            kind = "route_collision", compound = cmpd, treatment = collisions$treatment[j],
            routes = collisions$routes[[j]],
            message = paste0("'", collisions$treatment[j], "' (", cmpd, ") appears under routes [",
                              paste(collisions$routes[[j]], collapse = ", "), "] -- will collapse into ONE arm.")
          )
        }
      }
      if (any(is.na(aoms))) {
        pooling_flags[[length(pooling_flags) + 1]] <- list(
          kind = "missing_route", compound = cmpd, treatment = NA_character_, routes = list(),
          message = paste0("'", cmpd, "' has rows with no `aom` recorded.")
        )
      }
    }
  }

  integrity_flags <- list()
  mistagged <- merged %>% filter(treatment == "placebo", !is.na(compound), compound != "placebo")
  if (nrow(mistagged) > 0) {
    for (i in seq_len(nrow(mistagged))) {
      integrity_flags[[length(integrity_flags) + 1]] <- list(
        kind = "placebo_mistag", study_name = mistagged$study_name[i], compound = mistagged$compound[i],
        message = paste0("Study '", mistagged$study_name[i], "' has treatment=='placebo' tagged compound='", mistagged$compound[i], "'.")
      )
    }
  }
  pbo_rows <- merged %>% filter(compound == "pbo")
  if (nrow(pbo_rows) > 0) {
    affected_studies <- unique(pbo_rows$study_name)
    integrity_flags[[length(integrity_flags) + 1]] <- list(
      kind = "pbo_compound_alias", study_name = NA_character_, compound = "pbo",
      message = paste0("compound == 'pbo' found in ", length(affected_studies), " study/ies -- propose compound_relabels: 'pbo' -> 'placebo'.")
    )
  }

  placebo_naming_flags <- list()
  placebo_variants <- merged %>% filter(compound == "placebo", treatment != "placebo") %>% distinct(treatment) %>% pull(treatment)
  for (pv in placebo_variants) {
    affected_studies <- merged %>% filter(compound == "placebo", treatment == pv) %>% pull(study_name) %>% unique()
    placebo_naming_flags[[length(placebo_naming_flags) + 1]] <- list(
      kind = "placebo_naming_variant", treatment = pv, affected_studies = affected_studies,
      message = paste0("'", pv, "' is a placebo row under a non-canonical treatment string -- affects ", length(affected_studies), " study/ies.")
    )
  }

  no_placebo_flags <- list()
  studies_with_placebo_all <- merged %>% filter(compound == "placebo") %>% pull(study_name) %>% unique()
  studies_without_placebo_all <- setdiff(unique(merged$study_name), studies_with_placebo_all)
  for (sn in studies_without_placebo_all) {
    treats <- merged %>% filter(study_name == sn) %>% pull(treatment) %>% unique()
    no_placebo_flags[[length(no_placebo_flags) + 1]] <- list(
      study_name = sn, treatments = treats,
      message = paste0("'", sn, "' has no 'placebo' row.")
    )
  }

  report <- list(
    compound_flags = compound_flags, pooling_flags = pooling_flags,
    integrity_flags = integrity_flags, placebo_naming_flags = placebo_naming_flags,
    no_placebo_flags = no_placebo_flags,
    summary = list(
      n_compounds_checked = length(compounds), n_compound_flags = length(compound_flags),
      n_compound_flags_active = sum(vapply(compound_flags, function(f) !f$suppressed, logical(1))),
      n_pooling_flags = length(pooling_flags), n_integrity_flags = length(integrity_flags),
      n_placebo_naming_flags = length(placebo_naming_flags), n_no_placebo_flags = length(no_placebo_flags)
    )
  )

  cat("\n=== Naming/Pooling QA Report ===\n")
  cat(jsonlite::toJSON(report, auto_unbox = TRUE, pretty = TRUE, na = "null"), "\n")
  quit(status = 0, save = "no")
}

# ==========================================================================
# BUILD (manifest given) -- formerly build_batman_data.R. Runs for both
# build-preview mode (no --model, exits after this block) and fit mode
# (--model given, continues on to fit below). Always derived fresh from
# the manifest -- see this script's own header for why that matters when
# model_type changes between the build-preview call and the fit call.
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

print_heterogeneity_estimability(compute_heterogeneity_estimability(data_recon))

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

model_output <- list(batman_data = batman_data, arm_info = arm_info, study_info = study_info, arm_rows = arm_rows)

if (is.null(args$model)) {
  cat("Build preview complete (no --model given) -- not fitting. Re-run with\n",
      "--model once model_type is confirmed (Step 9). Nothing written to disk.\n")
  quit(status = 0, save = "no")
}

# ==========================================================================
# FIT MODE (--model given) -- formerly fit_bnma_model.R + (optionally)
# fit_pooled_placebo_model.R. Needs rjags/module load jags -- explore and
# build-preview modes above never reach this point.
# ==========================================================================
if (!is.null(args$out)) saveRDS(model_output, args$out)

suppressPackageStartupMessages(library(rjags))

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

if (isTRUE(args$fit_placebo)) {
  placebo_rows <- arm_rows %>% filter(compound == "placebo", !is.na(y), !is.na(se), se > 0, is.finite(se))
  if (nrow(placebo_rows) == 0) stop("No usable placebo rows for the pooled-placebo model.")
  study_map <- data.frame(study_ind = sort(unique(placebo_rows$study_ind)), study_idx = seq_along(unique(placebo_rows$study_ind)))
  placebo_rows <- placebo_rows %>% left_join(study_map, by = "study_ind")
  if (nrow(study_map) < 2) stop("Not enough studies with a usable placebo arm (need >= 2; found ", nrow(study_map), ").")

  if (!is.null(args$placebo_out)) saveRDS(placebo_rows, args$placebo_out)
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
```
### B2. `append_to_qa.R`

Step 6's "promote to QA" path — appends new rows to an existing QA workbook in-place (or creates one from a PRD schema if the user confirmed). Called once per session when new data is being promoted to the shared QA file before fitting. Unchanged from before, except it no longer sources a separate `lib_common.R` (retired along with the other consolidated scripts) — its own tiny `parse_args()`/`%||%` copy is inlined instead.

```r
#!/usr/bin/env Rscript
# Step 6 of the /cmh-ci skill (the "promote to QA" branch): append new rows
# to the QA workbook.
#
# The QA file is the living working copy of the landscape data. New entries
# (from press releases, digitized slides, subsets of other workbooks) land
# here first, then eventually get promoted to PRD through the normal team
# process. This script handles the physical append; the skill's Step 6
# handles the logic of what to append and getting user confirmation.
#
# Usage:
#   Rscript append_to_qa.R --qa <path.xlsx> --sheet <Observed|Prediction> \
#     --rows <rows.rds> [--create-from <prd_path.xlsx>]

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
         "The skill should ask the user before creating a new QA file.")
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

combined <- bind_rows(existing, new_rows)

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
```

### B3. `make_forest_plot.R`

Steps 10a/10b's forest plot + QC plot, plus the `named_contrast.R` utility —
three modes on one script, selected by which arguments are given:

- **plot** (default): renders the relative/absolute forest plot, reading
  `--model-output` (B1's bundle: `arm_info`/`study_info`/`arm_rows`) instead
  of three separate files. Fixed compound palette + fallback generator,
  evidence-type superscripts, no caption on the image (per the 2026-08-27
  change), footnote still printed to console.
- **`--qc-plot <path> --placebo-data <path>`**: also renders the pooled-
  placebo QC plot (formerly `make_placebo_forest_plot.R`) — each
  contributing study's observed vs. posterior-shrunk placebo effect, the
  pooled `m`, and the predictive `mu_new`.
- **`--contrast "treat1|||treat2"`**: skips plotting entirely and prints a
  named posterior contrast between two treatments (formerly
  `named_contrast.R`) — resolves both by name against `--model-output`'s
  `arm_info`, never a hardcoded posterior index.

```r
#!/usr/bin/env Rscript
# Consolidated /cmh-ci plotting script: forest plot [+ placebo QC plot] [+
# named contrast]. Replaces make_forest_plot.R + make_placebo_forest_plot.R +
# named_contrast.R (see SKILL.md's Appendix B intro for why).
#
# Usage:
#   Rscript make_forest_plot.R --model-output <bundle.rds> --samples <cache.rds> \
#     --manifest <manifest.yaml> --effect relative|absolute --out <plot.png> \
#     [--placebo-samples <p.rds>]                                    # required if --effect absolute
#     [--qc-plot <qc.png> --placebo-data <pd.rds>]                   # optional placebo QC plot
#     [--contrast "treat1|||treat2"]                                 # skips plotting; prints a contrast instead
#     [--title "..."] [--xlab "..."]

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(yaml)
  library(coda)
  library(ggtext)
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
  model_output    = list(required = TRUE),
  samples         = list(default = NULL),
  manifest        = list(required = TRUE),
  effect          = list(default = "relative"),
  placebo_samples = list(default = NULL),
  out             = list(default = NULL),
  qc_plot         = list(default = NULL),
  placebo_data    = list(default = NULL),
  contrast        = list(default = NULL),
  title           = list(default = NULL),
  xlab            = list(default = NULL)
))

bundle <- readRDS(args$model_output)
arm_info <- bundle$arm_info
study_info <- bundle$study_info
arm_rows <- bundle$arm_rows
manifest <- yaml::read_yaml(args$manifest)

# ==========================================================================
# CONTRAST MODE -- formerly named_contrast.R. Resolves a named head-to-head
# comparison from an already-fitted run's posterior, never a hardcoded d[k]
# index. Skips plotting entirely.
# ==========================================================================
if (!is.null(args$contrast)) {
  parts <- strsplit(args$contrast, "\\|\\|\\|")[[1]]
  if (length(parts) != 2) stop("--contrast must be \"treat1|||treat2\", got: ", args$contrast)
  treat1 <- trimws(parts[1]); treat2 <- trimws(parts[2])

  if (is.null(args$samples)) stop("--contrast needs --samples <cache.rds>")
  samples <- readRDS(args$samples)
  cn <- colnames(samples[[1]])
  samples_mat <- do.call(rbind, lapply(samples, function(x) x[, , drop = FALSE]))
  colnames(samples_mat) <- cn

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

# ==========================================================================
# PLOT MODE (default) -- formerly make_forest_plot.R
# ==========================================================================
if (!args$effect %in% c("relative", "absolute")) stop("--effect must be 'relative' or 'absolute'")
if (is.null(args$samples)) stop("--samples <cache.rds> is required for plotting")
if (is.null(args$out)) stop("--out <plot.png> is required for plotting")

samples <- readRDS(args$samples)
samples_mat <- as.matrix(samples)

if (args$effect == "absolute") {
  if (is.null(args$placebo_samples)) stop("--effect absolute needs --placebo-samples <path> (from run_bnma_pipeline.R --fit-placebo).")
  if (!file.exists(args$placebo_samples)) stop("--placebo-samples file not found: ", args$placebo_samples)
  placebo_samples_mat <- as.matrix(readRDS(args$placebo_samples))
  if (!"m" %in% colnames(placebo_samples_mat)) stop("--placebo-samples file has no 'm' node.")
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
  if (args$effect == "relative") {
    post <- if (arm_k == 1) rep(0, nrow(samples_mat)) else samples_mat[, paste0("d[", arm_k, "]")]
  } else {
    post <- if (arm_k == 1) m_samples else m_samples + samples_mat[, paste0("d[", arm_k, "]")]
  }
  data.frame(treatment = trt_name, compound = if (trt_name == "placebo") "placebo" else cmpd,
             evidence_type = arm_lookup$evidence_type[i], mean = mean(post),
             val2.5pc = quantile(post, 0.025), val97.5pc = quantile(post, 0.975))
})

data_plot <- bind_rows(rows) %>%
  filter(treatment %in% plot_treatments | (args$effect == "absolute" & treatment == "placebo")) %>%
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

effect_col <- manifest$effect_col %||% "pchg_wl_ee"
endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
ylab_text <- args$xlab %||% sprintf("Mean (95%% CI) of %s Percent Change in %s (%%)",
                                     if (args$effect == "relative") "Pbo-adj" else "Absolute", endpoint_label)
title_text <- args$title %||% sprintf("%s Percent %s Change",
                                       if (args$effect == "relative") "Placebo-Adjusted" else "Absolute", endpoint_label)

subtitle_text <- NULL
if (args$effect == "absolute") {
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

if (!is.null(arm_rows)) {
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
} else {
  contributing_studies <- paste(sort(study_info$study_name), collapse = ", ")
  contributing_lines <- strwrap(paste0("Contributing studies: ", contributing_studies), width = footnote_wrap_width)
}
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
ggsave(args$out, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote (not rendered on the plot -- console record only):\n", footnote_text, "\n")

# ==========================================================================
# QC PLOT (--qc-plot given) -- formerly make_placebo_forest_plot.R
# ==========================================================================
if (!is.null(args$qc_plot)) {
  if (is.null(args$placebo_data)) stop("--qc-plot needs --placebo-data <path> (from run_bnma_pipeline.R --fit-placebo's --placebo-out).")
  if (is.null(args$placebo_samples)) stop("--qc-plot needs --placebo-samples too.")

  placebo_data <- readRDS(args$placebo_data)
  ps <- summary(readRDS(args$placebo_samples))
  m_mean <- ps$statistics["m", "Mean"]; m_lo <- ps$quantiles["m", "2.5%"]; m_hi <- ps$quantiles["m", "97.5%"]
  sigma_mean <- ps$statistics["sigma_m", "Mean"]; sigma_lo <- ps$quantiles["sigma_m", "2.5%"]; sigma_hi <- ps$quantiles["sigma_m", "97.5%"]
  mu_new_mean <- ps$statistics["mu_new", "Mean"]; mu_new_lo <- ps$quantiles["mu_new", "2.5%"]; mu_new_hi <- ps$quantiles["mu_new", "97.5%"]

  mu_rows <- grepl("^mu\\[", rownames(ps$statistics))
  mu_summary <- data.frame(
    study_idx = as.integer(gsub("mu\\[(\\d+)\\]", "\\1", rownames(ps$statistics)[mu_rows])),
    post_mean = ps$statistics[mu_rows, "Mean"], post_lower = ps$quantiles[mu_rows, "2.5%"], post_upper = ps$quantiles[mu_rows, "97.5%"]
  )

  qc_data <- placebo_data %>% left_join(mu_summary, by = "study_idx") %>%
    mutate(obs_lower = y - 1.96 * se, obs_upper = y + 1.96 * se,
           Label = sprintf("%.1f (%.1f, %.1f)", post_mean, post_lower, post_upper)) %>%
    arrange(study_name)

  study_order <- c("New study (predicted)", "Pooled (m)", rev(qc_data$study_name))
  rows_obs <- qc_data %>% transmute(label = study_name, kind = "Observed", mean = y, lo = obs_lower, hi = obs_upper)
  rows_post <- qc_data %>% transmute(label = study_name, kind = "Posterior (shrunk)", mean = post_mean, lo = post_lower, hi = post_upper)
  rows_pooled <- data.frame(label = "Pooled (m)", kind = "Pooled", mean = m_mean, lo = m_lo, hi = m_hi)
  rows_new <- data.frame(label = "New study (predicted)", kind = "Predicted (mu_new)", mean = mu_new_mean, lo = mu_new_lo, hi = mu_new_hi)
  qc_plot_data <- bind_rows(rows_obs, rows_post, rows_pooled, rows_new) %>% mutate(label = factor(label, levels = study_order))

  qc_endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
  qc_xlab <- sprintf("Mean (95%% CI) Placebo Percent Change in %s (%%)", qc_endpoint_label)
  qc_title <- sprintf("Pooled Placebo Effect: %s", qc_endpoint_label)
  qc_subtitle <- sprintf("Pooled m = %.2f%% (95%% CrI: %.2f, %.2f)   between-study SD (sigma_m) = %.2f (95%% CrI: %.2f, %.2f)",
                          m_mean, m_lo, m_hi, sigma_mean, sigma_lo, sigma_hi)

  qc_p <- ggplot(qc_plot_data, aes(x = label, y = mean, ymin = lo, ymax = hi, color = kind, shape = kind)) +
    geom_pointrange(position = position_dodge(width = 0.4), size = 0.5) +
    geom_hline(yintercept = 0, linetype = 2, linewidth = 0.6) +
    scale_color_manual(values = c("Observed" = "#7F8C8D", "Posterior (shrunk)" = "#1B4F72", "Pooled" = "#000000", "Predicted (mu_new)" = "#7B241C")) +
    scale_shape_manual(values = c("Observed" = 1, "Posterior (shrunk)" = 16, "Pooled" = 18, "Predicted (mu_new)" = 17)) +
    coord_flip() + xlab("") + ylab(qc_xlab) +
    ggtitle(qc_title, subtitle = qc_subtitle) +
    labs(color = "", shape = "") +
    theme_bw() +
    theme(plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
          plot.subtitle = element_text(size = 10, color = "grey35", hjust = 0.5), legend.position = "bottom")

  ggsave(args$qc_plot, plot = qc_p, width = 9, height = max(4, 0.45 * length(study_order) + 2), dpi = 150)
  cat("Placebo QC plot saved to:", args$qc_plot, "\n")
  cat(sprintf("Pooled placebo effect (m): %.2f%% (95%% CrI: %.2f, %.2f)\n", m_mean, m_lo, m_hi))
  cat(sprintf("Predicted placebo effect in a new study (mu_new): %.2f%% (95%% CrI: %.2f, %.2f)\n", mu_new_mean, mu_new_lo, mu_new_hi))
}
```
---

## Appendix D — Session Environment Wrappers (embedded, no external files needed)

This HPC environment doesn't guarantee `Rscript` on `PATH`, and `rjags`
needs `module load jags` run in the same shell before it links — these three
wrappers resolve that portably. Materialize them the same way as Appendix B
(write to a real file, `chmod +x`, then exec). Now shared by just the two
consolidated scripts instead of nine: D2 for `run_bnma_pipeline.R`'s
explore/build-preview modes and `make_forest_plot.R` (none of these load
`rjags`), D3 only for `run_bnma_pipeline.R`'s fit mode.

### D1. `_resolve_rscript.sh`

Shared Rscript resolution, sourced by D2/D3 below (not run directly): explicit override, PATH, then `module load R`, then PATH again.

```bash
#!/usr/bin/env bash

# Shared Rscript resolution, sourced by run_r.sh and run_with_jags.sh.
# Not meant to be run directly. Sets RSCRIPT_BIN.
#
# Resolution order: explicit override, PATH, `module load R` (whichever
# version this session tags default) then PATH again. Neither "on PATH" nor
# "one fixed install path" can be assumed across different analysts'
# Positron sessions -- confirmed by testing: Rscript is NOT on PATH by
# default in at least one real session here, and R itself is provisioned
# via `module load R/<version>` there, same as JAGS.

if [ -f /etc/profile.d/modules.sh ]; then
  source /etc/profile.d/modules.sh
fi

RSCRIPT_BIN="${BNMA_RSCRIPT:-}"
if [ -z "$RSCRIPT_BIN" ]; then
  RSCRIPT_BIN="$(command -v Rscript || true)"
fi
if [ -z "$RSCRIPT_BIN" ] && command -v module >/dev/null 2>&1; then
  module load R >/dev/null 2>&1 || true
  RSCRIPT_BIN="$(command -v Rscript || true)"
fi
if [ -z "$RSCRIPT_BIN" ]; then
  echo "ERROR: no Rscript found on PATH, and 'module load R' didn't put one there." >&2
  echo "Set BNMA_RSCRIPT=/path/to/Rscript to pin a specific install." >&2
  exit 1
fi
```

### D2. `run_r.sh`

Wrapper for any script that does NOT need rjags/JAGS.

```bash
#!/usr/bin/env bash
# Wrapper for any /cmh-ci script that does NOT need rjags/JAGS -- resolves
# Rscript portably (see _resolve_rscript.sh) and execs it. Use
# run_with_jags.sh instead for run_bnma_pipeline.R's fit mode.
#
# Usage: scripts/run_r.sh <path/to/script.R> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_resolve_rscript.sh"

exec "$RSCRIPT_BIN" "$@"
```

### D3. `run_with_jags.sh`

Wrapper for `run_bnma_pipeline.R`'s fit mode (`--model` given): loads the `jags` environment module before exec'ing Rscript.


```bash
#!/usr/bin/env bash
# Wrapper for any /bnma script that needs rjags: resolves Rscript (see
# _resolve_rscript.sh), loads the `jags` environment module (rjags is
# installed but fails to link its shared library without this -- confirmed:
# requireNamespace("rjags") is FALSE until `module load jags` has run in the
# same shell), then execs Rscript.
#
# Usage: scripts/run_with_jags.sh <path/to/script.R> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_resolve_rscript.sh"

if command -v module >/dev/null 2>&1; then
  if module avail jags 2>&1 | grep -qi jags; then
    module load jags
  else
    echo "WARNING: environment modules are available here but no 'jags' module was found." >&2
    echo "  rjags will likely fail to load unless JAGS is on the library path some other way." >&2
    echo "  Run 'module avail' to check what this session actually calls it." >&2
  fi
else
  echo "NOTE: no 'module' command in this session -- assuming JAGS is already reachable" >&2
  echo "  (either not needed here, or provisioned some other way than environment modules)." >&2
fi

exec "$RSCRIPT_BIN" "$@"
```

