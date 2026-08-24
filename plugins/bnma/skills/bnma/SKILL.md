---
name: bnma
description: >
  Run an obesity/diabetes-landscape Bayesian network meta-analysis (BNMA) on
  any single continuous endpoint (weight loss, HbA1c, physical function,
  etc.) from the QA/PRD dataset, with forced study-selection confirmation and
  a naming/route pooling-risk QA gate, instead of a hardcoded, hand-edited
  study list. Use this skill whenever the user wants to run, update, or
  refresh a BNMA forest plot from a QA/PRD dataset, or mentions "/bnma",
  "run the meta-analysis", "BATMAN", or a compound landscape forest plot.
---

# /bnma

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
│  /bnma · review & confirm                                          │
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
estimated; fixed-effects is the appropriate primary analysis"). **This does
not trigger a second round trip** — it's an objective statistical fact
about the data, not a discretionary preference, so if Step 3's answer said
`rand_effect` and the network turns out to be a full star, auto-correct
`model_type` to `fixed_effect` in the manifest and refit with that model,
noting the override loudly in the final summary/footnote rather than
stopping to ask again. **The same rule applies to `effect_type: absolute` on
`model_simultaneous.txt`/`model_simultaneous_fixed.txt`** — a full star means
`model_simultaneous_fixed.txt` (deterministic delta), not
`model_simultaneous.txt` (random delta); see the CI-inflation finding
documented below under Step 5's model-file list. When the network isn't a
full star (some nodes have
multi-study support, even if most don't — this is the common case for the
obesity landscape data, where dozens of single-study nodes coexist with a
handful of well-replicated ones), heterogeneity is estimable from the
network as a whole; surface the node counts for information, but
`rand_effect` vs. `fixed_effect` remains
the analyst's own call, same as always.

Then fit (or load a cached fit of) the model. **Must go through the JAGS
wrapper** — plain `Rscript` will fail to load `rjags` in this environment:

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
requested on a full-star network, use `model_simultaneous_fixed.txt`, not
`model_simultaneous.txt`** — same auto-correct-without-a-second-round-trip
rule as `rand_effect`→`fixed_effect` above (it's an objective statistical
fact, not a preference). `make_forest_plot.R`'s absolute-effect subtitle
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

Run it after Step 5's main fit, against the same run's `arm_rows.rds`:
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
underlying per-study shrinkage:
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
shifts). Cherry-picked from `atlas`, 2026-08-19:
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
