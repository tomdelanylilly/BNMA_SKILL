---
name: cmh-ci
description: >
  Run a Cardiometabolic Health competitive-intelligence Bayesian network
  meta-analysis (BNMA) on any single continuous endpoint (weight loss, HbA1c,
  physical function, etc.) from the QA/PRD dataset, with forced
  study-selection confirmation and a naming/route pooling-risk QA gate,
  instead of a hardcoded, hand-edited study list. Use this skill whenever
  the user wants to run, update, or refresh a BNMA forest plot from a
  QA/PRD dataset, or mentions "/cmh-ci", "run the BNMA", "run the
  meta-analysis", "BATMAN", "landscape forest plot", or "competitive
  intelligence deck figures".
---

# /cmh-ci

Guided BNMA workflow for the obesity/diabetes-landscape QA/PRD dataset,
generalized across endpoints (weight loss, HbA1c, physical function, etc. --
see Step 3's Endpoint question and Step 4's `effect_col`/`se_col` manifest
fields). Reuses the
existing BATMAN-augmentation + JAGS + forest-plot pipeline (see the misc5
project's R scripts for the reference implementation this was built from),
but replaces every place that pipeline made a silent, hardcoded decision
with an explicit step the user must confirm. See `DESIGN.md` in this skill's
repo (or the project's `GUIDE_README.md`) for why each step exists.

**Run this in a terminal, with the statistician's own working directory of
their choice** (their own project folder under `programs/`/`output/shared/`,
per `GUIDE_README.md`'s Flow 2 convention — not necessarily this skill's own
repo checkout). Step 0 assumes exactly this: a folder that may already have
PRD/QA data sitting in it, not a bare/empty directory.

**Canonical reference for MCMC settings and model behavior:**
`EliLillyCo/CMH.BNMA` (the real production Shiny app this skill's pipeline
is meant to match) — provided in full, 2026-08-20. Where this skill's own
prior settings conflicted with that package's actual documented/coded
behavior, this skill was corrected to match it (see Step 5's MCMC settings
and the single-arm-study/`pbo`-alias notes below); `BNMA_forest_plot-main.zip`
(confirmed 2026-08-17) remains the source for the JAGS model files
themselves, which CMH.BNMA's own model files match verbatim.

**Do not skip steps or assume defaults on the user's behalf on anything
genuinely discretionary.** The whole point of this skill is that a low-dose
Phase 2 study or an oral/injectable mix-up must never enter a model silently
again — but that doesn't require an interview. **One round trip is the
target** (2026-08-19, per explicit direction): compute everything that can
be computed from the data first, present ONE consolidated message with a
stated, safe default for every genuinely discretionary choice, let the
statistician accept-all/override/add free-form concerns in a single reply,
then run straight through to the plot with no further stops.

**The one thing that always still interrupts, even after that reply: a hard
gate failure** — `build_batman_data.R` refusing to run because a study is
missing from the manifest. Continuing silently past that would defeat the
actual purpose of the skill, not just its UX.

**This skill does not run any automated post-fit diagnostics** (no Rhat/ESS
convergence check, no network-connectivity/consistency/DIC check) — matches
the real production `EliLillyCo/CMH.BNMA` app's own behavior (confirmed
2026-08-24: it fits and plots with no such checks). If a fit's plausibility
needs verifying, inspect the posterior manually (`coda::gelman.diag()`,
`coda::effectiveSize()` on the cached `samples.rds`) rather than expecting
this skill to flag it.

## Step 0 — Locate the data, offer to merge new data, set up the run folders

Runs at the very start of every trigger, before Step 1 — the entry
experience for someone opening this skill against a folder that already has
PRD/QA data sitting in it (the common case: a statistician's own project
directory). Adapted 2026-08-21 from a colleague's independent restructuring
of this step (the `godwill-bnma` branch) — the locate-the-data logic below
is unchanged from before; 0b/0c are the new parts.

**0a. Locate the base dataset.** Only ask if the initial prompt didn't
already make this clear. Two ways a statistician can point at it — both
valid, use whichever fits what they actually gave you:
- **An exact file path** (PRD, and QA too if there's a newer one not yet
  promoted). Resolve per the workflow doc's fallback rule: try the QA path
  first, fall back to PRD if it's moved/been promoted. Use exactly what's
  given — don't guess a filename.
- **A working directory instead of a filename** — mirrors how a
  statistician's own scripts usually open with a `setwd()` to anchor
  relative paths; here it means naming a folder (their own project
  directory, e.g. under `programs/YYYYMMDD_.../`, or wherever this
  session's files live) and letting the search find the actual file. Search
  depth-limited (e.g. `find <dir> -maxdepth 3 -iname "*.xlsx"`) — never a
  full recursive walk, and never a directory that's itself a mount root
  (see the org's filesystem-search policy). **Always show every candidate
  found, with modified dates, and get an explicit pick — even when only one
  file looks plausible.** Silently choosing "the newest" or "the best name
  match" is exactly the class of silent assumption this skill exists to
  eliminate everywhere else; the directory search finds candidates, it
  never substitutes for confirming which one.

If neither a path nor a directory came with the initial prompt, ask which
the statistician wants to use before doing anything else.

**0b. Ask if there's new data to merge in.** Once the base dataset is
confirmed, always ask — in the same message, not a separate round trip —
whether there's new data (a new readout, a hand-digitized slide, a
standalone workbook, an updated QA file) to merge into this run before the
BNMA is fit. Never assume "no" just because the prompt didn't mention it. If
yes:
1. Get the new data's path (or inline content, if small enough to paste —
   treat that the same as `supplementary_data`, see Step 4).
2. Merge it into the base dataset via `load_merge_data.R` (QA-wins-over-PRD
   logic already documented in Step 1) — or, if its schema doesn't match
   the QA/PRD shape, via the standalone-workbook adapter procedure (see
   Step 1's own note on this). Show a merge summary: rows added, studies
   added, studies updated (an existing `(study_name, treatment)` pair whose
   values changed) — a merge that silently changes an existing row's value
   is exactly the kind of undetected drift this skill exists to prevent.
3. **Run `check_naming_pooling.R` against the merged result right away** —
   new data merging in is precisely when a naming collision or route
   mismatch is most likely (a newly-added study using a slightly different
   spelling for an existing compound, or the wrong `aom` tag). Surface any
   new flags now, folded into Step 3's consolidated ask alongside whatever
   Step 2 finds on the rest of the data — don't defer this to a second pass
   through Step 2.

If no, proceed with the base dataset as-is — Step 1 loads it normally.

**0c. Propose the run's `programs/` and `output/` folders — don't create
them yet.** As soon as the dataset (merged or not) is confirmed, work out a
proposed `<slug>` and both paths — `programs/YYYYMMDD_<slug>/` /
`output/shared/YYYYMMDD_<slug>/`, the same convention Step 7 already uses
for the driver script and forest plot — and carry them into Step 3's
consolidated ask as a **Working folders** line, same as every other
genuinely discretionary choice in that step (a proposed default, shown
explicitly, not decided silently on the statistician's behalf). Derive
`<slug>` from the dataset/endpoint (e.g. `cwm_wl_nont2d`, `ada_oral_full`) —
if nothing obvious presents itself, propose your best guess rather than
leaving it blank; the statistician can rename it in their Step 3 reply.
**Actually create both folders only once Step 3 is confirmed** (right before
Step 4 writes the manifest into `programs/<slug>/`) — this moves folder
creation earlier than Step 7 used to, so every intermediate artifact from
Step 1 onward (naming report, manifest, cached samples)
has a real home instead of living in `/tmp`, but it's still a
confirmed action, not a background one: don't write anything to disk under
a folder name the statistician hasn't seen and had the chance to change.
The merged dataset (Step 1) is the one exception — it never gets a
persisted home, see Step 4.

**Scratch mode is the opt-out alternative to the above, not a separate
step** — alongside the `programs/`/`output/shared/` proposal, always state
explicitly that replying "scratch" or "dry run" instead keeps this entire
run inside `/tmp` (`/tmp/bnma_scratch_<slug>/`) with nothing written to the
shared drive — no `programs/`/`output/shared/` folders, no
`compound_registry.yaml` update (Step 2), no driver script (Step 7). Useful
for prototyping/demoing the skill itself without leaving files behind on a
share that has no version control to clean them up. See Step 4 onward for
how each step's destination changes, and Step 7a for promoting a scratch
run to a real one afterward.

## Step 1 — Load & merge (runs automatically)

Every `--out`/intermediate-artifact path in this step and Step 2/2.5 below is
shown as `/tmp/bnma_*.rds` and genuinely does write there — the run's real
`programs/YYYYMMDD_<slug>/` folder isn't created until Step 4 (Step 3 has to
confirm the folder name first), so nothing durable exists yet. From Step 4
onward, everything (manifest, cached samples) writes into the
now-real `programs/<slug>/` folder instead. Losing `/tmp`'s merged data or
naming report between here and Step 4 costs nothing — both are cheap,
deterministic re-derivations from the source file(s), not something Step 7's
driver script or a later re-run ever depends on existing in `/tmp`.

Materialize Appendix D's wrappers and Appendix B.1/B.2 (`lib_common.R`,
`load_merge_data.R`) to this session's lib dir (e.g. `/tmp/cmh_ci_lib/`
before Step 4's folders exist, `programs/<slug>/lib/` after) if not already
done this session, then run:

```bash
scripts/run_r.sh scripts/load_merge_data.R \
  --prd <prd_path.xlsx> [--qa <qa_path.xlsx>] --out /tmp/bnma_merged.rds
```

No stop here — the printed summary (row/study/compound counts) feeds
directly into Step 3's consolidated message, not a separate confirmation.

**If the user attaches a standalone workbook instead of a QA/PRD path**
(confirmed real case, 2026-08-20: `Global_ADA_Oral_KAI7535_*.xlsx`, sheets
named `weight`/`WC` with generic `study_ind`/`arm_ind`/`y`/`se`/`Treatment`/
`Compound`/`Study` columns, not `Observed`/`Prediction` sheets with
`study_name`/`treatment`/`compound`/`aom`/`region`/`pchg_wl_ee`/`se_wl_ee`
columns) — check the actual sheet names and columns with R/readxl **before**
running `load_merge_data.R` on it. That script's sheet-fallback logic
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

If the schema doesn't match, don't force it through Step 1. Instead:
1. Write a small one-off adapter script (save it as `adapt_standalone.R`
   next to this run's manifest, not in `/tmp` — Step 7's driver script needs
   a permanent path to call it from) that maps the file's own columns into
   the shape `build_batman_data.R` expects: lowercase + `squish_ws()`
   `study_name`/`treatment`/`compound`; derive `aom`/`region`/`source_sheet`
   from context (e.g. a study name containing "Prediction" → `source_sheet
   = "prediction"`, else `"observed"`); keep the file's own effect/SE column
   names as-is — no need to rename to `pchg_wl_ee`/`se_wl_ee`, the
   manifest's `effect_col`/`se_col` can name whatever columns actually exist.
   Save the result as an `.rds`.
2. Feed that `.rds` into `check_naming_pooling.R` (Step 2) and
   `build_batman_data.R` (Step 5) exactly as if it were `load_merge_data.R`'s
   own output — every other step is unchanged.
3. In the manifest, put the adapter script's path in `source_program` and
   the original workbook's path in `source_data.prd` (not a custom key) —
   `make_forest_plot.R`'s footnote only reads `source_data.prd/qa` and
   `source_program`, so a custom key silently prints "(not recorded)"
   instead of the real path.

Also: a manifest's `effect_col`/`se_col` value of literally `y` or `n` must
be quoted (`effect_col: "y"`) — bare `y`/`n`/`yes`/`no`/`on`/`off` parse as
YAML 1.1 booleans, not strings, and `build_batman_data.R` fails with a
confusing "effect_col 'TRUE' not found" error. Same root cause as the
`row_exclusions` `"n"` gotcha documented under Step 4.

## Step 2 — Naming/pooling check (runs automatically, proposes resolutions)

Materialize Appendix B.3 (`check_naming_pooling.R`) to this session's lib
dir if not already done this session, then run:

```bash
scripts/run_r.sh scripts/check_naming_pooling.R \
  --data /tmp/bnma_merged.rds --out /tmp/bnma_naming_report.json
```

Read the JSON report, but **do not stop here to resolve flags one at a
time** — for every active (non-suppressed) `compound_flags`/`pooling_flags`
entry, work out a proposed resolution to carry into Step 3's single message
instead:
- A compound-name flag: propose `different` unless the substring/prefix
  signal is strong (one name is literally a substring of the other — the
  higher-confidence signal), in which case propose `same`.
- A route-pooling collision (identical `treatment` string under two `aom`
  values): propose `split_by_route` — collapsing two genuinely different
  routes into one arm is almost never the intended outcome.

These are proposals the statistician can override in their one reply, not
silent auto-resolutions — Step 3 must show every active flag and its
proposed resolution explicitly. If there are zero active flags, note that
plainly in Step 3's message rather than a separate line here.

Once an answer is confirmed (in Step 3), persist compound-name resolutions
to `compound_registry.yaml` (Edit tool, this skill's own repo copy) so the
same pair is never re-flagged; pooling-flag resolutions go in the manifest
only (Step 4), since they're data-specific rather than a general
compound-identity fact. **Skip the `compound_registry.yaml` write entirely
for a scratch run** (Step 0c/3) — the resolution still applies to this
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
treatment as any other naming flag. `build_batman_data.R` hard-errors if a
`compound == "placebo"` row ever reaches arm assignment under a
non-canonical treatment string — the backstop if this proposal is skipped
or missed, not just a style nit.

`no_placebo_flags` (Check 4b) — studies with no `placebo`-**compound** row
at all (computed after accounting for Check 4a's variants, so a study whose
only placebo arm is spelled `"oral placebo qd"` is correctly NOT flagged
here). This only matters if this run ends up on `model_type:
rand_effect`/`fixed_effect` (confirmed real, recurring scenario, 2026-08-20:
comes up "in some analyses" — an isolated head-to-head trial with no placebo
arm is the common case): those two model types leave such a study
disconnected from the network by default, matching the real production
tool's own behavior, unless explicitly opted into phantom-bridging. Carry
every flagged study into Step 3 individually, same "no silent default"
treatment as a phase 1/2 study — propose "leave disconnected" (the default,
and the one that matches production behavior) but require an explicit
per-study answer, not a blanket accept. If there are zero flagged studies
for either check, note that plainly rather than a separate line here, same
as the other checks.

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

## Step 2.5 — Compound-first entry point (if requested)

If the initial prompt already named specific compounds/treatments (e.g. "I
need these 21 treatments"), resolve them now, silently where unambiguous:
match each requested string against the merged data's actual `treatment`
values (report exact matches plainly; for anything without an exact match,
use edit-distance/substring candidates, same mechanism as Step 2). A missing
dose suffix (e.g. "Tirzepatide 5mg" vs. "tirzepatide 5mg qw") is usually
resolvable without asking. **Only a genuine ambiguity still needs its own
question** — e.g. "X Pooled" that doesn't correspond to any single row in
the source data needs an explicit decision (which single arm to use, or
whether to compute a genuinely new derived value); never invent one
silently, but don't manufacture a question where the match is actually
clear either.

Derive the distinct compound list from the resolved treatments and carry it
into Step 3 as the proposed `compound_filter` (a list of compound names).
`build_batman_data.R` applies this as a **row-level** filter (drop any row
whose `compound` isn't in the list), not a study-level one — a study mixing
a wanted compound with an unwanted one keeps its wanted-compound rows and
drops the rest. Placebo rows are always exempt, same as the route filter.
Every study is still enumerated in Step 3 for an explicit decision even
under a compound filter — a study with no requested compound usually still
has its placebo row survive (compound-exempt), so it still needs a decision;
batch these with a shared proposed reason ("not one of the requested
compounds for this run").

If the initial prompt did not name specific compounds, propose the default
in Step 3: every treatment surviving the other filters, in the order first
seen.

## Step 3 — The one consolidated ask

Present everything computed in Steps 1/2/2.5 as **one message**, each item
with a stated, safe default — this is the single round trip the
statistician answers once. Use this structure (fill in every value from the
actual data/report; never leave a placeholder):

```
╭──────────────────────────────────────────────────────────────────╮
│  /cmh-ci · review & confirm                                        │
├──────────────────────────────────────────────────────────────────┤
│  Reply with just what you want to change, plus anything else to   │
│  flag -- everything else proceeds on the default/proposal shown.  │
╰──────────────────────────────────────────────────────────────────╯

  SCOPE
   1  Dataset           <path(s)>                                (detected)
   2  Working folders  ► programs/YYYYMMDD_<slug>/, output/shared/YYYYMMDD_<slug>/  (not yet created; reply "scratch" for a /tmp-only dry run)
   3  Endpoint         ► weight loss (effect_col: pchg_wl_ee, se_col: se_wl_ee)
   4  Route            ► both (oral + injectable)
   5  Evidence         ► both (observed + prediction)
   6  Region           ► global only
   7  Heterogeneity    ► random-effects (rand_effect)
   8  Effect to report ► placebo-adjusted (relative)
   9  Project CLAUDE.md ► skip (default for a single run) -- reply "add CLAUDE.md" if this is a larger/ongoing project

  NAMING / POOLING  (N active flags)
   - <compound_a> vs <compound_b> -- proposed: <same|different>, because <signal>
   - <treatment string> under two routes -- proposed: split_by_route
   [or: "No naming/pooling flags found."]

  STUDIES  (X total)
   - Y phase 3 observed  -- proposed: include all
   - Z phase 1/2 / prediction-tier -- YOUR CALL, no default assumed:
       <study_name> (<phase>, <data_type>) -- proposed reason if you accept: <reason>
       ...

  STUDIES WITHOUT A PLACEBO ARM  (N found -- only matters if Heterogeneity above
  lands on rand_effect/fixed_effect; omit this whole section if N is 0)
   - <study_name> (<treatments in this study>) -- proposed: leave disconnected
     (matches production tool default; contributes a baseline estimate only,
     no relative-effect info) -- reply "bridge <study_name>" + a reason to
     phantom-bridge it instead
     ...

  PLOT
   - Treatments to show, in order -- proposed: <list, or "everything in scope">
```

Notes:
- **Working folders are a proposal, not yet created** — `<slug>` is your
  best guess at a short, meaningful label for this run (see Step 0c); the
  statistician can rename it in their reply. Nothing gets written to disk
  under this name until Step 3 is confirmed (see Step 4).
- **Replying "scratch" or "dry run" instead of accepting/renaming the
  folders** keeps the whole run in `/tmp/bnma_scratch_<slug>/` —
  `manifest.yaml`, the JAGS cache, and the forest plot all land there
  instead of `programs/`/`output/shared/`, Step 2's naming resolution
  (below) is never written to `compound_registry.yaml`, and Step 7's driver
  script is skipped in favor of an explicit promote-or-discard offer (Step
  7a). Everything else about the run — the fit, the plot, the footnote — is
  identical either way.
- **Endpoint defaults to weight loss** (`effect_col: pchg_wl_ee`,
  `se_col: se_wl_ee` — the QA/PRD schema's own effect-estimate/SE column
  pair) **only when the dataset's own columns match that schema** — check
  the actual column names in the merged data (Step 1) before proposing this
  default; don't assume every workbook is a weight-loss one just because
  that's the common case. For any other endpoint (HbA1c, physical function,
  etc.), state the real column names as the proposal instead — e.g. "HbA1c
  (`effect_col: chg_hba1c`, `se_col: se_chg_hba1c`)" — and also propose an
  `effect_label` (a short phrase for the plot's axis/title — e.g. `"HbA1c
  (%)"`) and, if `placebo_clamp` might be used this run, an `effect_direction`
  (`decrease_is_better` | `increase_is_better` — controls which sign
  `placebo_clamp` treats as "wrong direction"; weight loss and HbA1c
  reduction are `decrease_is_better`, a physical-function score where higher
  is healthier would be `increase_is_better`). This is a genuinely
  discretionary, data-dependent choice like Route/Evidence/Region — propose
  a default, but always state it explicitly rather than leaving it implicit.
- **Phase 1/2 and prediction-tier studies never get a silent proposed
  decision baked into the default path** — list each one individually and
  require the statistician to actually say include or exclude, even though
  everything else above is a normal accept-the-default item. This is the
  one place the "one round trip" goal does not mean "one fewer thing to
  decide" — it means "asked once, together with everything else," not
  "decided for you." (A *proposed reason* is fine to show for when they do
  decide to include one, per Step 4's manifest schema — the decision itself
  is never pre-filled.)
- **Studies without a placebo arm get the same individual, no-silent-default
  treatment**, but with a stated default (leave disconnected) they can
  accept in bulk by saying nothing — unlike phase 1/2 studies, this one has
  an objectively reasonable default (matches the real production tool), so
  silence means "leave every one of them disconnected," not "undecided."
  Only a study the statistician explicitly names to bridge needs a reason
  from them (folded into `phantom_placebo_reason`).
- End with an open invitation: "anything else to flag — a study you know
  about that should be excluded, a data-quality concern, a specific
  treatment format — say so now or after the fact; I'll fold it in before
  Step 4."
- Echo back exactly what was locked in (defaults accepted + overrides +
  any free-form concerns folded in) once the statistician replies, before
  Step 4 writes the manifest.
- **Project CLAUDE.md defaults to skip** — most runs are a single,
  self-contained ask and don't need one. Accept "add CLAUDE.md" (or
  anything that signals this is a bigger/ongoing initiative — a conference
  submission, a project the statistician says they'll keep coming back to)
  at face value rather than second-guessing it. If accepted, Step 7 writes
  it alongside the driver script.

## Step 4 — Write the manifest

Apply everything confirmed in Step 3. **First, actually create the working
folders** — `programs/YYYYMMDD_<slug>/` and `output/shared/YYYYMMDD_<slug>/`
(`<slug>` per Step 3's confirmed or renamed value, dated with today's date) —
now that the statistician has seen and confirmed the name. Everything from
here on (manifest, naming report, cached samples)
writes into `programs/<slug>/`; forest plots go into `output/shared/<slug>/`
(Step 6). **The merged dataset (Step 1's `load_merge_data.R` output) never
moves in from `/tmp`** — per the workflow guide, the PRD+QA merge happens in
code and leaves no separate merged file on the share; re-deriving it from
the source file(s) is cheap and deterministic, so there's nothing worth
persisting. Then write a YAML manifest capturing everything from Step 3 — this
is the traceable artifact that replaces a commented-out R vector. Example
shape:

**Scratch run:** skip folder creation entirely. Create one directory,
`/tmp/bnma_scratch_<slug>/`, and write `manifest.yaml` there instead — same
content, same schema below, only the destination differs. Steps 5/6 point
their own outputs at this same directory (see each step).

```yaml
created_at: "2026-08-14"
source_data:
  prd: /lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_20260805.xlsx
  qa: null
effect_col: pchg_wl_ee # from Step 3's Endpoint question -- the QA/PRD column holding this run's effect estimate; omit = pchg_wl_ee (weight loss), unchanged for every existing manifest
se_col: se_wl_ee # from Step 3 -- the matching SE column; omit = se_wl_ee (weight loss), unchanged for every existing manifest
effect_label: "Body Weight" # optional -- short phrase for the plot's default axis/title text (e.g. "HbA1c", "Physical Function Score"); omit = "Body Weight" only when effect_col is pchg_wl_ee, else falls back to the raw effect_col name (unpolished but not wrong) -- --xlab/--title on make_forest_plot.R always override regardless
effect_direction: decrease_is_better # decrease_is_better | increase_is_better -- from Step 3, only matters if placebo_clamp is used; controls which sign placebo_clamp treats as "wrong direction". omit = decrease_is_better (weight loss/HbA1c-reduction convention), unchanged for every existing manifest
source_program: <path to whatever script/session produced this run>
route_filter: both # oral | injectable | both -- from Step 3; omit or "both" = no route filtering
evidence_filter: both # observed | prediction | both -- from Step 3; omit or "both" = no evidence filtering
compound_filter: null # optional list of compound names -- from Step 2.5's compound-first entry point; omit/null = no compound filtering
region_filter: [global] # list of regions to include -- from Step 3; omit = ["global"] only, unlike route/evidence_filter's "both" default
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
model_type: rand_effect # rand_effect (recommended default for new runs) | fixed_effect | simultaneous (legacy) | simultaneous_fixed (legacy, fixed-effect delta -- use instead of simultaneous whenever effect_type: absolute + a full star network, see Step 5) -- from Step 3; omit or "simultaneous" = today's unconditional phantom-bridging behavior, unchanged; see Step 5
plot_treatments:
  - tirzepatide 5mg qw
  - tirzepatide 10mg qw
  - tirzepatide 15mg qw
effect_type: relative # from Step 3
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
Step 2's `no_placebo_flags` actually found and Step 3 surfaced individually;
`build_batman_data.R` errors on an unrecognized study name (spelling
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
relative-effect information. This is still a stated decision from Step 3,
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
straight into its analysis with no traceability at all. This is a stopgap,
not a permanent home for the data — the row should still get entered as a
real QA row via the project CLAUDE.md's Flow 1 once it's ready, same
"QA is the live working copy" principle as everywhere else in this
workspace. Each entry requires `study_name`, `treatment`, `compound`, this
run's `effect_col`/`se_col` values, and `reason`; `aom`/`region` are
optional:
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
defaults for new runs — see Step 5), **no bridging happens at all**: a study
with no placebo row simply doesn't connect to the network. This isn't a gap
— it's confirmed, documented real-tool behavior (see Step 5), unlike the
earlier connectivity-aware bridging attempt this skill tried and reverted
mid-session for having no such documentation anywhere.

Save it into `programs/<slug>/` (created moments ago, above, per Step 3's
confirmed name), e.g. `study_selection_manifest.yaml`.

**Every study found in step 1's merged data must appear under `studies:`.**
`build_batman_data.R` (step 5) enforces this itself and will refuse to run
otherwise — that's intentional, not a bug to work around.

## Step 5 — Build BATMAN data, fit the model

Materialize Appendix B.4 (`build_batman_data.R`) to this run's lib dir if
not already done this session, then run:

```bash
scripts/run_r.sh scripts/build_batman_data.R \
  --data /tmp/bnma_merged.rds --manifest <manifest.yaml> \
  --batman-out /tmp/bnma_batman.rds --arm-info-out /tmp/bnma_arm_info.rds \
  --study-info-out /tmp/bnma_study_info.rds --arm-rows-out /tmp/bnma_arm_rows.rds
```

If this errors because studies are missing from the manifest, that's the
intended guard — go back to step 3/4 with the user, don't patch around it.

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

`--arm-rows-out` is now part of the default command for every new run — it
feeds two downstream steps: `fit_pooled_placebo_model.R` (see below, for
`effect_type: absolute` runs) and `make_forest_plot.R`'s Step 6
per-treatment "which studies fed this estimate" footnote breakdown.
Existing driver scripts written before this were still fine omitting it —
`fit_pooled_placebo_model.R` errors clearly if it's genuinely needed and
missing, and `make_forest_plot.R` falls back to its older flat, plot-wide
footnote when it's absent, rather than failing.

`build_batman_data.R` also prints a **heterogeneity estimability** check —
for every non-placebo treatment node, how many distinct studies feed it.
This is the checkpoint for the fixed-vs-random-effects question asked in
Step 3: if it reports a **star network** (zero nodes with ≥2 contributing
studies — the exact situation in `pf_nma.R`, a physical-function
sub-network where every comparison has exactly one supporting study),
between-study heterogeneity literally cannot be estimated from the data, and
`model_type: fixed_effect` is the appropriate primary analysis, not a
stylistic preference — quote `pf_nma.R`'s own rationale
("with only 1 study per comparison, between-study heterogeneity cannot be
estimated; fixed-effects is the appropriate primary analysis"). **This
triggers an explicit ask to the user, not a silent auto-correction.** Tell
the user plainly:
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

**Do NOT auto-correct.** The user's Step 3 answer stands unless they
explicitly change it after seeing the star-network finding. If they confirm
`rand_effect` despite the warning, fit with `model_random.txt` as requested
and note in the footnote that the network is a full star and `sigma` is
prior-dominated.

**The same rule applies to `effect_type: absolute` on
`model_simultaneous.txt`/`model_simultaneous_fixed.txt`** — a full star means
`model_simultaneous_fixed.txt` is recommended (deterministic delta), but
if the user explicitly wants `model_simultaneous.txt` after being informed,
proceed with it and note the CI-inflation risk in the footnote. When the
network isn't a full star (some nodes have
multi-study support, even if most don't — this is the common case for the
obesity landscape data, where dozens of single-study nodes coexist with a
handful of well-replicated ones), heterogeneity is estimable from the
network as a whole; surface the node counts for information, but
`rand_effect` vs. `fixed_effect` remains
the analyst's own call, same as always.

Then fit (or load a cached fit of) the model. **Must go through the JAGS
wrapper** — plain `Rscript` will fail to load `rjags` in this environment.
Materialize Appendix D (wrappers) and Appendix B.5 (`fit_bnma_model.R`) to
this run's lib dir if not already done this session, then run:

```bash
scripts/run_with_jags.sh scripts/fit_bnma_model.R \
  --batman /tmp/bnma_batman.rds --model model_random.txt \
  --cache <programs_folder>/samples_<run_name>.rds
```
**Scratch run:** `--cache /tmp/bnma_scratch_<slug>/samples.rds` instead.

**Which model file to use is driven by the manifest's `model_type` field**
(see Step 4's example) — pass the matching file here:
- `model_type: rand_effect` (recommended default for new runs) →
  `--model model_random.txt`
- `model_type: fixed_effect` → `--model model_fixed.txt`
- `model_type: simultaneous` (legacy) or omitted → `--model
  model_simultaneous.txt`
- `model_type: simultaneous_fixed` (legacy, fixed-effect delta) → `--model
  model_simultaneous_fixed.txt` — use this instead of `simultaneous` whenever
  `effect_type: absolute` is requested **and** the network is a full star
  (see the heterogeneity-estimability check above); see below for why.

**MCMC settings and chain initialization follow the real production
package's own documentation** (`EliLillyCo/CMH.BNMA`, provided 2026-08-20 —
supersedes the NMA Output Review Process Guide-derived settings this skill
used before) — n.adapt 10,000, burn-in 10,000, 20,000 sampling iterations
thinned by 10 (3 chains), with chain 1 initialized to exactly 0 on
the baseline (`phi`, and `m` for `model_simultaneous.txt`/
`model_simultaneous_fixed.txt`) and
treatment-effect (`d`) nodes and chains 2–3 drawing from those same nodes'
own vague priors (Normal(0, SD=100)) — all built into `fit_bnma_model.R`
itself, nothing to configure per run. Override via `--n_adapt`/`--n_burnin`/
`--n_iter`/`--thin` if a specific run needs more (e.g. after manually
inspecting the posterior and finding it under-mixed).


`model_random.txt`/`model_fixed.txt` are copied verbatim from the real
production BNMA Shiny app (`BNMA_forest_plot-main.zip`, confirmed
2026-08-17) — non-hierarchical `phi[i]~dnorm(0,0.0001)` baseline per study
(the "separate model per Dias 2013" the NMA Output Review Process Guide
already said was the team's stated standard), `sigma~dunif(0,8)`. The app's
own UI defaults to the random-effect model, which is why this skill now
does too. `fit_bnma_model.R` infers which variables to monitor from the
model file's basename — no extra flag needed, and every existing driver
script that already passes `--model model_simultaneous.txt` explicitly
keeps working unchanged.

`model_simultaneous.txt` (hierarchical/pooled baseline, `sigma~dunif(0,8)`,
corrected 2026-08-19 to match the NMA Output Review Process Guide's explicit
spec for this parameter) stays as a legacy option — it's the only one with a
pooled baseline `m` node, which is required if you need `effect_type: absolute`
(see Step 3); the real production tool has no absolute-effect view at all,
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

**`effect_type: absolute`'s pooled baseline comes from a separate,
standalone pooled-placebo model — not the main model's own `m`/`phi[i]`
nodes at all.** Adopted 2026-08-20 from the real production package's own
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

Run it after Step 5's main fit, against the same run's `arm_rows.rds`.
Materialize Appendix B.6 (`fit_pooled_placebo_model.R`) if not already done
this session:
```bash
scripts/run_with_jags.sh scripts/fit_pooled_placebo_model.R \
  --arm-rows <arm_rows.rds> --cache <placebo_samples.rds> \
  --placebo-data-out <placebo_data.rds>
```
Then pass `--placebo-samples <placebo_samples.rds>` to `make_forest_plot.R`
alongside `--effect absolute`. MCMC settings for this model are its own,
lighter budget (n.adapt 1,000, burn-in 5,000, sampling 10,000, thin 10) —
matching the production package's own settings for this specific model, not
the main model's canonical 10k/10k/20k/10 (see Step 5's MCMC settings note).
Stops with an error if fewer than 2 studies have a usable placebo arm — same
identifiability problem as the main model's own star-network check, just for
`sigma_m` instead of `sigma`: with 1 study, there's no between-study
variance to estimate at all.

**Recommended: also render the pooled-placebo model's own QC plot**, so a
reviewer can see the model is sane rather than trusting the number blind —
`make_forest_plot.R` only ever *consumes* `m`/`sigma_m`, it never shows the
underlying per-study shrinkage. Materialize Appendix B.8
(`make_placebo_forest_plot.R`) if not already done this session:
```bash
scripts/run_r.sh scripts/make_placebo_forest_plot.R \
  --samples <placebo_samples.rds> --placebo-data <placebo_data.rds> \
  --manifest <manifest.yaml> --out <placebo_forest_plot.png>
```
Shows each contributing study's observed vs. posterior-shrunk placebo effect,
the pooled `m`, and the predictive `mu_new` for a hypothetical new study —
adapted 2026-08-21 from a colleague's independent implementation
(`godwill-bnma` branch), which itself mirrors the production app's own
`placebo_forest_plot()`. Not a numbered pipeline step (nothing downstream
consumes its output) — render it whenever `effect_type: absolute` is used,
same "always do this, don't wait to be asked" expectation as Step 7's driver
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
of the fit (not just pre-Step-4 scratch space) — don't let anything delete
`/tmp/bnma_scratch_<slug>/` until the statistician decides promote or
discard (Step 7a).

## Step 6 — Forest plot + footnote

Materialize Appendix B.7 (`make_forest_plot.R`) to this run's lib dir if not
already done this session, then run:

```bash
scripts/run_r.sh scripts/make_forest_plot.R \
  --samples <cache.rds> --arm-info /tmp/bnma_arm_info.rds \
  --study-info /tmp/bnma_study_info.rds --manifest <manifest.yaml> \
  --arm-rows /tmp/bnma_arm_rows.rds \
  --effect relative --out <output_folder>/forest_plot.png
```

The script prints the footnote text it embedded in the plot — surface that
back to the user so they can confirm it's traceable, per the workflow doc's
footnote requirement. With `--arm-rows` passed (the default per Step 5), the
footnote breaks "Contributing studies" out **per treatment** — e.g.
`semaglutide: surmount-1, surmount-4` on its own line — rather than one
flat list for the whole plot, so a reviewer can tell which studies fed
which specific estimate. Without it (older driver scripts), the footnote
falls back to the old flat, plot-wide list. Either way it also includes the
source data path(s) and source program. Save the plot into the matching
dated `output/shared/YYYYMMDD_.../`
folder, not next to the manifest in `programs/`.

**Scratch run:** `--out /tmp/bnma_scratch_<slug>/forest_plot.png` instead.
**Display the image itself either way** (Read tool, same as Step 7 already
requires for the driver script) — a scratch run's entire point is seeing
the result, just without persisting it.

Every plotted treatment label carries a superscript marking its evidence
type — `°` for observed, `ᵖ` for projection, `°ᵖ` for an arm fed by both
(e.g. a shared placebo arm) — so a reviewer QC'ing the PNG can tell which
arms are real trial data vs. modeled without cross-referencing the manifest.
A one-line legend ("° = observed, ᵖ = projection") is appended to the
footnote automatically.

**Never produce both `--effect relative` and `--effect absolute` "for
completeness" unless the user explicitly asked, or the manifest states
`effect_type: both`** — this doubles unrequested output, and the absolute
view needs its own footnote caveat (see Step 5's "modelled, shrunk placebo
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

## Step 7 — Generate the driver script

**Applies to persisted runs only.** For a scratch run (Step 0c/3), skip this
step entirely — a driver script pointing at `/tmp` paths that vanish on
reboot isn't reproducible, so there's nothing useful to generate yet. End
the turn instead with the promote-or-discard offer in Step 7a.

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
   - Caption: source file, studies, estimand, model, date
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

**If Step 3's Project CLAUDE.md item was accepted**, write
`programs/<slug>/CLAUDE.md` in the same turn as the driver script, and show
its contents too (same "must be shown, not just written" rule). Populate it
entirely from the manifest and Step 3's answers already in hand — this is
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
- model_type: <model_type> <"(auto-corrected from X -- full star network)" if applicable>
- Studies excluded: <list + reasons, from manifest, or "none">
- Naming/pooling resolutions: <list, from manifest, or "none">

## Re-running
See `run_bnma_<slug>.R` in this folder — reproduces the fit and plot from
scratch. Full decision record: `manifest.yaml`.
```

## Step 7a — Promoting (or discarding) a scratch run

For a scratch run, end the turn with an explicit summary instead of Step 7's
driver script:

> **SCRATCH RUN** — nothing written to `programs/`, `output/shared/`, or
> `compound_registry.yaml`. Artifacts are in `/tmp/bnma_scratch_<slug>/` and
> won't survive a reboot. Reply **promote** to write this exact run for
> real, or just move on and it's discarded automatically.

**If the statistician replies "promote":**
1. Create `programs/YYYYMMDD_<slug>/` and `output/shared/YYYYMMDD_<slug>/`
   now (same naming Step 4 would have used had this not been a scratch
   run).
2. Copy `manifest.yaml` and `samples.rds` from `/tmp/bnma_scratch_<slug>/`
   into `programs/<slug>/`; copy `forest_plot.png` into
   `output/shared/<slug>/`. **No refitting** — a scratch run's outputs are
   byte-identical to what a persisted run would have produced, since
   nothing in Steps 1-6 branches on where the file ends up, only on what
   path gets passed. Promoting is a filesystem operation, not a re-run.
3. If Step 2 held back a naming-registry resolution for this run, persist
   it now (Edit tool → `compound_registry.yaml`) — it's no longer a
   throwaway decision.
4. Run Step 7 for real: generate and show the driver script.

This is also the answer to "I want to redo this without documenting a
failed attempt" — a scratch run *is* that undocumented iteration space.
Nothing about a discarded scratch run needs mentioning again; there is no
partial artifact on the shared drive to explain away, unlike a persisted
run that turned out wrong.

## Utilities (not numbered pipeline steps)

**`named_contrast.R`** — resolves a contrast between two treatments by name
from an already-fitted run, instead of a hardcoded posterior index (the
exact anti-pattern this replaces, seen in real analyst code:
`TZP15_vs_Sema72 <- d[18] - d[89]`, silently wrong if treatment order ever
shifts). Cherry-picked from `atlas`, 2026-08-19. Materialize Appendix B.9
(`named_contrast.R`) to this session's lib dir if not already done, then
run:
```bash
scripts/run_r.sh scripts/named_contrast.R \
  --samples <cache.rds> --arm-info <arm_info.rds> \
  --treat1 "<treatment name>" --treat2 "<treatment name>" [--out <contrast.yaml>]
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
  model (Step 5's `fit_pooled_placebo_model.R`, adopted from
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

## Appendix A — JAGS Model Text (embedded, no external files needed)

These are the exact model definitions this skill uses. During the session,
write the chosen model to a temp file via `cat('...', file = model_path)`.
In the standalone driver script (Step 7), paste it inline the same way.

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

### A4. Pooled-placebo meta-analysis (`model_placebo_random.txt`)

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
`/tmp/cmh_ci_lib/<name>.R` before Step 4's folders exist,
`programs/<slug>/lib/<name>.R` after) via `cat('...', file = <path>)`, then
invoke it exactly as shown in the step that references it — same pattern
Appendix A already uses for the JAGS model text.

### B1. `lib_common.R`

Shared helpers sourced by every other script below (never run directly): squish_ws(), parse_args(), read_sheet_with_fallback(), stringify_all()/recast_numeric_cols(), and compute_heterogeneity_estimability()/print_heterogeneity_estimability() (the star-network check Step 5 relies on).

```r
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
```

### B2. `load_merge_data.R`

Step 1 — loads QA + PRD workbooks and merges them (QA wins on (study_name, treatment) collision), tagging every row's source_tier/source_sheet/region.

```r
#!/usr/bin/env Rscript
# Step 1 of the /bnma skill: load QA + PRD data and merge into one data.frame.
#
# Join logic (documented here per GUIDE_README.md Flow 2 step 4 — merge
# happens in code, not as a shared preprocessing file):
#   - PRD is the cumulative, lead-team-curated tier and is always the base.
#   - QA (optional) holds newer entries not yet promoted to PRD. Any QA row
#     matching an existing PRD row on (study_name, treatment) is treated as
#     an update to that row and wins (kept), using its own time_entry as the
#     tie-breaker when both exist. QA rows with no PRD match are additions.
#   - Both tiers' Observed and Prediction sheets are read (by name, with a
#     fallback to positional sheet 2/3 for older workbooks — see
#     lib_common.R's read_sheet_with_fallback) and tagged with source_tier /
#     source_sheet columns so downstream steps and the footnote can trace
#     every row back to where it came from.
#
# Usage:
#   Rscript load_merge_data.R [--prd <path.xlsx>] [--qa <path.xlsx>] --out <merged.rds>
#
# At least one of --prd/--qa must be given. Both are optional individually
# (not just --qa) so a QA-only run -- e.g. no cumulative PRD file has been
# copied in for this dataset -- tags its rows source_tier="qa" correctly,
# rather than being forced through --prd and mislabeled "prd".

suppressPackageStartupMessages({
  library(readxl)
  library(dplyr)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
source(file.path(dirname(normalizePath(script_path)), "lib_common.R"))

args <- parse_args(list(
  prd = list(default = NULL),
  qa  = list(default = NULL),
  out = list(required = TRUE)
))

if (is.null(args$prd) && is.null(args$qa)) {
  stop("At least one of --prd or --qa must be given.")
}

# A workbook's standard "Observed"/"Prediction" sheets are tagged
# region="global". Some workbooks also carry a region-scoped extra sheet
# (found in practice: a "China Observed" sheet alongside the standard ones)
# -- any sheet matching "<Region> Observed" or "<Region> Prediction"
# (case-insensitive) is read the same way and tagged with that region,
# lowercased, instead of "global". This is read into every merge
# unconditionally (same as the standard sheets); `region_filter` in
# build_batman_data.R is what actually scopes a run to global-only or a
# specific region -- load time just needs to capture that the rows exist
# and where they came from.
region_sheet_pattern <- "^(.*)\\s+(Observed|Prediction)$"

load_tier <- function(path, tier_label) {
  if (is.null(path)) return(NULL)
  if (!file.exists(path)) stop("File not found for --", tier_label, ": ", path)

  sheets <- excel_sheets(path)
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

  # Case-insensitive exclusion (matches read_sheet_with_fallback's own
  # case-insensitive name match above) -- otherwise a lowercase "observed"/
  # "prediction" sheet would remain in extra_sheets and get needlessly
  # checked against the region-sheet regex below.
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

  if (length(parts) == 0) {
    stop("Neither an Observed nor a Prediction sheet was found in ", path)
  }
  bind_rows(parts)
}

prd_data <- load_tier(args$prd, "prd")
qa_data  <- load_tier(args$qa, "qa")

if (is.null(prd_data)) {
  merged <- qa_data
} else if (is.null(qa_data)) {
  merged <- prd_data
} else {
  # QA rows matching an existing PRD (study_name, treatment) pair are updates
  # and win; QA rows with no match are new additions. Both cases: just prefer
  # QA over PRD on key collision, keep everything else.
  key <- function(df) paste(df$study_name, df$treatment, sep = "")
  prd_keys <- key(prd_data)
  qa_keys  <- key(qa_data)
  merged <- bind_rows(
    prd_data %>% filter(!prd_keys %in% qa_keys),
    qa_data
  )
}

# Some QA workbooks carry leftover derived columns from a prior analysis run
# (study_ind, arm_ind, treat) that were never supposed to persist in the
# source file (GUIDE_README.md: "study_ind, arm_ind (re-derived at analysis
# time, not stored)") -- found via testing against a real T2D QA file whose
# Prediction sheet already had a `treat` column, colliding with this script's
# own rename() step downstream. Drop them defensively; this pipeline always
# recomputes its own indices, so any pre-existing ones can't be trusted
# anyway (they'd reflect some other, unrelated arm-numbering scheme).
merged <- merged %>% select(-any_of(c("study_ind", "arm_ind", "treat")))

merged <- merged %>%
  mutate(
    compound  = tolower(squish_ws(compound)),
    treatment = tolower(squish_ws(treatment)),
    study_name = tolower(squish_ws(study_name))
  ) %>%
  recast_numeric_cols()

saveRDS(merged, args$out)
cat(
  "Merged", nrow(merged), "rows (",
  sum(merged$source_tier == "prd"), "from PRD,",
  sum(merged$source_tier == "qa"), "from QA ).\n",
  "Studies:", n_distinct(merged$study_name), "  Compounds:", n_distinct(merged$compound), "\n",
  "Written to:", args$out, "\n"
)
```

### B3. `check_naming_pooling.R`

Step 2 — the naming/pooling QA gate: near-duplicate compound spelling, route-pooling collisions, placebo mistagging/pbo-alias, placebo-naming variants, and no-placebo-arm studies.

```r
#!/usr/bin/env Rscript
# Step 2 of the /bnma skill: the naming/pooling QA gate. Runs before any
# study-selection is offered, so that step is grounded in already-vetted
# compound names and treatment/route labels. Never edits the input data --
# only produces a report for a human (or the calling skill conversation) to
# act on.
#
# Two independent checks, documented in DESIGN.md:
#
# 1. Near-duplicate compound spelling. No signal here *proves* two spellings
#    are the same real compound -- this only ranks candidates for review:
#      - "high" tier: one name is a substring of the other (e.g. "canaflig"
#        in "canafligizon") -- matches the actual failure mode of a dev code
#        name drifting into a full INN name, or a truncated entry.
#      - "low" tier: normalized edit distance below a conservative threshold.
#        Shown separately because GLP-1/GIP-class drugs share suffixes
#        systematically (-glutide, -tide, -trutide) -- edit distance alone
#        would flag real, distinct compounds constantly.
#      - Suppressed entirely if the two names ever appear as separate arms
#        within the same study_name -- that's a head-to-head comparison,
#        strong evidence they're genuinely different compounds.
#      - Skipped entirely if the pair is already in compound_registry.yaml's
#        resolved_pairs.
#
# 2. Route-pooling risk. Mechanical, not fuzzy: for compounds with more than
#    one distinct `aom` (route) value, flag any exact `treatment` string
#    shared across routes (the literal bug -- arm_ind comes from
#    unique(treatment), so such rows collapse into one arm) and any compound
#    with missing/mixed `aom` recording.
#
# Usage:
#   Rscript check_naming_pooling.R --data <merged.rds> [--registry <registry.yaml>] --out <report.json>

suppressPackageStartupMessages({
  library(dplyr)
  library(yaml)
  library(jsonlite)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  data     = list(required = TRUE),
  registry = list(default = file.path(dirname(script_dir), "compound_registry.yaml")),
  out      = list(required = TRUE),
  edit_distance_threshold = list(default = "0.25")
))

EDIT_THRESHOLD <- as.numeric(args$edit_distance_threshold)

merged <- readRDS(args$data)
registry <- if (file.exists(args$registry)) yaml::read_yaml(args$registry) else list()
resolved_pairs <- registry$resolved_pairs %||% list()

pair_key <- function(a, b) paste(sort(c(a, b)), collapse = "|||")

is_resolved <- function(a, b) {
  if (length(resolved_pairs) == 0) return(FALSE)
  target <- pair_key(a, b)
  any(vapply(resolved_pairs, function(p) pair_key(p$a, p$b) == target, logical(1)))
}

# ---------------------------------------------------------------------------
# Check 1: near-duplicate compound spelling
# ---------------------------------------------------------------------------
compounds <- merged$compound %>%
  unique() %>%
  na.omit() %>%
  setdiff("placebo") %>%
  sort()

# study_name sets per compound, to test same-study co-occurrence
studies_by_compound <- split(merged$study_name, merged$compound)

compound_flags <- list()
if (length(compounds) >= 2) {
  pairs <- combn(compounds, 2, simplify = FALSE)
  for (p in pairs) {
    a <- p[1]; b <- p[2]
    if (a == b) next
    if (is_resolved(a, b)) next

    is_substring <- (nchar(a) >= 4 && nchar(b) >= 4) &&
      (grepl(a, b, fixed = TRUE) || grepl(b, a, fixed = TRUE))
    edit_ratio <- adist(a, b)[1, 1] / max(nchar(a), nchar(b))

    tier <- if (is_substring) {
      "high"
    } else if (edit_ratio <= EDIT_THRESHOLD) {
      "low"
    } else {
      NA_character_
    }
    if (is.na(tier)) next

    shared_studies <- intersect(studies_by_compound[[a]], studies_by_compound[[b]])
    suppressed <- length(shared_studies) > 0

    compound_flags[[length(compound_flags) + 1]] <- list(
      compound_a = a,
      compound_b = b,
      tier = tier,
      edit_distance_ratio = round(edit_ratio, 3),
      is_substring = is_substring,
      suppressed = suppressed,
      suppressed_reason = if (suppressed) {
        paste0(
          "co-occur as separate arms in ", length(shared_studies),
          " shared study/ies (e.g. '", shared_studies[1], "') -- ",
          "likely genuinely distinct compounds, not a naming duplicate"
        )
      } else {
        NA_character_
      }
    )
  }
}

# ---------------------------------------------------------------------------
# Check 2: route (aom) pooling risk
# ---------------------------------------------------------------------------
pooling_flags <- list()
has_aom <- "aom" %in% names(merged)

if (has_aom) {
  by_compound <- merged %>%
    filter(compound != "placebo") %>%
    group_by(compound) %>%
    summarise(
      aom_values = list(unique(aom)),
      .groups = "drop"
    )

  for (i in seq_len(nrow(by_compound))) {
    cmpd <- by_compound$compound[i]
    aoms <- by_compound$aom_values[[i]]
    distinct_non_na <- unique(na.omit(aoms))
    if (length(distinct_non_na) < 2 && !any(is.na(aoms))) next # single route, fully recorded: nothing to check

    rows <- merged %>% filter(compound == cmpd)

    if (length(distinct_non_na) >= 2) {
      collisions <- rows %>%
        filter(!is.na(aom)) %>%
        group_by(treatment) %>%
        summarise(n_routes = n_distinct(aom), routes = list(unique(aom)), .groups = "drop") %>%
        filter(n_routes > 1)

      for (j in seq_len(nrow(collisions))) {
        pooling_flags[[length(pooling_flags) + 1]] <- list(
          kind = "route_collision",
          compound = cmpd,
          treatment = collisions$treatment[j],
          routes = collisions$routes[[j]],
          message = paste0(
            "'", collisions$treatment[j], "' (", cmpd, ") appears under ",
            "routes [", paste(collisions$routes[[j]], collapse = ", "), "] -- ",
            "these rows will collapse into ONE treatment arm (arm_ind is ",
            "derived from the treatment string alone), silently pooling ",
            "different routes of administration."
          )
        )
      }
    }

    if (any(is.na(aoms))) {
      pooling_flags[[length(pooling_flags) + 1]] <- list(
        kind = "missing_route",
        compound = cmpd,
        treatment = NA_character_,
        routes = list(),
        message = paste0(
          "'", cmpd, "' has rows with no `aom` recorded -- route can't be ",
          "confirmed, so an accidental oral/injectable pooling can't be ",
          "ruled out for this compound."
        )
      )
    }
  }
}

# ---------------------------------------------------------------------------
# Check 3: placebo rows mistagged with an active-drug compound
# ---------------------------------------------------------------------------
# Neither a naming-similarity nor a route-pooling issue -- a distinct data-
# entry integrity check. Found via testing against real PRD data: a placebo
# arm (treatment == "placebo") occasionally carries the study's active-drug
# compound in the `compound` column instead of "placebo"/NA. build_batman_data.R
# hardens against this (arm_ind 1's compound is always forced to "placebo"
# regardless of what's in the raw data), but it's still flagged here so a
# curator can fix it at the source.
integrity_flags <- list()
mistagged <- merged %>% filter(treatment == "placebo", !is.na(compound), compound != "placebo")
if (nrow(mistagged) > 0) {
  for (i in seq_len(nrow(mistagged))) {
    integrity_flags[[length(integrity_flags) + 1]] <- list(
      kind = "placebo_mistag",
      study_name = mistagged$study_name[i],
      compound = mistagged$compound[i],
      message = paste0(
        "Study '", mistagged$study_name[i], "' has a treatment == 'placebo' row ",
        "tagged with compound = '", mistagged$compound[i], "' instead of 'placebo' ",
        "-- likely a data-entry error. The BNMA model itself keys off the treatment ",
        "string (not compound), so this shouldn't corrupt the fit, but it can mislabel ",
        "the placebo arm's color/legend in the forest plot unless corrected at the source."
      )
    )
  }
}

# `compound == "pbo"` is a real, documented convention this skill's own
# checks previously missed entirely -- confirmed 2026-08-20 against the real
# production package's own placebo_name(): `grep("^placebo$|^pbo$", ...,
# ignore.case = TRUE)`. Every check/filter in this pipeline keys off
# `compound == "placebo"` specifically (route exemption, placebo_clamp,
# arm_ind ordering's fallback), and "placebo" is excluded from Check 1's own
# compound-similarity comparison set below -- so a compound literally spelled
# "pbo" would previously have gone completely unflagged (not compared
# against "placebo" at all, since that string isn't in the comparison list)
# and been treated as some unrelated 28th drug, not the reference arm.
pbo_rows <- merged %>% filter(compound == "pbo")
if (nrow(pbo_rows) > 0) {
  affected_studies <- unique(pbo_rows$study_name)
  integrity_flags[[length(integrity_flags) + 1]] <- list(
    kind = "pbo_compound_alias",
    study_name = NA_character_,
    compound = "pbo",
    message = paste0(
      "compound == 'pbo' found in ", length(affected_studies), " study/ies (",
      paste(head(affected_studies, 5), collapse = ", "),
      if (length(affected_studies) > 5) ", ..." else "",
      ") -- a real placebo alias (matches the production tool's own placebo_name() ",
      "regex) that every check/filter in this pipeline will otherwise treat as an ",
      "unrelated compound. Propose a compound_relabels entry: 'pbo' -> 'placebo'."
    )
  )
}

# ---------------------------------------------------------------------------
# Check 4a: placebo-arm naming variants
# ---------------------------------------------------------------------------
# Found via testing against real T2D HbA1c PRD data, 2026-08-20: several
# studies record their placebo arm's `treatment` as "oral placebo qd",
# "injectable placebo qw", "injectable placebo qd", or "placebo qw" --
# `compound` is correctly "placebo" for every one of them, only the
# treatment STRING varies. This is more than a cosmetic naming issue --
# build_batman_data.R's arm_ind assignment is keyed off the literal
# treatment string (matches the skill's own "arm_ind is derived from the
# treatment string alone" invariant used everywhere else, e.g. Check 2's
# route-collision logic), so each differently-worded placebo row becomes
# its OWN separate, single-study, disconnected network node instead of
# sharing the one placebo reference arm every other study anchors to --
# silently fragmenting the network's connectivity, not just a label
# inconsistency. The dominant convention in this same dataset already uses
# a bare "placebo" string across BOTH oral and injectable rows (route
# filtering already exempts placebo from route matching for exactly this
# reason), so collapsing these variants onto it is consistent with the
# data's own existing convention, not a new one.
placebo_naming_flags <- list()
placebo_variants <- merged %>%
  filter(compound == "placebo", treatment != "placebo") %>%
  distinct(treatment) %>%
  pull(treatment)
if (length(placebo_variants) > 0) {
  for (pv in placebo_variants) {
    affected_studies <- merged %>% filter(compound == "placebo", treatment == pv) %>% pull(study_name) %>% unique()
    placebo_naming_flags[[length(placebo_naming_flags) + 1]] <- list(
      kind = "placebo_naming_variant",
      treatment = pv,
      affected_studies = affected_studies,
      message = paste0(
        "'", pv, "' is a placebo row (compound == 'placebo') under a non-canonical ",
        "treatment string -- without a treatment_relabels entry to 'placebo', ", "affects ",
        length(affected_studies), " study/ies (", paste(head(affected_studies, 5), collapse = ", "),
        if (length(affected_studies) > 5) ", ..." else "",
        ") and will each become their own disconnected single-study node instead of ",
        "sharing the network's one placebo reference arm."
      )
    )
  }
}

# ---------------------------------------------------------------------------
# Check 4b: studies with no placebo arm at all
# ---------------------------------------------------------------------------
# Only matters for model_type rand_effect/fixed_effect -- build_batman_data.R
# leaves such a study disconnected from the network by default (matches the
# real production tool's own documented behavior), unless the manifest opts
# it into phantom-bridging via `phantom_placebo_studies` (see SKILL.md Step
# 3/4). Computed here (pre-study-selection, pre-model_type-finalization) so
# every such study can be surfaced in Step 3's one consolidated ask rather
# than discovered only once build_batman_data.R runs. A study excluded from
# this run entirely (Step 3 studies: list) makes this moot for it, same as
# any other flag here -- the skill conversation reconciles that at Step 3,
# not this script.
#
# Keyed off `compound == "placebo"`, NOT the literal treatment string --
# using the treatment string here would double-count every Check 4a variant
# as "no placebo" too (a study can easily have a real placebo arm recorded
# under one of those variant strings and nothing else), which is exactly the
# false-positive this fix replaces: real case, 2026-08-20, several studies
# whose placebo arm was "oral placebo qd" showed up here as falsely having
# no placebo arm at all.
no_placebo_flags <- list()
studies_with_placebo_all <- merged %>% filter(compound == "placebo") %>% pull(study_name) %>% unique()
studies_without_placebo_all <- setdiff(unique(merged$study_name), studies_with_placebo_all)
if (length(studies_without_placebo_all) > 0) {
  for (sn in studies_without_placebo_all) {
    treats <- merged %>% filter(study_name == sn) %>% pull(treatment) %>% unique()
    no_placebo_flags[[length(no_placebo_flags) + 1]] <- list(
      study_name = sn,
      treatments = treats,
      message = paste0(
        "'", sn, "' has no 'placebo' row -- under model_type rand_effect/fixed_effect this study ",
        "won't connect to the network by default (baseline estimate only, no relative-effect ",
        "information) unless opted into phantom-bridging via phantom_placebo_studies."
      )
    )
  }
}

report <- list(
  compound_flags = compound_flags,
  pooling_flags = pooling_flags,
  integrity_flags = integrity_flags,
  placebo_naming_flags = placebo_naming_flags,
  no_placebo_flags = no_placebo_flags,
  summary = list(
    n_compounds_checked = length(compounds),
    n_compound_flags = length(compound_flags),
    n_compound_flags_active = sum(vapply(compound_flags, function(f) !f$suppressed, logical(1))),
    n_pooling_flags = length(pooling_flags),
    n_integrity_flags = length(integrity_flags),
    n_placebo_naming_flags = length(placebo_naming_flags),
    n_no_placebo_flags = length(no_placebo_flags)
  )
)

jsonlite::write_json(report, args$out, auto_unbox = TRUE, pretty = TRUE, na = "null")

cat("Naming/pooling QA gate report written to:", args$out, "\n")
cat(
  "  Compounds checked:", report$summary$n_compounds_checked, "\n",
  "  Compound flags:", report$summary$n_compound_flags,
  "(", report$summary$n_compound_flags_active, "active,",
  report$summary$n_compound_flags - report$summary$n_compound_flags_active, "suppressed )\n",
  "  Pooling flags:", report$summary$n_pooling_flags, "\n",
  "  Integrity flags (placebo mistagging):", report$summary$n_integrity_flags, "\n",
  "  Placebo naming variants (need a treatment_relabels entry):", report$summary$n_placebo_naming_flags, "\n",
  "  Studies with no placebo arm:", report$summary$n_no_placebo_flags,
  "(relevant only if model_type ends up rand_effect/fixed_effect -- see SKILL.md Step 3)\n"
)
```

### B4. `build_batman_data.R`

Steps 3+4/5 — applies the confirmed manifest (filters, relabels, exclusions, placebo_clamp, se_fallback, supplementary_data, phantom-placebo bridging) and builds the BATMAN/JAGS input matrices. Refuses to run if any study is missing an include/exclude decision.

```r
#!/usr/bin/env Rscript
# Step 3+4 of the /bnma skill: apply a confirmed study-selection manifest to
# the merged data, then BATMAN-augment and build the JAGS input matrices.
#
# The manifest (written by the skill conversation after the user explicitly
# confirms study inclusion/exclusion -- see SKILL.md) must list EVERY study
# present in the usable merged data. This script validates that and REFUSES
# TO RUN otherwise -- that hard failure is what makes "no silent default
# selection" a real guarantee instead of a social convention, closing the
# gap that let a low-dose Phase 2 study slip into a prior analysis unnoticed.
#
# Usage:
#   Rscript build_batman_data.R --data <merged.rds> --manifest <manifest.yaml> \
#     --batman-out <batman.rds> --arm-info-out <arm_info.rds> --study-info-out <study_info.rds>

suppressPackageStartupMessages({
  library(dplyr)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  data            = list(required = TRUE),
  manifest        = list(required = TRUE),
  batman_out      = list(required = TRUE),
  arm_info_out    = list(required = TRUE),
  study_info_out  = list(required = TRUE),
  arm_rows_out    = list(default = NULL)
))

merged <- readRDS(args$data)
manifest <- yaml::read_yaml(args$manifest)

if (is.null(manifest$studies) || length(manifest$studies) == 0) {
  stop(
    "Manifest has no `studies` entries. Every study found in the data must ",
    "have an explicit include/exclude decision before a model can be run -- ",
    "see SKILL.md step 3."
  )
}

# Endpoint columns -- which QA/PRD column holds this run's effect estimate
# and SE. Default to the weight-loss schema's own column pair so every
# existing manifest (none of which set these fields) keeps working
# unchanged; a run against a different endpoint (HbA1c, physical function,
# etc.) states its own real column names here instead (see SKILL.md Step 3's
# Endpoint question). effect_direction only matters for placebo_clamp below
# -- which sign counts as "wrong direction" depends on whether a decrease or
# an increase is the desired treatment effect for this endpoint.
effect_col <- manifest$effect_col %||% "pchg_wl_ee"
se_col <- manifest$se_col %||% "se_wl_ee"
effect_direction <- manifest$effect_direction %||% "decrease_is_better"
if (!effect_direction %in% c("decrease_is_better", "increase_is_better")) {
  stop("effect_direction must be 'decrease_is_better' or 'increase_is_better', got: ", effect_direction)
}
if (!effect_col %in% names(merged)) {
  stop(
    "effect_col '", effect_col, "' not found in the merged data's columns. ",
    "Check the manifest's effect_col against this workbook's actual column ",
    "name for this endpoint -- available columns: ", paste(names(merged), collapse = ", ")
  )
}
if (!se_col %in% names(merged)) {
  stop(
    "se_col '", se_col, "' not found in the merged data's columns. Check ",
    "the manifest's se_col against this workbook's actual column name for ",
    "this endpoint -- available columns: ", paste(names(merged), collapse = ", ")
  )
}
cat("Endpoint columns: effect_col='", effect_col, "', se_col='", se_col, "', effect_direction='", effect_direction, "'\n", sep = "")

# Phantom placebo rows below must mirror the actual runtime type of
# effect_col/se_col, not assume one -- confirmed by testing (2026-08-20/
# 2026-08-21): load_merge_data.R's recast_numeric_cols() casts the fixed
# QA_NUMERIC_COLS list (pchg_wl_ee/se_wl_ee, the weight-loss defaults) to
# numeric during merge, but any OTHER effect_col/se_col (a custom endpoint,
# e.g. HbA1c's chg_hba1c) stays character until this script's own later
# as.numeric() casts. A hardcoded NA_real_/1 breaks bind_rows() for a custom
# endpoint (character vs. double); a hardcoded NA_character_/"1" breaks it
# right back for the weight-loss default (double vs. character) -- neither
# constant is safe on its own, only matching whichever type this run's data
# actually is.
na_like  <- function(x) if (is.numeric(x)) NA_real_ else NA_character_
one_like <- function(x) if (is.numeric(x)) 1 else "1"

# SE fallback -- derive se_col = sd/sqrt(n) for rows missing se_col but
# with a known arm sample size n. This is a real, repeated team convention
# for the weight-loss endpoint specifically, not a one-off: redefine1's own
# curator_note documents it verbatim ("se is calculated with 10/sqrt(n)
# where sd=10 is commonly used for %change in body weight in nont2d"), and
# it's actually *applied* (not just written down) in
# brenipatide_gzmu_misc5.R and brenipatide_gzmu_gzmd.R. Runs before
# the unusable-row filter below so a rescued row survives it, same as any
# row that already had a real se_col value. Opt-in and reasoned, same pattern as
# placebo_clamp -- unlike placebo_clamp, this is judged common enough across
# real datasets to offer as a standing manifest field rather than a
# one-off (per the user, 2026-08-19), but it still defaults to off:
# fabricating an SE for a row that never had a data-quality decision made
# about it must be a deliberate, visible choice, not silent. se_fallback_sd's
# own default (10) is the weight-loss convention's value, not a generic
# statistical constant -- a different endpoint using se_fallback should pass
# its own se_fallback_sd, not rely on this default.
if (isTRUE(manifest$se_fallback)) {
  if (is.null(manifest$se_fallback_reason) || !nzchar(trimws(manifest$se_fallback_reason))) {
    stop(
      "se_fallback is true but se_fallback_reason is missing/blank -- this can ",
      "rewrite an arbitrary number of rows' ", se_col, " values, so (like ",
      "placebo_clamp) it needs a documented reason, not just a logged default."
    )
  }
  fallback_sd <- as.numeric(manifest$se_fallback_sd %||% 10)
  se_num <- suppressWarnings(as.numeric(merged[[se_col]]))
  n_num  <- suppressWarnings(as.numeric(merged$n))
  needs_fallback <- is.na(se_num) & !is.na(n_num) & n_num > 0
  n_rescued <- sum(needs_fallback)
  if (n_rescued > 0) {
    rescued_studies <- unique(merged$study_name[needs_fallback])
    cat(
      n_rescued, "row(s) with missing", se_col, "but known n given a derived SE (",
      fallback_sd, "/ sqrt(n)) -- reason:", manifest$se_fallback_reason, "\n",
      "  Affected studies:", paste(rescued_studies, collapse = ", "), "\n"
    )
    merged[[se_col]][needs_fallback] <- fallback_sd / sqrt(n_num[needs_fallback])
  }
}

# Rows unusable regardless of any selection decision (not a study-selection
# choice, just a data-quality precondition) -- same filter the existing
# misc5 scripts apply, made explicit and logged here.
usable <- merged %>% filter(!is.na(suppressWarnings(as.numeric(.data[[se_col]]))))
dropped_unusable <- setdiff(unique(merged$study_name), unique(usable$study_name))
if (length(dropped_unusable) > 0) {
  cat(
    "Dropped as unusable (non-numeric/missing ", se_col, " for every row):\n  ",
    paste(dropped_unusable, collapse = ", "), "\n", sep = ""
  )
}

# Supplementary data -- literal rows for data that hasn't been promoted into
# the QA/PRD workbook yet (e.g. a hand-digitized dose-response series from a
# slide deck). Found via bnma-nonadj-11AUG2026.R, which bind_rows() a
# hand-typed brenipatide tibble straight into its analysis with no
# traceability; this is the same capability, but as an explicit, reasoned
# manifest entry instead of a silent literal in a script. Bound in here,
# before row_exclusions/relabels/placebo_clamp/the scope filters, so these
# rows flow through the entire normal pipeline just like any other row --
# the only exemption is evidence_filter (see below), since "supplementary"
# isn't a meaningful point on the observed/prediction axis.
if (!is.null(manifest$supplementary_data)) {
  required_fields <- c("study_name", "treatment", "compound", effect_col, se_col, "reason")
  supp_rows <- lapply(seq_along(manifest$supplementary_data), function(i) {
    entry <- manifest$supplementary_data[[i]]
    missing_fields <- setdiff(required_fields, names(entry))
    if (length(missing_fields) > 0) {
      stop(
        "supplementary_data entry ", i, " is missing required field(s): ",
        paste(missing_fields, collapse = ", "), " -- every entry needs ",
        paste(required_fields, collapse = ", "), " (the effect/SE field names ",
        "must match this manifest's own effect_col/se_col)."
      )
    }
    row_df <- data.frame(
      # Normalized the same way load_merge_data.R normalizes every other
      # row (tolower + squish_ws) -- otherwise a supplementary row's
      # study_name/treatment/compound/aom could silently fail to match the
      # manifest's studies:/plot_treatments/route_filter comparisons purely
      # on casing or stray whitespace.
      study_name = tolower(squish_ws(entry$study_name)),
      treatment = tolower(squish_ws(entry$treatment)),
      compound = tolower(squish_ws(entry$compound)),
      aom = if (is.null(entry$aom)) NA_character_ else tolower(squish_ws(entry$aom)),
      region = tolower(squish_ws(entry$region %||% "global")),
      source_tier = "supplementary",
      source_sheet = "supplementary",
      stringsAsFactors = FALSE
    )
    row_df[[effect_col]] <- as.numeric(entry[[effect_col]])
    row_df[[se_col]] <- as.numeric(entry[[se_col]])
    row_df
  })
  supp_df <- bind_rows(supp_rows)
  cat(
    "Supplementary data: ", nrow(supp_df), " hand-added row(s) across ",
    n_distinct(supp_df$study_name), " study/ies:\n"
  )
  for (i in seq_along(manifest$supplementary_data)) {
    entry <- manifest$supplementary_data[[i]]
    cat("  ", entry$study_name, "/", entry$treatment, " -- reason:", entry$reason, "\n")
  }
  usable <- bind_rows(usable, supp_df)
}

# Row-level exclusions (e.g. a single anomalous/likely-erroneous row within an
# otherwise-included study) -- a study-level include/exclude decision can't
# express this, so the manifest supports an optional `row_exclusions` list.
# Every entry must actually match a row still present at this point, or the
# script stops -- silently matching zero rows (e.g. a stale exclusion after
# the underlying data changed) is exactly the kind of quiet drift this skill
# exists to prevent. An optional `n` field disambiguates two literal duplicate
# rows sharing the same (study_name, treatment) -- found via testing against
# real data (solstice's elecoglipron 75mg qd had two identical-looking rows
# differing only in n and the reported value). Without `n`, an entry matching
# more than one row is ALSO an error -- ambiguous exclusions are exactly as
# unsafe as ones matching zero.
#
# MANIFEST AUTHORING GOTCHA: write the key as quoted `"n": 37`, not bare
# `n: 37` -- YAML 1.1 (which the `yaml` package follows) parses a bare `n`
# (also `y`/`yes`/`no`/`on`/`off`) as the boolean FALSE, not the string "n",
# so an unquoted key silently vanishes and this block never disambiguates
# anything. Hit this exact bug once already; quoting the key is what fixes it.
if (!is.null(manifest$row_exclusions)) {
  for (ex in manifest$row_exclusions) {
    match_idx <- which(usable$study_name == ex$study_name & usable$treatment == ex$treatment)
    if (!is.null(ex$n)) {
      match_idx <- match_idx[usable$n[match_idx] == ex$n]
    }
    if (length(match_idx) == 0) {
      stop(
        "row_exclusions entry matched no rows: study_name='", ex$study_name,
        "', treatment='", ex$treatment, "'",
        if (!is.null(ex$n)) paste0(", n=", ex$n) else "",
        " -- check the manifest against the current data (it may have ",
        "changed since this exclusion was written)."
      )
    }
    if (length(match_idx) > 1) {
      stop(
        "row_exclusions entry matched ", length(match_idx), " rows (ambiguous): ",
        "study_name='", ex$study_name, "', treatment='", ex$treatment, "' -- add ",
        "an `n` field (or another discriminator) to pick exactly one row."
      )
    }
    cat(
      "Excluding", length(match_idx), "row(s): study='", ex$study_name,
      "' treatment='", ex$treatment, "' -- reason:", ex$reason %||% "(none given)", "\n"
    )
    usable <- usable[-match_idx, ]
  }
}


# Compound relabels -- for a naming-QA flag resolved as "these rows were
# mislabeled, merge into the canonical spelling" (as opposed to "these are
# genuinely different compounds, just noted"). Applied globally by compound
# string, since that's what the naming-QA gate flags on. Same
# match-or-stop-loudly guarantee as row_exclusions above.
if (!is.null(manifest$compound_relabels)) {
  for (rl in manifest$compound_relabels) {
    match_idx <- which(usable$compound == rl$from)
    if (length(match_idx) == 0) {
      stop(
        "compound_relabels entry matched no rows: from='", rl$from, "' -- check ",
        "the manifest against the current data (it may have changed since this ",
        "relabel was written)."
      )
    }
    cat(
      "Relabeling", length(match_idx), "row(s): compound '", rl$from, "' -> '",
      rl$to, "' -- reason:", rl$reason %||% "(none given)", "\n"
    )
    usable$compound[match_idx] <- rl$to
  }
}

# Treatment relabels -- for a naming-QA flag resolved as "these rows use a
# different label for what is the same treatment" (e.g. a mislabeled dose
# string). Applied globally by treatment string, matching the same
# match-or-stop-loudly guarantee as compound_relabels above. Unlike
# compound_relabels (identity of the drug), this changes which arm_ind a row
# maps to -- use it deliberately.
if (!is.null(manifest$treatment_relabels)) {
  for (rl in manifest$treatment_relabels) {
    match_idx <- which(usable$treatment == rl$from)
    if (length(match_idx) == 0) {
      stop(
        "treatment_relabels entry matched no rows: from='", rl$from, "' -- check ",
        "the manifest against the current data (it may have changed since this ",
        "relabel was written)."
      )
    }
    cat(
      "Relabeling", length(match_idx), "row(s): treatment '", rl$from, "' -> '",
      rl$to, "' -- reason:", rl$reason %||% "(none given)", "\n"
    )
    usable$treatment[match_idx] <- rl$to
  }
}

# Placebo clamp -- forces any placebo row reporting a "wrong direction"
# effect_col value to 0. Found via bnma-nonadj-11AUG2026.R, which applies this
# unconditionally with no manifest equivalent, and no effect_direction concept
# at all since it only ever ran on weight-loss data ("Yongming advised
# setting the placebo effect to zero" -- a positive/weight-gain value there).
# Opt-in and reasoned here, same pattern as every
# other manifest field -- absent means today's behavior (no clamping),
# unchanged. Requires a reason (hard stop, not just logged) because unlike a
# single row_exclusions entry, this can silently rewrite an arbitrary number
# of rows' values across the whole run.
if (isTRUE(manifest$placebo_clamp)) {
  if (is.null(manifest$placebo_clamp_reason) || !nzchar(trimws(manifest$placebo_clamp_reason))) {
    stop(
      "placebo_clamp is true but placebo_clamp_reason is missing/blank -- ",
      "this rewrites placebo values across the whole run and needs an ",
      "explicit, documented reason before it can be applied."
    )
  }
  clamp_vals <- suppressWarnings(as.numeric(usable[[effect_col]]))
  wrong_direction <- if (effect_direction == "decrease_is_better") clamp_vals > 0 else clamp_vals < 0
  clamp_idx <- which(usable$compound == "placebo" & wrong_direction)
  if (length(clamp_idx) > 0) {
    cat(
      "Placebo clamp: ", length(clamp_idx), " placebo row(s) with a wrong-direction ",
      "(", effect_direction, ") ", effect_col, " forced to 0 -- reason:", manifest$placebo_clamp_reason, "\n", sep = ""
    )
    usable[[effect_col]][clamp_idx] <- 0
  } else {
    cat("Placebo clamp enabled, but no placebo rows had a wrong-direction ", effect_col, " -- no-op this run.\n", sep = "")
  }
}

# Route-of-administration and observed/projection pre-filters (Step 2.5 of
# the skill) -- global scoping choices made once per run, applied before any
# study-selection review. Both default to "both" (no filtering) when absent,
# so every manifest written before these fields existed keeps working
# unchanged.
route_filter <- manifest$route_filter %||% "both"
if (!route_filter %in% c("oral", "injectable", "both")) {
  stop("route_filter must be 'oral', 'injectable', or 'both', got: ", route_filter)
}
if (route_filter != "both") {
  before_n <- nrow(usable)
  # Placebo rows are never dropped by route -- a placebo arm's own `aom` tag
  # reflects its paired active comparator's route, not a property of placebo
  # itself. A row with missing `aom` is dropped under a specific route filter
  # (can't confirm it matches what was asked for) -- same "can't rule out
  # pooling if route isn't recorded" logic as check_naming_pooling.R's
  # missing_route flag.
  usable <- usable %>% filter(compound == "placebo" | aom == route_filter)
  cat("Route filter '", route_filter, "': ", before_n - nrow(usable), " row(s) dropped.\n", sep = "")
}

evidence_filter <- manifest$evidence_filter %||% "both"
if (!evidence_filter %in% c("observed", "prediction", "both")) {
  stop("evidence_filter must be 'observed', 'prediction', or 'both', got: ", evidence_filter)
}
if (evidence_filter != "both") {
  before_n <- nrow(usable)
  # supplementary rows are exempt, same pattern as placebo's route exemption
  # above -- "supplementary" isn't a meaningful point on the observed/
  # prediction axis, so forcing an evidence_filter choice on it would just
  # drop deliberately hand-added data for the wrong reason.
  usable <- usable %>% filter(source_sheet == "supplementary" | source_sheet == evidence_filter)
  cat("Evidence filter '", evidence_filter, "': ", before_n - nrow(usable), " row(s) dropped.\n", sep = "")
}

# Compound scope filter -- for a "compound-first" run (user supplies a list
# of wanted compounds/doses up front, per SKILL.md step 0.5, rather than
# reviewing the full unfiltered study list). Row-level, not study-level: a
# study that mixes a wanted compound with an unwanted one (e.g. "believe"
# has semaglutide alongside bimagrumab and a bimagrumab+semaglutide combo
# arm) keeps its wanted-compound rows and drops the rest, rather than either
# keeping the whole study (silently pulling in compounds nobody asked for)
# or dropping the whole study (losing the wanted compound's evidence too).
# Dropping arms from a multi-arm trial doesn't corrupt the remaining arms'
# own estimates as long as a shared comparator (placebo, almost always)
# still connects them -- this is standard NMA subnetwork selection, not a
# statistical shortcut. Placebo rows are always exempt, same pattern as the
# route filter above -- placebo is the network's shared reference arm
# regardless of which compounds are in scope.
if (!is.null(manifest$compound_filter)) {
  compound_filter <- unlist(manifest$compound_filter)
  before_n <- nrow(usable)
  usable <- usable %>% filter(compound == "placebo" | compound %in% compound_filter)
  cat(
    "Compound filter (", length(compound_filter), " compounds): ",
    before_n - nrow(usable), " row(s) dropped.\n", sep = ""
  )
}

# Region scope filter -- for a workbook that carries a region-scoped extra
# sheet (e.g. "China Observed") alongside the standard global Observed/
# Prediction sheets (see load_merge_data.R). Defaults to "global" ONLY --
# unlike route/evidence/compound_filter, which default to "both" -- because
# region-scoped sheets are read into every merge unconditionally regardless
# of whether a given run asked for them; defaulting to "both" here would
# silently pull a newly-added regional dataset into every existing run the
# moment someone adds that sheet to a workbook. An explicit region_filter is
# required to include anything beyond "global". No placebo exemption here
# (unlike route_filter): a regional dataset's own placebo rows are part of
# that region's scope, not a universal reference shared across regions.
region_filter <- unlist(manifest$region_filter %||% "global")
if (!"region" %in% names(usable)) usable$region <- "global"
before_n <- nrow(usable)
usable <- usable %>% filter(region %in% region_filter)
if (before_n - nrow(usable) > 0) {
  cat(
    "Region filter (", paste(region_filter, collapse = ", "), "): ",
    before_n - nrow(usable), " row(s) dropped.\n", sep = ""
  )
}

studies_in_data <- unique(usable$study_name)
studies_in_manifest <- vapply(manifest$studies, function(s) s$study_name, character(1))

missing_from_manifest <- setdiff(studies_in_data, studies_in_manifest)
if (length(missing_from_manifest) > 0) {
  stop(
    "Manifest is missing an explicit include/exclude decision for ",
    length(missing_from_manifest), " study/ies found in the data:\n  ",
    paste(missing_from_manifest, collapse = ", "),
    "\nAdd an entry for each under `studies:` before re-running -- no ",
    "study is included or excluded by default."
  )
}

unknown_in_manifest <- setdiff(studies_in_manifest, studies_in_data)
if (length(unknown_in_manifest) > 0) {
  cat(
    "Note: manifest lists studies not present in this data run (ignored):\n  ",
    paste(unknown_in_manifest, collapse = ", "), "\n"
  )
}

included_studies <- vapply(
  Filter(function(s) isTRUE(s$include), manifest$studies),
  function(s) s$study_name,
  character(1)
)

data_sel <- usable %>% filter(study_name %in% included_studies)

if (nrow(data_sel) == 0) {
  stop("No rows remain after applying the manifest's study selection.")
}

data_sel <- data_sel %>%
  rename(study = study_name, treat = treatment)

# Hard guard: every compound=="placebo" row must have literally treat=="placebo"
# by this point, or it becomes its own separate, disconnected single-study
# network node below (arm_ind is derived from the treatment STRING alone,
# same invariant check_naming_pooling.R's route-collision check already
# relies on) instead of sharing the network's one placebo reference arm.
# Real case, 2026-08-20: a T2D HbA1c workbook recorded placebo arms as
# "oral placebo qd"/"injectable placebo qw"/etc in several studies --
# check_naming_pooling.R's placebo_naming_flags surfaces these upfront so
# Step 3 can propose a treatment_relabels entry, but this is the backstop
# that actually stops the run if that proposal was skipped or missed,
# rather than silently fragmenting the network.
bad_placebo <- data_sel %>% filter(compound == "placebo", treat != "placebo")
if (nrow(bad_placebo) > 0) {
  bad_variants <- bad_placebo %>% distinct(treat) %>% pull(treat)
  stop(
    "compound == 'placebo' row(s) found with a non-canonical treatment string: ",
    paste(bad_variants, collapse = ", "), " -- add a treatment_relabels entry ",
    "for each (see check_naming_pooling.R's placebo_naming_flags) mapping it to ",
    "'placebo', or every one of these becomes its own disconnected single-study ",
    "node instead of sharing the network's placebo reference arm."
  )
}

# Disambiguate study identity when a single study_name internally collides on
# (study, treat) -- e.g. a study whose own observed rows and own prediction
# rows are both kept (per the manifest), and both happen to include the same
# treatment string (typically "placebo") at a different duration. BATMAN
# requires exactly one row per treatment per "study" -- this is the same
# distinction that already exists naturally between e.g. retatrutide_ph2_gzbf
# and retatrutide_gzbf (which just happen to have different study_names);
# here it's the same study_name internally, so split by source_sheet instead.
# Only colliding studies get the [sheet] suffix, so the common case (no
# internal observed+prediction mix) is untouched.
colliding_studies <- data_sel %>%
  count(study, treat) %>%
  filter(n > 1) %>%
  pull(study) %>%
  unique()

if (length(colliding_studies) > 0) {
  cat(
    "Disambiguating studies with an internal same-treatment collision by ",
    "data source (observed vs. prediction): ", paste(colliding_studies, collapse = ", "), "\n"
  )
  data_sel <- data_sel %>%
    mutate(study = if_else(study %in% colliding_studies, paste0(study, " [", source_sheet, "]"), study))
}

study_list <- unique(data_sel$study)
treatment_list <- unique(data_sel$treat)
if ("placebo" %in% treatment_list) {
  treatment_list <- c("placebo", setdiff(treatment_list, "placebo"))
} else {
  warning("No 'placebo' arm found in the selected data -- adding as phantom reference.")
  treatment_list <- c("placebo", treatment_list)
}

data_recon <- data_sel %>%
  left_join(data.frame(study = study_list, study_ind = seq_along(study_list)), by = "study") %>%
  left_join(data.frame(treat = treatment_list, arm_ind = seq_along(treatment_list)), by = "treat")

# Real (non-phantom), study-level arm rows -- snapshot taken here, before
# phantom-placebo bridging below can add synthetic rows. Consumed by
# fit_pooled_placebo_model.R (needs to know which studies *actually*
# reported which arms, not the BATMAN-augmented version that would
# misrepresent a phantom-bridged study as having real placebo evidence).
# Optional output -- existing driver scripts that don't
# pass --arm-rows-out keep working unchanged.
if (!is.null(args$arm_rows_out)) {
  arm_rows <- data_recon %>%
    transmute(study_ind, study_name = study, arm_ind, treatment = treat, compound,
              y = as.numeric(.data[[effect_col]]), se = as.numeric(.data[[se_col]]))
  saveRDS(arm_rows, args$arm_rows_out)
}

# ---------------------------------------------------------------------------
# BATMAN augmentation: phantom placebo arm for studies with none
# ---------------------------------------------------------------------------
# model_type controls whether this fires at all. Confirmed 2026-08-17
# (BNMA_forest_plot-main.zip, the real production BNMA Shiny app): the real
# tool has NO automatic phantom-placebo bridging anywhere -- its own
# intro page states "If a placebo already exists for the treatment arm from
# previous studies in the Core dataset, no new placebo data is needed.
# Otherwise, placebo data is required," i.e. a curator supplies the value
# upstream; a study with none simply doesn't connect to the network (its
# phi[i] baseline is estimated, but it contributes no delta/relative-effect
# information). That's real, documented behavior (unlike the earlier
# connectivity-aware attempt, which had no documentation anywhere and was
# reverted for exactly that reason) -- so for model_type rand_effect/
# fixed_effect (the real production models), we match it: no injection,
# just a clear log line instead of a silent no-op.
#
# model_type absent or "simultaneous" (the legacy hierarchical model) keeps
# today's unconditional bridging exactly as-is -- every existing manifest
# was written assuming this, so the field defaults to the OLD behavior when
# absent, not the new recommended default (same asymmetric-default pattern
# as region_filter's own note above).
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
    phantom_rows <- data_recon %>%
      filter(study_ind %in% studies_without_placebo) %>%
      select(study, study_ind) %>%
      distinct() %>%
      mutate(treat = "placebo", arm_ind = 1L, compound = NA_character_)
    # See na_like()/one_like() above -- must match effect_col/se_col's
    # actual runtime type in data_recon, which depends on whether this run's
    # columns happen to be in QA_NUMERIC_COLS (weight-loss defaults: numeric
    # after merge) or not (a custom endpoint: still character at this point).
    phantom_rows[[effect_col]] <- na_like(data_recon[[effect_col]])
    phantom_rows[[se_col]] <- one_like(data_recon[[se_col]])
    data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
  } else {
    # rand_effect/fixed_effect default to NOT bridging (see note above), but
    # this is a real, recurring per-run judgment call -- confirmed 2026-08-20,
    # comes up "in some analyses we run" (e.g. an isolated head-to-head trial
    # that would otherwise sit outside the network entirely). So it's opt-in
    # per study here, same hard-error-if-no-reason pattern as placebo_clamp/
    # se_fallback below -- a phantom placebo (se=1, y=NA) is a fabricated,
    # zero-information data point, not something to default silently either
    # way. The skill conversation surfaces every no-placebo study in Step 3
    # (whether or not this field ends up used) so "leave disconnected" is
    # always a stated decision, not a silent fallthrough.
    bridge_requested <- manifest$phantom_placebo_studies %||% list()
    bridge_requested <- unique(tolower(squish_ws(unlist(bridge_requested))))

    if (length(bridge_requested) > 0) {
      reason <- manifest$phantom_placebo_reason
      if (is.null(reason) || !nzchar(trimws(reason))) {
        stop(
          "phantom_placebo_studies is set but phantom_placebo_reason is missing/blank -- ",
          "bridging a study with no real placebo arm fabricates a zero-information data ",
          "point (se=1, y=NA) for it, so (like placebo_clamp/se_fallback) it needs a ",
          "documented reason, not just a logged default."
        )
      }
      unknown <- setdiff(bridge_requested, tolower(squish_ws(no_placebo_studies)))
      if (length(unknown) > 0) {
        stop(
          "phantom_placebo_studies lists study/ies not among this run's no-placebo studies ",
          "(check spelling against study_name): ", paste(unknown, collapse = ", ")
        )
      }
    }

    to_bridge <- lookup %>%
      filter(study_ind %in% studies_without_placebo, tolower(squish_ws(study)) %in% bridge_requested)
    to_leave <- lookup %>%
      filter(study_ind %in% studies_without_placebo, !tolower(squish_ws(study)) %in% bridge_requested)

    if (nrow(to_bridge) > 0) {
      cat(
        "Studies without a placebo arm, phantom-bridged per phantom_placebo_studies ",
        "-- reason:", reason, ":\n  ", paste(to_bridge$study, collapse = ", "), "\n", sep = ""
      )
      phantom_rows <- data_recon %>%
        filter(study_ind %in% to_bridge$study_ind) %>%
        select(study, study_ind) %>%
        distinct() %>%
        mutate(treat = "placebo", arm_ind = 1L, compound = NA_character_)
      # See na_like()/one_like() near the top of this script -- must match
      # effect_col/se_col's actual runtime type, same reasoning as the
      # simultaneous branch above.
      phantom_rows[[effect_col]] <- na_like(data_recon[[effect_col]])
      phantom_rows[[se_col]] <- one_like(data_recon[[se_col]])
      data_recon <- bind_rows(data_recon, phantom_rows) %>% arrange(study_ind, arm_ind)
    }
    if (nrow(to_leave) > 0) {
      cat(
        "Studies without a placebo arm (model_type='", model_type, "' -- NOT bridged, matches the real ",
        "production tool's own behavior; these studies contribute a baseline estimate only, no ",
        "relative-effect information):\n  ", paste(to_leave$study, collapse = ", "), "\n", sep = ""
      )
    }
  }
}

# ---------------------------------------------------------------------------
# Build BATMAN/JAGS input matrices
# ---------------------------------------------------------------------------
na_df <- data_recon %>% group_by(study_ind) %>% summarise(na = n_distinct(arm_ind), .groups = "drop") %>% arrange(study_ind)

# Drop studies left with only one arm after all filtering/exclusion above --
# matches the real production app's own defensive behavior (cmh.bnma's
# prepare_model_data(): "Drop studies with only one arm (JAGS requires at
# least 2 arms per study)"), confirmed 2026-08-20. Not a crash risk here --
# JAGS's own `for(j in 2:na[i])` is a bounded loop (zero iterations when
# na[i]<2), not R's `:` operator semantics, so a single-arm study just adds
# a dead-weight phi[i] baseline node with no relative-effect contribution
# (confirmed: our own real T2D HbA1c run had 4 such studies and converged
# fine) -- but there's no reason to carry that dead weight or let it
# contribute noise to the convergence scoring, so drop it explicitly and
# renumber study_ind contiguously, same as the real app does.
single_arm_studies <- na_df %>% filter(na < 2) %>% pull(study_ind)
if (length(single_arm_studies) > 0) {
  dropped_names <- data_recon %>% filter(study_ind %in% single_arm_studies) %>% pull(study) %>% unique()
  cat("Dropping", length(single_arm_studies), "single-arm study/ies (no relative-effect information possible):\n  ",
      paste(dropped_names, collapse = ", "), "\n")
  data_recon <- data_recon %>% filter(!study_ind %in% single_arm_studies)
  study_remap <- data.frame(
    study_ind_old = sort(unique(data_recon$study_ind)),
    study_ind = seq_along(unique(data_recon$study_ind))
  )
  data_recon <- data_recon %>%
    rename(study_ind_old = study_ind) %>%
    left_join(study_remap, by = "study_ind_old") %>%
    select(-study_ind_old)
  na_df <- data_recon %>% group_by(study_ind) %>% summarise(na = n_distinct(arm_ind), .groups = "drop") %>% arrange(study_ind)
}

na_vec <- na_df$na
ns <- max(data_recon$study_ind)
M <- max(data_recon$arm_ind)
max_na <- max(na_vec)

trt <- matrix(NA_integer_, ns, max_na)
y   <- matrix(NA_real_, ns, max_na)
se  <- matrix(NA_real_, ns, max_na)

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
saveRDS(batman_data, args$batman_out)

# Surface whether this specific network can actually support a
# random-effects heterogeneity estimate, or whether every treatment node is
# single-study (fixed-effects territory -- see lib_common.R's
# compute_heterogeneity_estimability() for the full rationale and its
# pf_nma.R precedent). Informational only -- never overrides the manifest's
# own model_type, but must be surfaced to the statistician before fitting
# (Step 5 in SKILL.md) rather than left for them to discover after the fact.
print_heterogeneity_estimability(compute_heterogeneity_estimability(data_recon))

arm_info <- data_recon %>%
  mutate(node = paste0("d[", arm_ind, "]")) %>%
  select(node, arm_ind, treatment = treat, compound) %>%
  # A placebo row's compound is always "placebo" by construction, regardless
  # of what the raw data says -- found via testing against real PRD data,
  # where a placebo arm occasionally carried the study's active-drug compound
  # (a data-entry error; see check_naming_pooling.R's placebo_mistag flag,
  # which surfaces this for a curator to fix at the source). Forcing it here
  # means the forest plot's placebo arm is never mislabeled by that error.
  mutate(compound = if_else(treatment == "placebo", "placebo", compound)) %>%
  distinct() %>%
  # Phantom BATMAN placebo rows have compound = NA and can duplicate a real
  # row's arm_ind (same node/treatment, no compound) -- prefer the row that
  # actually carries a compound so downstream lookups never depend on which
  # of the two ties happened to sort first.
  arrange(arm_ind, is.na(compound)) %>%
  distinct(arm_ind, .keep_all = TRUE)

# Per-arm evidence type, for the forest plot's observed/projection/
# supplementary marker. Aggregated from source_sheet (the clean tag, not the
# free-text data_type column) across every surviving row that maps to this
# arm_ind -- an arm can legitimately be fed by more than one source (e.g. the
# shared placebo arm fed by both observed and prediction studies, or a
# supplementary row sharing an arm with a real one). Stored as the sorted,
# comma-joined set of distinct sources rather than a lossy "mixed" catch-all
# -- single-source arms keep their existing plain string ("observed",
# "prediction", "supplementary") unchanged; a genuinely mixed arm stores e.g.
# "observed,prediction" or "observed,supplementary" so make_forest_plot.R can
# render the exact combination instead of guessing which two sources mixed.
# BATMAN's own synthetic phantom-placebo rows have no source_sheet (they're
# not from any real source) and are excluded here so they can't make a real
# placebo arm look unevidenced.
arm_evidence <- data_recon %>%
  filter(!is.na(source_sheet)) %>%
  group_by(arm_ind) %>%
  summarise(evidence_type = paste(sort(unique(source_sheet)), collapse = ","), .groups = "drop")
arm_info <- arm_info %>% left_join(arm_evidence, by = "arm_ind")
saveRDS(arm_info, args$arm_info_out)

study_info <- data_recon %>% select(study_ind, study_name = study) %>% distinct() %>% arrange(study_ind)
# has_placebo: whether this study has a real placebo arm (arm_ind == 1) --
# not whether one was phantom-injected (model_type: simultaneous). Needed so
# make_forest_plot.R's --effect absolute can exclude studies with no real
# placebo data from the pooled baseline: a head-to-head trial's phi[i] is
# purely a hierarchical-prior artifact with nothing anchoring it to a real
# value, and averaging it into "the pooled placebo baseline" silently
# corrupts that number -- found via testing (2026-08-19), not assumed: two
# no-placebo studies (surmount-5, redefine4) had phi[i] of -15 and -25 when
# every real-placebo study's phi[i] was -3 to +1, dragging the pooled mean
# from a plausible ~-2% to an implausible -5.9%.
has_placebo_study <- data_recon %>%
  filter(arm_ind == 1, !is.na(.data[[effect_col]])) %>%
  pull(study_ind) %>% unique()
study_info <- study_info %>% mutate(has_placebo = study_ind %in% has_placebo_study)
saveRDS(study_info, args$study_info_out)

cat(
  "BATMAN data built:", ns, "studies,", M, "treatment arms.\n",
  "Written to:", args$batman_out, "/", args$arm_info_out, "/", args$study_info_out, "\n"
)
```

### B5. `fit_bnma_model.R`

Step 5 — fits (or loads a cached fit of) the main JAGS BNMA model, with the canonical MCMC settings and chain-init procedure.

```r
#!/usr/bin/env Rscript
# Step 5 of the /bnma skill: fit (or load a cached fit of) the BATMAN/JAGS
# random-effects NMA model.
#
# MCMC settings: canonical source is the real production package's own
# documentation (EliLillyCo/CMH.BNMA, provided by the user 2026-08-20,
# installed via `pak::pak("EliLillyCo/CMH.BNMA")`) -- this SUPERSEDES the
# NMA Output Review Process Guide-derived settings this file used before
# (burn-in 20,000/iter 50,000/thin 5), since it's the actual package's own
# stated behavior rather than a documentation guide being interpreted
# against unrelated internal scripts. CMH.BNMA states, verbatim:
#   "Models are fitted with JAGS (via rjags) using 3 MCMC chains: Adapt:
#   10,000 iterations. Burn-in: 10,000 iterations. Sampling: 20,000
#   iterations, thinned by 10."
# -> n.adapt 10,000 (unchanged), n.burnin 10,000 (was 20,000), n.iter 20,000
# (was 50,000), thin 10 (was 5), n.chains 3 (unchanged). Anyone needing the
# Guide's heavier 100k/200k sampling can still pass --n_iter directly.
#
# CMH.BNMA also confirms, matching this skill's own existing design (no
# code change needed, noted here only as independent cross-validation):
#   - "Two model specifications are available: Fixed effects (common
#     treatment effects across studies) / Random effects (study-level
#     heterogeneity via a half-uniform prior on sigma)" -- matches
#     model_fixed.txt/model_random.txt exactly (sigma~dunif(0,8) IS a
#     half-uniform prior on the between-study SD).
#   - "Posterior samples are cached to disk so repeat visits... load
#     instantly" -- matches this script's own cache-by-path behavior below.
#
# Chain initialization (not covered by the CMH.BNMA excerpt above, so the
# Guide-derived procedure below still stands unchanged):
#   - Chain 1 gets deterministic zero initial values for the baseline (phi,
#     and m for model_simultaneous.txt/model_simultaneous_fixed.txt) and
#     treatment-effect (d) nodes;
#     chains 2+ get random draws from those same nodes' own vague priors
#     (Normal(0, SD=100)) -- verbatim per the Guide's stated procedure.
#     Heterogeneity nodes (sigma/sigma_m) are deliberately left to JAGS's
#     own default init -- the Guide's own scope for explicit inits is "the
#     study-specific baseline term (alpha) and treatment terms (beta)" only,
#     and forcing chain 1's sigma to exactly 0 would divide-by-zero in this
#     model's tau2 <- 1/sigma2 node.
#
# model_random.txt/model_fixed.txt (the recommended defaults -- see SKILL.md)
# are copied verbatim from the real production BNMA Shiny app
# (BNMA_forest_plot-main.zip, confirmed 2026-08-17): non-hierarchical
# phi[i]~dnorm(0,0.0001) baseline per Dias 2013's "separate model" (matching
# the NMA Output Review Process Guide's stated standard), sigma~dunif(0,8) --
# also matching the Guide's explicit "between trial SD... uniform 0 to 8"
# spec for random-effects models. model_simultaneous.txt (hierarchical/
# exchangeable phi) stays as a legacy option for effect_type: absolute; its
# own sigma~dunif(0,8) (baseline heterogeneity, matches the Guide's "separate
# baseline risk models" spec) was already correct, but its treatment-effect
# heterogeneity prior was dunif(0,100) -- 12.5x the Guide's stated 0-8 for
# that exact parameter, with no other internal source supporting 100 --
# corrected 2026-08-19.
#
# model_simultaneous_fixed.txt (added 2026-08-19): same hierarchical/pooled
# phi as model_simultaneous.txt (needed for effect_type: absolute's baseline),
# but delta[i,j] is DETERMINISTIC (no sigma), matching model_fixed.txt's own
# delta block. Found by testing: fitting a star network (every treatment node
# single-study -- see compute_heterogeneity_estimability()) through
# model_simultaneous.txt's random delta[i,j]~dnorm(..., tau2) inflates every
# credible interval hugely, because with zero replication per node, sigma is
# almost entirely prior-driven (dunif(0,8) posterior mean landed ~3.9-4) and
# that ~4-point SD gets added on top of each arm's own (much smaller) trial
# SE. This is exactly the same "fixed-effect is the objectively correct
# choice for a star network" argument SKILL.md already documents for
# rand_effect->fixed_effect (model_random.txt/model_fixed.txt) -- it applies
# equally to model_simultaneous.txt's own delta structure, this file is the
# fixed-effect counterpart for the absolute-effect path.
#
# Must be run via scripts/run_with_jags.sh, not Rscript directly -- rjags
# needs the `jags` environment module loaded first in this environment.
#
# Usage:
#   scripts/run_with_jags.sh scripts/fit_bnma_model.R --batman <batman.rds> \
#     --model <model_random.txt|model_fixed.txt|model_simultaneous.txt|model_simultaneous_fixed.txt> --cache <samples.rds> [--force]

suppressPackageStartupMessages(library(rjags))

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  batman   = list(required = TRUE),
  model    = list(required = TRUE),
  cache    = list(required = TRUE),
  force    = list(flag = TRUE, default = FALSE),
  n_adapt  = list(default = "10000"),
  n_burnin = list(default = "10000"),
  n_iter   = list(default = "20000"),
  thin     = list(default = "10"),
  seed     = list(default = "2026")
))

batman_data <- readRDS(args$batman)

if (file.exists(args$cache) && !args$force) {
  cat("Loading cached MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))
  base_seed <- as.integer(args$seed) * 1000

  # model_simultaneous.txt / model_simultaneous_fixed.txt additionally have a
  # pooled baseline mean `m` -- give it the same deliberate zero/random-from-
  # prior init treatment as phi.
  has_pooled_baseline <- basename(args$model) %in% c("model_simultaneous.txt", "model_simultaneous_fixed.txt")
  ns <- batman_data$ns
  M  <- batman_data$M

  #' Chain 1 -> exactly 0 ("no relationship between treatment and outcome",
  #' per the Guide). Chains 2+ -> random draws from the same Normal(0, SD=100)
  #' vague prior every phi[]/d[]/m node in these models actually uses.
  draw_from_vague_prior <- function(n, chain_num) {
    if (chain_num == 1) rep(0, n) else rnorm(n, mean = 0, sd = 100)
  }

  inits.list <- lapply(1:3, function(chain_num) {
    # d[1] is a deterministic constant (`d[1] <- 0`) in every model file --
    # NA in the init vector tells JAGS "no initial value for this element,"
    # which is required since you cannot supply one for a logical node.
    d_init <- c(NA, draw_from_vague_prior(M - 1, chain_num))
    init <- list(
      .RNG.seed = base_seed + chain_num, .RNG.name = "base::Wichmann-Hill",
      phi = draw_from_vague_prior(ns, chain_num),
      d   = d_init
    )
    if (has_pooled_baseline) init$m <- draw_from_vague_prior(1, chain_num)
    init
  })

  cat("Compiling JAGS model from", args$model, "\n")
  jags_model <- jags.model(
    args$model, batman_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = inits.list
  )

  cat("Burn-in (", args$n_burnin, "iterations)...\n")
  update(jags_model, as.integer(args$n_burnin))

  # model_simultaneous.txt is the only model file with a pooled baseline (m,
  # sigma_m, mu_new) -- model_random.txt/model_fixed.txt (the real
  # production models) use a separate phi[i] per study with no pooling, so
  # those nodes don't exist there and monitoring them would error at
  # compile/sample time. Keyed off the model file itself (not a manifest
  # field) so every existing caller that already passes an explicit --model
  # path keeps working with zero changes.
  # `sigma` (the between-study SD of the relative treatment effect, feeding
  # delta[i,j]'s variance -- standard NMA "tau", per the user 2026-08-19) is
  # monitored alongside sigma_m (baseline heterogeneity) so make_forest_plot.R
  # can report it on absolute-effect plots. model_simultaneous_fixed.txt has
  # no `sigma` node at all (delta[i,j] is deterministic there -- see its own
  # header comment) so it's excluded from that file's monitored set.
  variable_names <- if (basename(args$model) == "model_simultaneous.txt") {
    c("d", "phi", "delta", "m", "sigma", "sigma_m", "mu_new")
  } else if (basename(args$model) == "model_simultaneous_fixed.txt") {
    c("d", "phi", "delta", "m", "sigma_m", "mu_new")
  } else {
    c("d", "phi", "delta")
  }

  cat("Sampling (", args$n_iter, "iterations, thin =", args$thin, ")...\n")
  samples <- coda.samples(
    jags_model, as.integer(args$n_iter),
    variable.names = variable_names,
    thin = as.integer(args$thin)
  )
  saveRDS(samples, args$cache)
  cat("Samples saved to", args$cache, "\n")
}

cat("Posterior summary (d[] treatment-effect nodes):\n")
s <- summary(samples)
d_rows <- grepl("^d\\[", rownames(s[[1]]))
print(round(cbind(s[[1]][d_rows, "Mean", drop = FALSE], s[[2]][d_rows, c("2.5%", "97.5%")]), 2))

```

### B6. `fit_pooled_placebo_model.R`

Step 5 — the standalone pooled-placebo model that supplies effect_type: absolute's baseline for any model_type.

```r
#!/usr/bin/env Rscript
# Standalone pooled-placebo model, for the --effect absolute baseline in
# make_forest_plot.R. Adopted 2026-08-20 from the real production package's
# own pooled-placebo feature (EliLillyCo/CMH.BNMA, R/pooled_placebo_model_utils.R
# `jags_placebo_module()`/`define_placebo_model()`) -- a SEPARATE, standalone
# hierarchical random-effects meta-analysis fit only on placebo arms
# (mu[i]~dnorm(m, sigma_m^2)), not derived from the main BNMA model's own
# phi[i] nodes at all.
#
# This replaces the 2026-08-19 fix that averaged phi[i] across only the
# real-placebo studies from model_simultaneous.txt's own fit -- that fix was
# already correct in spirit (excluding no-placebo studies' contaminated
# phi[i]), but this is architecturally cleaner: a genuinely independent fit
# that only ever sees placebo data, works with ANY model_type (rand_effect/
# fixed_effect included -- those have no pooled baseline of their own at
# all, so this is what actually enables --effect absolute for them, not
# just model_simultaneous.txt/model_simultaneous_fixed.txt).
#
# MCMC settings match the production package's own (lighter than the main
# model's canonical 10k/10k/20k/thin-10, since this model has far fewer
# parameters): n.adapt 1,000, burn-in 5,000, sampling 10,000, thin 10.
#
# Usage:
#   scripts/run_with_jags.sh scripts/fit_pooled_placebo_model.R \
#     --arm-rows <arm_rows.rds> --cache <placebo_samples.rds> \
#     [--placebo-data-out <placebo_data.rds>] [--force]
#
# No --effect-col/--se-col flag -- arm_rows.rds (Step 5's --arm-rows-out)
# already normalizes to plain y/se columns regardless of this run's own
# effect_col/se_col manifest fields (build_batman_data.R's transmute() does
# that rename), so this script never needs to know the original QA/PRD
# column names at all. Confirmed 2026-08-21: an earlier version of this
# comment claimed those flags existed; parse_args() below never defined
# them, so passing either errored with "Unknown argument."
#
# --arm-rows is Step 5's --arm-rows-out output -- the real (non-phantom),
# manifest-filtered study-level arm rows. Using this (not the raw merged
# data) means the placebo arms fed here already reflect every naming/pooling
# resolution, study include/exclude, and relabel from this run's manifest,
# same set of studies the main model itself was fit on.
#
# --placebo-data-out (optional) persists the per-study placebo rows actually
# used for this fit (study_name/study_idx/y/se) -- make_placebo_forest_plot.R
# needs this to label each posterior mu[i] with its real study name, since
# the JAGS samples themselves only carry the numeric study_idx. Cross-
# validated 2026-08-21 against a colleague's independent implementation
# (the `godwill-bnma` branch, which re-derives this same placebo subset from
# scratch via its own build_placebo_data.R) -- adopted the persist-and-reuse
# approach here instead, since arm_rows.rds already reflects this run's full
# manifest filtering and re-deriving that logic in a second script is a
# needless duplication risk if build_batman_data.R's own filtering ever
# changes.

suppressPackageStartupMessages({
  library(rjags)
  library(dplyr)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  arm_rows        = list(required = TRUE),
  cache           = list(required = TRUE),
  placebo_data_out = list(default = NULL),
  force           = list(flag = TRUE, default = FALSE),
  n_adapt         = list(default = "1000"),
  n_burnin        = list(default = "5000"),
  n_iter          = list(default = "10000"),
  thin            = list(default = "10"),
  seed            = list(default = "2026")
))

arm_rows <- readRDS(args$arm_rows)

placebo_rows <- arm_rows %>% filter(compound == "placebo", !is.na(y), !is.na(se), se > 0, is.finite(se))
if (nrow(placebo_rows) == 0) {
  stop("No usable placebo rows (compound=='placebo', numeric y/se) found in ", args$arm_rows)
}

# Remap to a contiguous 1..ns_bl study index for JAGS -- study_ind from
# arm_rows spans every study in the run, not just placebo-bearing ones.
study_map <- data.frame(
  study_ind = sort(unique(placebo_rows$study_ind)),
  study_idx = seq_along(unique(placebo_rows$study_ind))
)
placebo_rows <- placebo_rows %>% left_join(study_map, by = "study_ind")

# A hierarchical random-effects meta-analysis needs at least 2 groups to say
# anything about between-study variance at all -- the exact same
# identifiability problem compute_heterogeneity_estimability() already
# checks for the main model's own delta[i,j] heterogeneity, just here for
# sigma_m instead of sigma. Confirmed by testing (colleague's godwill-bnma
# branch, 2026-08-21): with 1 study, sigma_m's posterior is pure prior
# (dunif(0,10)), not a data-driven estimate -- stop rather than silently
# fitting a meaningless model.
if (nrow(study_map) < 2) {
  stop(
    "Not enough studies with a usable placebo arm for a pooled-placebo model ",
    "(need >= 2; found ", nrow(study_map), "). With only one study, sigma_m ",
    "has nothing to be estimated from -- check the manifest's study selection ",
    "and route/evidence/compound/region filters."
  )
}

if (!is.null(args$placebo_data_out)) {
  saveRDS(placebo_rows, args$placebo_data_out)
}

cat("Pooled placebo model: ", nrow(placebo_rows), " placebo row(s) across ", nrow(study_map), " study/ies.\n", sep = "")

jags_data <- list(
  y_pct = placebo_rows$y,
  se_pct = placebo_rows$se,
  n_obs = nrow(placebo_rows),
  ns_bl = nrow(study_map),
  study_idx = placebo_rows$study_idx
)

if (file.exists(args$cache) && !args$force) {
  cat("Loading cached placebo-model MCMC samples from", args$cache, "\n")
  samples <- readRDS(args$cache)
} else {
  set.seed(as.integer(args$seed))
  base_seed <- as.integer(args$seed) * 1000
  y_mean <- mean(jags_data$y_pct, na.rm = TRUE)

  # Deterministic per-chain RNG (.RNG.seed/.RNG.name), matching
  # fit_bnma_model.R's own established convention for the main model's fit
  # -- a plain single set.seed() call (this script's own original approach)
  # doesn't guarantee reproducibility across JAGS's separately-spawned chain
  # RNG streams the way an explicit per-chain seed does.
  inits.list <- lapply(1:3, function(chain_num) {
    list(
      .RNG.seed = base_seed + chain_num, .RNG.name = "base::Wichmann-Hill",
      m = rnorm(1, y_mean, 0.5),
      sigma_m = runif(1, 0.3, 1),
      mu = rnorm(jags_data$ns_bl, y_mean, 0.5)
    )
  })

  model_path <- file.path(dirname(script_dir), "model_placebo_random.txt")
  cat("Compiling JAGS model from", model_path, "\n")
  jags_model <- jags.model(
    model_path, jags_data,
    n.adapt = as.integer(args$n_adapt), n.chains = 3, inits = inits.list
  )

  cat("Burn-in (", args$n_burnin, "iterations)...\n")
  update(jags_model, as.integer(args$n_burnin))

  cat("Sampling (", args$n_iter, "iterations, thin =", args$thin, ")...\n")
  samples <- coda.samples(
    jags_model,
    variable.names = c("m", "sigma_m", "mu", "mu_new"),
    n.iter = as.integer(args$n_iter),
    thin = as.integer(args$thin)
  )

  saveRDS(samples, args$cache)
  cat("Saved:", args$cache, "\n")
}

s <- summary(samples)
m_row <- s$statistics["m", "Mean"]
m_ci <- s$quantiles["m", c("2.5%", "97.5%")]
sigma_row <- s$statistics["sigma_m", "Mean"]
cat("Pooled placebo baseline: m =", round(m_row, 3),
    " (95% CrI", round(m_ci[1], 3), ",", round(m_ci[2], 3), ")",
    " sigma_m =", round(sigma_row, 3), "\n")

```

### B7. `make_forest_plot.R`

Step 6 — builds the forest plot: per-treatment contributing-studies footnote, observed/projection/supplementary superscripts, the fixed compound color palette + fallback generator, and the absolute-effect μ/τ subtitle.

```r
#!/usr/bin/env Rscript
# Step 6 of the /bnma skill: forest plot from a fitted model's posterior,
# annotated with contributing studies and footnoted with the source
# data/program paths -- per GUIDE_README.md Flow 2 steps 5, 7, 8 (forest
# plots should show which studies fed the estimate; footnote the exact
# data/program paths so results trace back to a specific run).
#
# Usage:
#   Rscript make_forest_plot.R --samples <samples.rds> --arm-info <arm_info.rds> \
#     --study-info <study_info.rds> --manifest <manifest.yaml> \
#     --effect relative|absolute --out <plot.png> [--title "..."] \
#     [--arm-rows <arm_rows.rds>]
#
# --arm-rows (build_batman_data.R's --arm-rows-out, Step 5) enables a
# per-treatment "which studies fed this estimate" footnote breakdown instead
# of one plot-wide list -- see contributing_studies below. Omit it (older
# driver scripts that never passed --arm-rows-out) and the footnote falls
# back to the flat plot-wide list, unchanged from before.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(yaml)
  library(coda) # needed so as.matrix() dispatches as.matrix.mcmc.list correctly
  library(ggtext) # renders the observed/projection superscript markers as real superscripts
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples          = list(required = TRUE),
  arm_info         = list(required = TRUE),
  study_info       = list(required = TRUE),
  manifest         = list(required = TRUE),
  effect           = list(default = "relative"),
  placebo_samples  = list(default = NULL),
  arm_rows         = list(default = NULL),
  out              = list(required = TRUE),
  title            = list(default = NULL),
  xlab             = list(default = NULL)
))

if (!args$effect %in% c("relative", "absolute")) {
  stop("--effect must be 'relative' or 'absolute', got: ", args$effect)
}

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)
study_info <- readRDS(args$study_info)
manifest <- yaml::read_yaml(args$manifest)
arm_rows <- if (!is.null(args$arm_rows) && file.exists(args$arm_rows)) readRDS(args$arm_rows) else NULL

samples_mat <- as.matrix(samples)

# The absolute-effect baseline comes from a SEPARATE, standalone pooled-
# placebo model (scripts/fit_pooled_placebo_model.R), not from this model's
# own fit -- adopted 2026-08-20 from the real production package's own
# pooled-placebo feature (EliLillyCo/CMH.BNMA). This decouples --effect
# absolute from model_type entirely: model_random.txt/model_fixed.txt (the
# real production relative-effect models) have no pooled baseline of their
# own at all, so this is what actually makes absolute effects available for
# them, not just the legacy model_simultaneous.txt/model_simultaneous_fixed.txt
# (which still work fine here too -- this doesn't care what the main model
# was).
#
# Superseded: averaging phi[i] across only real-placebo studies from
# model_simultaneous.txt's OWN fit (2026-08-19) -- correct in spirit
# (excluding no-placebo studies' contaminated phi[i]) but architecturally
# coupled to one specific legacy model file. A genuinely independent fit
# that only ever sees placebo data is cleaner and works everywhere.
if (args$effect == "absolute") {
  if (is.null(args$placebo_samples)) {
    stop(
      "--effect absolute needs --placebo-samples <path> -- the cached fit from ",
      "scripts/fit_pooled_placebo_model.R (run it first against this run's ",
      "arm_rows.rds if you haven't already)."
    )
  }
  if (!file.exists(args$placebo_samples)) {
    stop("--placebo-samples file not found: ", args$placebo_samples)
  }
  placebo_samples_mat <- as.matrix(readRDS(args$placebo_samples))
  if (!"m" %in% colnames(placebo_samples_mat)) {
    stop("--placebo-samples file has no 'm' node -- was it really fit from model_placebo_random.txt?")
  }
  # Resample to this fit's own draw count so `m_samples + d_samples` below is
  # a valid elementwise Monte Carlo combination of two independent
  # posteriors, regardless of the two models' differing chain lengths/thin
  # (the placebo model deliberately uses a lighter MCMC budget -- see its
  # own script header).
  m_samples <- sample(placebo_samples_mat[, "m"], nrow(samples_mat), replace = TRUE)
  sigma_m_samples <- sample(placebo_samples_mat[, "sigma_m"], nrow(samples_mat), replace = TRUE)
  cat("Pooled placebo baseline loaded from", args$placebo_samples,
      "-- mean m =", round(mean(m_samples), 3), "\n")
}

plot_treatments <- manifest$plot_treatments
if (is.null(plot_treatments) || length(plot_treatments) == 0) {
  # Default: every non-placebo treatment that made it into the model, in the
  # order they were first seen -- an explicit `plot_treatments` list in the
  # manifest is how a curated subset/order is requested instead.
  plot_treatments <- arm_info %>% filter(treatment != "placebo") %>% pull(treatment) %>% unique()
}

arm_lookup <- arm_info %>%
  filter(treatment %in% c(plot_treatments, "placebo")) %>%
  group_by(arm_ind) %>% slice(1) %>% ungroup()

rows <- lapply(seq_len(nrow(arm_lookup)), function(i) {
  arm_k <- arm_lookup$arm_ind[i]
  trt_name <- arm_lookup$treatment[i]
  cmpd <- arm_lookup$compound[i]

  if (args$effect == "relative") {
    post <- if (arm_k == 1) rep(0, nrow(samples_mat)) else samples_mat[, paste0("d[", arm_k, "]")]
  } else {
    post <- if (arm_k == 1) m_samples else m_samples + samples_mat[, paste0("d[", arm_k, "]")]
  }

  data.frame(
    treatment = trt_name,
    compound = if (trt_name == "placebo") "placebo" else cmpd,
    evidence_type = arm_lookup$evidence_type[i],
    mean = mean(post),
    val2.5pc = quantile(post, 0.025),
    val97.5pc = quantile(post, 0.975)
  )
})

data_plot <- bind_rows(rows) %>%
  filter(treatment %in% plot_treatments | (args$effect == "absolute" & treatment == "placebo")) %>%
  arrange(match(treatment, c("placebo", plot_treatments))) %>%
  mutate(Label = paste0(round(mean, 1), " (", round(val2.5pc, 1), ", ", round(val97.5pc, 1), ")"))

# Observed/projection/supplementary marker -- a superscript on the axis
# label itself, so a reviewer QC'ing the PNG doesn't have to cross-reference
# the manifest to know which arms are real trial data, modeled, or hand-added
# (see supplementary_data in SKILL.md). evidence_type is the sorted,
# comma-joined set of distinct sources feeding this arm (build_batman_data.R)
# -- map each token through type_code and rejoin, so any combination (not
# just the observed+prediction pair this used to hardcode) renders correctly,
# e.g. "observed,supplementary" -> "^o,s^".
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

range_span <- max(data_plot$val97.5pc, na.rm = TRUE) - min(data_plot$val2.5pc, na.rm = TRUE)

trt_order <- unique(data_plot$treatment_label)

# Default axis/title text templates assume a "percent change" endpoint
# (weight loss, HbA1c reduction, etc.) -- this is a template, not a
# universal label: an endpoint that isn't naturally a percent change (e.g. a
# raw physical-function score) will render a technically-present but
# semantically-wrong "(%)" via this default. --xlab/--title always override
# it regardless, so use those explicitly for any endpoint this template
# doesn't fit rather than trying to make one template cover every shape.
effect_col <- manifest$effect_col %||% "pchg_wl_ee"
endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
ylab_text <- args$xlab %||% sprintf(
  "Mean (95%% CI) of %s Percent Change in %s (%%)",
  if (args$effect == "relative") "Pbo-adj" else "Absolute",
  endpoint_label
)
title_text <- args$title %||% sprintf(
  "%s Percent %s Change",
  if (args$effect == "relative") "Placebo-Adjusted" else "Absolute",
  endpoint_label
)

# Absolute-effect plots report the two parameters that number is actually
# built from -- the pooled placebo baseline (mu = m, sigma_mu = the standalone
# placebo model's own between-study SD of the placebo response) and the
# between-study SD of the relative treatment effect (tau = sigma, standard
# NMA notation, per the user 2026-08-19) -- so a reviewer sees the method,
# not just the number. The tau half soft-fails (omits that clause, doesn't
# error the whole plot) if `sigma` isn't in the MAIN model's samples -- true
# for a fixed-effect delta model, or an older samples.rds cached before
# sigma was added to fit_bnma_model.R's monitored variables.
subtitle_text <- NULL
if (args$effect == "absolute") {
  mu_mean <- mean(m_samples); mu_ci <- quantile(m_samples, c(0.025, 0.975))
  sigma_mu_mean <- mean(sigma_m_samples)
  mu_part <- sprintf(
    "Absolute = pooled placebo μ (%.1f%%; 95%% CrI: %.1f, %.1f; between-study σ=%.2f, standalone placebo-only model) + d[j]",
    mu_mean, mu_ci[1], mu_ci[2], sigma_mu_mean
  )
  if ("sigma" %in% colnames(samples_mat)) {
    tau_mean <- mean(samples_mat[, "sigma"]); tau_ci <- quantile(samples_mat[, "sigma"], c(0.025, 0.975))
    subtitle_text <- sprintf("%s    τ = %.2f (95%% CrI: %.2f, %.2f)", mu_part, tau_mean, tau_ci[1], tau_ci[2])
  } else {
    # No 'sigma' column can mean either: (a) this fit used a deterministic-
    # delta model (model_fixed.txt/model_simultaneous_fixed.txt), where
    # there's no tau to report, not an omission; or (b) an older samples.rds
    # cached before sigma was added to the main model's monitored variables.
    # Can't tell which from samples_mat alone, so the message covers both
    # rather than asserting the wrong one.
    subtitle_text <- paste0(mu_part, "    (no τ for this fit -- either a fixed-effect delta model, or refit to capture 'sigma')")
  }
}

# Plot width must be known before the footnote is wrapped -- strwrap()'s
# `width` is a character count, and a fixed value (e.g. 120) doesn't
# actually fit the physical plot width once that varies per run (few
# compounds/short labels -> narrow plot -> 120 chars overflows the panel and
# gets clipped, not wrapped -- caught by testing, not assumed). ~11
# characters per inch is a rough estimate for this caption's 9pt font.
n_compounds <- length(unique(data_plot$compound))
max_label_chars <- max(nchar(data_plot$Label))
plot_width <- 10 + 0.15 * max_label_chars + 0.25 * n_compounds
footnote_wrap_width <- max(40, floor(plot_width * 11))

# Subtitle uses an 11pt font (vs. the caption's 9pt) -- wider characters, so
# reuse the same physical-width logic scaled down proportionally (~9 chars/
# inch instead of ~11) rather than a fixed character count, same reasoning
# as the footnote's own wrap width above. Found by testing, 2026-08-20: the
# absolute-effect subtitle's added between-study-sigma clause pushed it past
# the plot width, silently clipped rather than wrapped.
if (!is.null(subtitle_text)) {
  subtitle_wrap_width <- max(40, floor(plot_width * 9))
  subtitle_text <- paste(strwrap(subtitle_text, width = subtitle_wrap_width), collapse = "\n")
}

#' Per-treatment "which studies fed this estimate" breakdown, per the
#' workflow guide (Flow 2 step 5: show which studies fed *each* treatment
#' estimate, not just the pooled result) -- needs arm_rows.rds's real,
#' study-level (study_ind x arm_ind) rows, since arm_info.rds is
#' deliberately collapsed to one row per arm_ind during
#' build_batman_data.R and has no per-study detail left to recover here.
#' Falls back to the old flat, plot-wide list when --arm-rows wasn't passed
#' (older driver scripts that predate --arm-rows-out) -- same footnote as
#' before, not a breaking change.
if (!is.null(arm_rows)) {
  by_treatment <- arm_rows %>%
    filter(treatment %in% c(plot_treatments, "placebo")) %>%
    distinct(treatment, study_name) %>%
    group_by(treatment) %>%
    summarise(studies = paste(sort(study_name), collapse = ", "), .groups = "drop")
  by_treatment <- by_treatment[match(c(plot_treatments, "placebo"), by_treatment$treatment), ]
  by_treatment <- by_treatment[!is.na(by_treatment$treatment), ]
  contributing_lines <- c(
    "Contributing studies by treatment:",
    unlist(lapply(seq_len(nrow(by_treatment)), function(i) {
      strwrap(
        paste0(by_treatment$treatment[i], ": ", by_treatment$studies[i]),
        width = footnote_wrap_width
      )
    }))
  )
} else {
  contributing_studies <- paste(sort(study_info$study_name), collapse = ", ")
  contributing_lines <- strwrap(paste0("Contributing studies: ", contributing_studies), width = footnote_wrap_width)
}
footnote_lines <- c(
  contributing_lines,
  strwrap(
    paste0(
      "Source data: ", manifest$source_data$prd %||% "(not recorded)",
      if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""
    ),
    width = footnote_wrap_width
  ),
  strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = footnote_wrap_width)
)
footnote_lines <- c(footnote_lines, "^o^ = observed, ^p^ = projection, ^s^ = supplementary (hand-added, not yet in QA/PRD)")
# ggtext's markdown parser (needed for the axis superscripts) treats a bare
# "\n" as a soft wrap, not a forced line break -- confirmed by testing: with
# "\n" the whole caption collapsed onto one line and got clipped by the
# panel edge rather than wrapping. "<br>" is the actual forced-break syntax
# it respects.
footnote_text <- paste(footnote_lines, collapse = "<br>")

# Reference palette (2026-08-19, per the user's team-standard T2D forest
# plot): fixed, named colors for the compounds it showed, so our output
# lines up with that convention exactly rather than an auto-assigned hue.
# This is a weight-loss/obesity-landscape compound convention specifically,
# not tied to the endpoint being plotted -- an HbA1c or physical-function run
# on these same compounds still gets these colors; a run on unrelated
# compounds (a different drug class) just falls through to
# generate_fallback_colors() below, same as any other unlisted compound.
# Any compound NOT in this list falls back to a distinct auto-generated
# color rather than erroring or rendering as NA -- extend
# FIXED_COMPOUND_COLORS here as more reference conventions are confirmed
# (vk2735/brenipatide added 2026-08-20, deliberately NOT their raw hue_pal()
# fallback [scales::hue_pal() was this skill's fallback before also being
# replaced 2026-08-20, see below] -- the auto-generated vk2735 hue landed
# visually close to berobenatide's already-fixed red, so it was assigned a
# separated purple instead; brenipatide's auto teal was already
# well-separated and kept as-is).
FIXED_COMPOUND_COLORS <- c(
  semaglutide  = "#7B241C",
  cagrisema    = "#1B4F72",
  maritide     = "#D68910",
  retatrutide  = "#000000",
  berobenatide = "#E74C3C",
  tirzepatide  = "#85C1E9",
  vk2735       = "#6C3483",
  brenipatide  = "#00BFC4",
  placebo      = "#7F8C8D"
)
compounds_in_plot <- unique(data_plot$compound)
unmapped_compounds <- setdiff(compounds_in_plot, names(FIXED_COMPOUND_COLORS))
# Fallback for any compound not in the team-standard fixed list: matches the
# real production package's own generate_color_palette() (2026-08-20,
# EliLillyCo/CMH.BNMA/R/plot_utils.R) -- RColorBrewer "Set3", darkened 0.3,
# extended via colorRampPalette beyond 12 compounds. Confirmed this is what
# feeds mod_model_forest.R's own BNMA results forest plot specifically (NOT
# build_color_map()'s dose-shaded palette, which turned out to feed an
# unrelated raw-data bar chart, mod_group_barchart.R -- checked the call
# sites directly rather than assuming from the function's name/vicinity).
# Replaces this skill's own prior scales::hue_pal() fallback.
generate_fallback_colors <- function(compounds) {
  n <- length(compounds)
  if (n == 0) return(character(0))
  base_colors <- RColorBrewer::brewer.pal(max(min(n, 12), 3), "Set3")
  if (n > 12) {
    base_colors <- grDevices::colorRampPalette(RColorBrewer::brewer.pal(12, "Set3"))(n)
  }
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
  # Label sits directly above its own point (nudged along the categorical
  # axis, pre-flip that's "x") rather than in a fixed side column -- matches
  # the reference plot's layout. Nudging by a fraction of a row (0.32) keeps
  # it inside that row's own band, clear of the neighboring row's point.
  geom_text(
    aes(y = mean, label = Label),
    position = position_nudge(x = 0.32), vjust = 0, size = 4.2, color = "black", show.legend = FALSE
  ) +
  scale_color_manual(values = compound_colors, name = "Compound") +
  scale_y_continuous(expand = expansion(mult = c(0.08, 0.08))) +
  scale_x_discrete(expand = expansion(add = c(0.6, 0.6))) +
  coord_flip() +
  xlab("") +
  ylab(ylab_text) +
  ggtitle(title_text, subtitle = subtitle_text) +
  labs(caption = footnote_text) +
  theme_bw() +
  theme(
    axis.title = element_text(size = 16),
    # Empirically (tested, not assumed): after coord_flip(), axis.text.y is
    # what actually styles the categorical treatment_label axis (rendered on
    # the left) -- axis.text.x styling the same aes was tried first and
    # silently did nothing, so don't "simplify" this back on a hunch.
    # element_markdown() is what renders "^o^"/"^p^" as real superscripts
    # instead of literal caret text.
    axis.text.y = ggtext::element_markdown(size = 14),
    axis.text.x = element_text(size = 14),
    plot.title = element_text(size = 18, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 11, color = "grey35", hjust = 0.5),
    plot.caption = ggtext::element_markdown(size = 9, hjust = 0, face = "italic"),
    legend.text = element_text(size = 13),
    legend.title = element_text(size = 13)
  )


subtitle_lines <- if (is.null(subtitle_text)) 0 else lengths(regmatches(subtitle_text, gregexpr("\n", subtitle_text))) + 1
plot_height <- max(4, 0.6 * length(trt_order)) + 0.22 * length(footnote_lines) + 0.18 * subtitle_lines
# n_compounds/max_label_chars/plot_width already computed above (needed
# earlier to size the footnote's wrap width) -- reused here, not recomputed.
ggsave(args$out, plot = pforest, width = plot_width, height = plot_height, dpi = 150)
cat("Forest plot saved to:", args$out, "\n")
cat("Footnote:\n", footnote_text, "\n")
```

### B8. `make_placebo_forest_plot.R`

Recommended alongside effect_type: absolute — the pooled-placebo model's own QC plot (each study's observed vs. posterior-shrunk placebo effect, the pooled m, and the predictive mu_new).

```r
#!/usr/bin/env Rscript
# QC plot for the standalone pooled-placebo model (fit_pooled_placebo_model.R)
# -- shows each contributing study's observed vs. posterior-shrunk placebo
# effect, the overall pooled estimate (m), and the predictive distribution
# for a hypothetical new study (mu_new). Adapted 2026-08-21 from a
# colleague's independent implementation on the `godwill-bnma` branch
# (make_placebo_forest_plot.R there), which mirrors the production app's own
# placebo_forest_plot() (CMH.BNMA R/plot_utils.R + R/mod_pooled_placebo.R).
#
# This is a real capability gap fit_pooled_placebo_model.R alone doesn't
# fill: make_forest_plot.R only ever *consumes* this model's m/sigma_m as an
# absolute-effect baseline, with no way to visually confirm the pooled model
# itself is sane (is shrinkage reasonable? is any one placebo study wildly
# discordant? does mu_new look plausible?) -- exactly the kind of check the
# "modelled, shrunk placebo level, not any single trial's observed placebo"
# footnote in make_forest_plot.R asks a reviewer to keep in mind, but gives
# them no picture of.
#
# Reads --placebo-data from fit_pooled_placebo_model.R's own
# --placebo-data-out (study_name/study_idx/y/se) rather than re-deriving the
# placebo subset independently -- single source of truth for which rows fed
# the fit, same reasoning as fit_pooled_placebo_model.R's own header comment.
#
# Usage:
#   Rscript make_placebo_forest_plot.R --samples <placebo_samples.rds> \
#     --placebo-data <placebo_data.rds> --manifest <manifest.yaml> \
#     --out <plot.png> [--title "..."] [--xlab "..."]

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(yaml)
  library(coda)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples      = list(required = TRUE),
  placebo_data = list(required = TRUE),
  manifest     = list(required = TRUE),
  out          = list(required = TRUE),
  title        = list(default = NULL),
  xlab         = list(default = NULL)
))

samples <- readRDS(args$samples)
placebo_data <- readRDS(args$placebo_data)
manifest <- yaml::read_yaml(args$manifest)

s <- summary(samples)
m_mean <- s$statistics["m", "Mean"]; m_lo <- s$quantiles["m", "2.5%"]; m_hi <- s$quantiles["m", "97.5%"]
sigma_mean <- s$statistics["sigma_m", "Mean"]; sigma_lo <- s$quantiles["sigma_m", "2.5%"]; sigma_hi <- s$quantiles["sigma_m", "97.5%"]
mu_new_mean <- s$statistics["mu_new", "Mean"]; mu_new_lo <- s$quantiles["mu_new", "2.5%"]; mu_new_hi <- s$quantiles["mu_new", "97.5%"]

mu_rows <- grepl("^mu\\[", rownames(s$statistics))
mu_summary <- data.frame(
  study_idx = as.integer(gsub("mu\\[(\\d+)\\]", "\\1", rownames(s$statistics)[mu_rows])),
  post_mean = s$statistics[mu_rows, "Mean"],
  post_lower = s$quantiles[mu_rows, "2.5%"],
  post_upper = s$quantiles[mu_rows, "97.5%"]
)

plot_data <- placebo_data %>%
  left_join(mu_summary, by = "study_idx") %>%
  mutate(
    obs_lower = y - 1.96 * se,
    obs_upper = y + 1.96 * se,
    Label = sprintf("%.1f (%.1f, %.1f)", post_mean, post_lower, post_upper)
  ) %>%
  arrange(study_name)

# Study rows (observed, hollow point) + posterior-shrunk estimate (filled
# point), so shrinkage is visible, not just stated -- plus a POOLED summary
# row and a NEW STUDY (PREDICTED) row for mu_new, so a reviewer sees both the
# historical pooled effect and what to expect next time without
# cross-referencing the console output.
study_order <- c("New study (predicted)", "Pooled (m)", rev(plot_data$study_name))

rows_obs <- plot_data %>% transmute(
  label = study_name, kind = "Observed", mean = y, lo = obs_lower, hi = obs_upper
)
rows_post <- plot_data %>% transmute(
  label = study_name, kind = "Posterior (shrunk)", mean = post_mean, lo = post_lower, hi = post_upper
)
rows_pooled <- data.frame(
  label = "Pooled (m)", kind = "Pooled", mean = m_mean, lo = m_lo, hi = m_hi
)
rows_new <- data.frame(
  label = "New study (predicted)", kind = "Predicted (mu_new)", mean = mu_new_mean, lo = mu_new_lo, hi = mu_new_hi
)

data_plot <- bind_rows(rows_obs, rows_post, rows_pooled, rows_new) %>%
  mutate(label = factor(label, levels = study_order))

effect_col <- manifest$effect_col %||% "pchg_wl_ee"
endpoint_label <- manifest$effect_label %||% (if (effect_col == "pchg_wl_ee") "Body Weight" else effect_col)
xlab_text <- args$xlab %||% sprintf("Mean (95%% CI) Placebo Percent Change in %s (%%)", endpoint_label)
title_text <- args$title %||% sprintf("Pooled Placebo Effect: %s", endpoint_label)
subtitle_text <- sprintf(
  "Pooled m = %.2f%% (95%% CrI: %.2f, %.2f)   between-study SD (sigma_m) = %.2f (95%% CrI: %.2f, %.2f)",
  m_mean, m_lo, m_hi, sigma_mean, sigma_lo, sigma_hi
)

plot_width <- 9
# Wrap the caption to the plot's own width (~11 chars/inch at this caption's
# 8pt font, same estimate make_forest_plot.R uses) -- confirmed by testing:
# an unwrapped contributing-studies line silently clips at the panel edge
# rather than wrapping, exactly the kind of untraceable footnote this skill
# otherwise insists on getting right.
footnote_wrap_width <- max(40, floor(plot_width * 11))
caption_text <- paste(
  strwrap(paste0("Contributing studies: ", paste(sort(placebo_data$study_name), collapse = ", ")), width = footnote_wrap_width),
  collapse = "\n"
)
caption_text <- paste0(
  caption_text,
  "\n", paste(strwrap(paste0(
    "Source data: ", manifest$source_data$prd %||% "(not recorded)",
    if (!is.null(manifest$source_data$qa)) paste0("  +  ", manifest$source_data$qa) else ""
  ), width = footnote_wrap_width), collapse = "\n"),
  "\n", paste(strwrap(paste0("Source program: ", manifest$source_program %||% "(not recorded)"), width = footnote_wrap_width), collapse = "\n")
)

p <- ggplot(data_plot, aes(x = label, y = mean, ymin = lo, ymax = hi, color = kind, shape = kind)) +
  geom_pointrange(position = position_dodge(width = 0.4), size = 0.5) +
  geom_hline(yintercept = 0, linetype = 2, linewidth = 0.6) +
  scale_color_manual(values = c(
    "Observed" = "#7F8C8D", "Posterior (shrunk)" = "#1B4F72",
    "Pooled" = "#000000", "Predicted (mu_new)" = "#7B241C"
  )) +
  scale_shape_manual(values = c(
    "Observed" = 1, "Posterior (shrunk)" = 16, "Pooled" = 18, "Predicted (mu_new)" = 17
  )) +
  coord_flip() +
  xlab("") + ylab(xlab_text) +
  ggtitle(title_text, subtitle = subtitle_text) +
  labs(color = "", shape = "", caption = caption_text) +
  theme_bw() +
  theme(
    plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 10, color = "grey35", hjust = 0.5),
    plot.caption = element_text(size = 8, hjust = 0, face = "italic"),
    legend.position = "bottom"
  )

plot_height <- max(4, 0.45 * length(study_order) + 2) + 0.15 * length(strsplit(caption_text, "\n")[[1]])
ggsave(args$out, plot = p, width = plot_width, height = plot_height, dpi = 150)

cat("Pooled placebo forest plot saved to:", args$out, "\n")
cat(sprintf("Pooled placebo effect (m): %.2f%% (95%% CrI: %.2f, %.2f)\n", m_mean, m_lo, m_hi))
cat(sprintf("Between-study SD (sigma_m): %.2f (95%% CrI: %.2f, %.2f)\n", sigma_mean, sigma_lo, sigma_hi))
cat(sprintf("Predicted placebo effect in a new study (mu_new): %.2f%% (95%% CrI: %.2f, %.2f)\n",
            mu_new_mean, mu_new_lo, mu_new_hi))
```

### B9. `named_contrast.R`

Utility (not a numbered step) — resolves a named head-to-head contrast from an already-fitted run's posterior, instead of a hardcoded d[k] index.

```r
#!/usr/bin/env Rscript
# Ad hoc utility: resolves a contrast between two treatments BY NAME from a
# fitted model's posterior, never by a hardcoded d[k] index. Adapted from
# the atlas branch's named_contrast.R -- replaces the exact anti-pattern
# atlas calls out: `TZP15_vs_Sema72 <- d[18] - d[89]`, a hardcoded posterior
# index that silently goes wrong if treatment order shifts between runs.
#
# Not a numbered pipeline step -- use whenever a specific head-to-head
# comparison is needed from an already-fitted run.
#
# Usage:
#   scripts/run_r.sh scripts/named_contrast.R \
#     --samples <samples.rds> --arm-info <arm_info.rds> \
#     --treat1 "vk2735 10mg oral" --treat2 "vk2735 10mg qw" [--out <contrast.yaml>]

suppressPackageStartupMessages({
  library(coda)
  library(yaml)
})

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
script_dir <- dirname(normalizePath(script_path))
source(file.path(script_dir, "lib_common.R"))

args <- parse_args(list(
  samples  = list(required = TRUE),
  arm_info = list(required = TRUE),
  treat1   = list(required = TRUE),
  treat2   = list(required = TRUE),
  out      = list(default = NULL)
))

samples <- readRDS(args$samples)
arm_info <- readRDS(args$arm_info)

cn <- colnames(samples[[1]])
samples_mat <- do.call(rbind, lapply(samples, function(x) x[, , drop = FALSE]))
colnames(samples_mat) <- cn

find_arm <- function(name) {
  k <- arm_info$arm_ind[tolower(arm_info$treatment) == tolower(name)]
  if (length(k) == 0) {
    stop(
      "Treatment not found in this network's arm_info: '", name, "'. ",
      "Available: ", paste(head(sort(unique(arm_info$treatment)), 15), collapse = ", "),
      if (length(unique(arm_info$treatment)) > 15) ", ..." else ""
    )
  }
  k[1]
}

k1 <- find_arm(args$treat1)
k2 <- find_arm(args$treat2)

d1_col <- paste0("d[", k1, "]")
d2_col <- paste0("d[", k2, "]")
if (!d1_col %in% colnames(samples_mat)) stop("Node ", d1_col, " (", args$treat1, ") not in samples.")
if (!d2_col %in% colnames(samples_mat)) stop("Node ", d2_col, " (", args$treat2, ") not in samples.")

diff <- samples_mat[, d1_col] - samples_mat[, d2_col]
mean_diff <- mean(diff)
ci <- quantile(diff, c(0.025, 0.975))
p_treat1_better <- mean(diff < 0)

cat(sprintf("%s vs %s\n", args$treat1, args$treat2))
cat(sprintf("  contrast (arm_ind %d - arm_ind %d): %.2f (%.2f, %.2f)\n",
            k1, k2, mean_diff, ci[1], ci[2]))
cat(sprintf("  P(%s better) = %.3f\n", args$treat1, p_treat1_better))

if (!is.null(args$out)) {
  write_yaml(
    list(
      generated_at = as.character(Sys.time()),
      treat1 = args$treat1, treat2 = args$treat2,
      arm_ind1 = k1, arm_ind2 = k2,
      mean = round(mean_diff, 3), ci_lo = round(ci[1], 3), ci_hi = round(ci[2], 3),
      p_treat1_better = round(p_treat1_better, 3)
    ),
    args$out
  )
  cat("Written to:", args$out, "\n")
}
```

---

## Appendix D — Session Environment Wrappers (embedded, no external files needed)

This HPC environment doesn't guarantee `Rscript` on `PATH`, and `rjags`
needs `module load jags` run in the same shell before it links — these three
wrappers resolve that portably. Materialize them the same way as Appendix B
(write to a real file, `chmod +x`, then exec), and use D2 in place of a bare
\`Rscript\` for any script above that does NOT need rjags, D3 for the one that
does (`fit_bnma_model.R`, `fit_pooled_placebo_model.R`).

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
# Wrapper for any /bnma script that does NOT need rjags/JAGS -- resolves
# Rscript portably (see _resolve_rscript.sh) and execs it. Use
# run_with_jags.sh instead for fit_bnma_model.R.
#
# Usage: scripts/run_r.sh <path/to/script.R> [args...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_resolve_rscript.sh"

exec "$RSCRIPT_BIN" "$@"
```

### D3. `run_with_jags.sh`

Wrapper for `fit_bnma_model.R`/`fit_pooled_placebo_model.R`: loads the `jags` environment module before exec'ing Rscript.

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

