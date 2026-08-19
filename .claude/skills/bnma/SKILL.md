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

## Step 0 — Scope this run (ask ONCE, in one structured block)

Before touching data, ask every scoping question together, in one message,
each with a stated default — never as a slow back-and-forth interview
(2026-08-19: restructured from asking route/evidence/region/heterogeneity
piecemeal across several later steps, per a colleague's parallel `atlas`
skill's UX — cherry-picked because asking once with defaults is a real
improvement over discovering these one flagged row at a time). The user
answers only what they want to override; everything else proceeds on the
default shown. Use this exact template (fill in the dataset row from
what's detectable/given; state real defaults, not placeholders):

```
╭──────────────────────────────────────────────────────────────────╮
│  /bnma · scope this run                                           │
├──────────────────────────────────────────────────────────────────┤
│  Reply with just what you want to change; anything unmentioned    │
│  uses the default shown with ►.                                   │
╰──────────────────────────────────────────────────────────────────╯
  1  Dataset            <PRD path, + QA path if a newer unpromoted file exists>
  2  Route            ► both (oral + injectable)      oral only     injectable only
  3  Evidence         ► both (observed + prediction)   observed only   prediction only
  4  Region           ► global only                    + other regions present in the workbook
  5  Heterogeneity    ► random-effects (rand_effect)    fixed-effect
  6  Effect to report ► placebo-adjusted (relative)      absolute       both
```

Echo back exactly what was locked in before Step 1 runs.

Notes on specific rows:

- **Row 1 (dataset):** resolve per the workflow doc's fallback rule — try
  the QA path first, fall back to PRD if it's moved/been promoted. Do not
  guess a path — ask, or use exactly what the user gives you.
- **Row 2/3 (route/evidence):** recorded as `route_filter` and
  `evidence_filter` (see Step 4's example). Omit the field (or `both`) if no
  filtering is wanted on that axis — `build_batman_data.R` treats a missing
  field as `both`, so manifests written before these fields existed keep
  working unchanged. Placebo rows are never dropped by the route filter,
  regardless of which route is chosen — a placebo arm's `aom` tag reflects
  its paired active comparator's route, not a property of placebo itself.
- **Row 4 (region):** some workbooks carry a region-scoped extra sheet
  alongside the standard global `Observed`/`Prediction` sheets — found in
  practice: a `"China Observed"` sheet. `load_merge_data.R` detects any
  sheet named `"<Region> Observed"` or `"<Region> Prediction"`
  (case-insensitive) and tags its rows with that region (lowercased); the
  standard sheets are tagged `"global"`. Recorded as `region_filter` — a
  list of regions to include. **Unlike route/evidence, this defaults to
  `["global"]` only, not "both"** — a region-scoped sheet is read into
  every merge unconditionally, so defaulting to include-everything would
  silently pull a newly-added regional dataset into every existing run the
  moment someone adds that sheet to a workbook. No placebo exemption here
  either: a region's own placebo rows are part of that region's scope.
- **Row 5 (heterogeneity):** recorded as `model_type` (see Step 4's
  example) — `rand_effect` is the recommended default, `fixed_effect` a
  real, legitimate alternative, not a fallback. **This answer is
  preliminary** — Step 5's heterogeneity-estimability check re-examines it
  against the actual built network once real per-node study counts are
  known, and can prompt a revision (particularly if the network turns out
  to be a full star, where heterogeneity literally cannot be estimated —
  see Step 5). Don't skip asking here just because Step 5 might override it
  later; the point is a stated, traceable starting position, not a silent
  default deferred indefinitely.
- **Row 6 (effect type):** recorded as `effect_type` — `relative`
  (placebo-adjusted) is the default view; `absolute` needs
  `model_type: simultaneous` (see Step 5); `both` produces both plots.

**Compound-first entry point and study-by-study selection are NOT part of
this upfront block** — they have a real data dependency (Step 2's naming
gate must run against the full merged dataset first, so a user-given
compound name or treatment string can be checked against the vetted,
de-duplicated list) that the "ask everything before touching data" ideal
can't honor. Those stay at Step 2.5/Step 3, after the data is loaded and
vetted — see below.

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

Do not proceed to step 2.5/3 until every active flag has an explicit
resolution.

## Step 2.5 — Compound-first entry point (optional)

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
(`plot_treatments`) and in what order — `effect_type` and `model_type` were
already asked in Step 0; don't re-ask them here, just carry the answer
forward into the manifest (Step 4).

## Step 4 — Write the manifest

Write a YAML manifest capturing everything decided so far — this is the
traceable artifact that replaces a commented-out R vector. Example shape:

```yaml
created_at: "2026-08-14"
source_data:
  prd: /lillyce/prd/diabetes/bnma/obesity/data/shared/weight/cwm_wl_nont2d_prd_20260805.xlsx
  qa: null
source_program: <path to whatever script/session produced this run>
route_filter: both # oral | injectable | both -- from Step 0; omit or "both" = no route filtering
evidence_filter: both # observed | prediction | both -- from Step 0; omit or "both" = no evidence filtering
compound_filter: null # optional list of compound names -- from Step 2.5's compound-first entry point; omit/null = no compound filtering
region_filter: [global] # list of regions to include -- from Step 0; omit = ["global"] only, unlike route/evidence_filter's "both" default
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
placebo_clamp: false # optional -- set true to force any placebo row's positive (weight-gain) pchg_wl_ee to 0; requires placebo_clamp_reason
se_fallback: false # optional -- set true to derive se_wl_ee = se_fallback_sd/sqrt(n) for rows missing se_wl_ee but with a known n; requires se_fallback_reason
supplementary_data: [] # optional -- literal rows for data not yet in the QA/PRD workbook; see below
model_type: rand_effect # rand_effect (recommended default for new runs) | fixed_effect | simultaneous (legacy) -- from Step 0; omit or "simultaneous" = today's unconditional phantom-bridging behavior, unchanged; see Step 5
plot_treatments:
  - tirzepatide 5mg qw
  - tirzepatide 10mg qw
  - tirzepatide 15mg qw
effect_type: relative # from Step 0
```

`compound_relabels` is for a naming-QA flag resolved as "these rows were
mislabeled, merge into the canonical spelling" -- applied globally by
compound string. `treatment_relabels` is the same idea but for the
`treatment` string itself (changes which arm a row maps to, not just which
compound it's attributed to). `row_exclusions` is for a single anomalous or
duplicate row within an otherwise-included study; add `"n"` (quoted) when
two rows share the same `(study_name, treatment)` and need a third field to
tell them apart.

**`placebo_clamp`** forces any placebo row reporting a positive (weight-gain)
`pchg_wl_ee` to 0 before fitting. Found in a real analyst script
(`bnma-nonadj-11AUG2026.R`, applied unconditionally there with no
traceability — "Yongming advised setting the placebo effect to zero").
Opt-in and reasoned here like everything else in this manifest: absent means
no clamping (today's behavior, unchanged). Setting `placebo_clamp: true`
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

**`se_fallback`** derives `se_wl_ee = se_fallback_sd / sqrt(n)` for any row
missing `se_wl_ee` but with a known arm sample size `n` — rescuing a row the
unusable-row filter would otherwise silently drop. This is a real, repeated
team convention, not a one-off (unlike `placebo_clamp`, which stays a
per-run judgment call): `redefine1`'s own `curator_note` documents the exact
formula ("se is calculated with 10/sqrt(n) where sd=10 is commonly used for
%change in body weight in nont2d"), and it's actually applied — not just
written down — in `brenipatide_gzmu_misc5.R` and `brenipatide_gzmu_gzmd.R`.
Still opt-in and still requires a reason, same hard-error pattern as
`placebo_clamp` — fabricating an SE is always a visible, deliberate choice
for a given run, never a silent default:
```yaml
se_fallback: true
se_fallback_reason: "redefine1's own curator_note documents this exact
  derivation but never applied it -- applying it here to include a large
  Phase 3 study that would otherwise be dropped for a missing SE."
se_fallback_sd: 10  # optional, default 10 -- the team's stated standard
                     # assumption for %change in body weight in nont2d;
                     # override only if a different population/endpoint's
                     # own convention is documented elsewhere.
```

**`supplementary_data`** is for a small, deliberately-curated addition that
hasn't been promoted into the QA/PRD workbook yet — e.g. a hand-digitized
dose-response series pulled from a slide deck, the same situation
`bnma-nonadj-11AUG2026.R` handles by `bind_rows()`-ing a hand-typed tibble
straight into its analysis with no traceability at all. This is a stopgap,
not a permanent home for the data — the row should still get entered as a
real QA row via the project CLAUDE.md's Flow 1 once it's ready, same
"QA is the live working copy" principle as everywhere else in this
workspace. Each entry requires `study_name`, `treatment`, `compound`,
`pchg_wl_ee`, `se_wl_ee`, and `reason`; `aom`/`region` are optional:
```yaml
supplementary_data:
  - study_name: "GZMD+GZMU"
    treatment: "brenipatide 8mg q4w"
    compound: brenipatide
    pchg_wl_ee: -13.86
    se_wl_ee: 0.26
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
  --study-info-out /tmp/bnma_study_info.rds [--arm-rows-out /tmp/bnma_arm_rows.rds]
```

If this errors because studies are missing from the manifest, that's the
intended guard — go back to step 3/4 with the user, don't patch around it.

`--arm-rows-out` is optional but recommended for every new run — it saves
the real (non-phantom), study-level arm rows that Step 5.6's network/
consistency/DIC diagnostics gate needs. Existing driver scripts that omit
it keep working unchanged; Step 5.6 simply isn't runnable without it.

`build_batman_data.R` also prints a **heterogeneity estimability** check —
for every non-placebo treatment node, how many distinct studies feed it.
This is the checkpoint for the fixed-vs-random-effects question asked in
Step 0: if it reports a **star network** (zero nodes with ≥2 contributing
studies — the exact situation in `pf_nma.R`, a physical-function
sub-network where every comparison has exactly one supporting study),
between-study heterogeneity literally cannot be estimated from the data, and
`model_type: fixed_effect` is the appropriate primary analysis, not a
stylistic preference — quote `pf_nma.R`'s own rationale to the statistician
("with only 1 study per comparison, between-study heterogeneity cannot be
estimated; fixed-effects is the appropriate primary analysis") and get an
explicit confirmation/revision of `model_type` in the manifest **before**
running the fit below, even if Step 0's answer already stated a preference.
When the network isn't a full star (some nodes have multi-study support,
even if most don't — this is the common case for the obesity landscape data,
where dozens of single-study nodes coexist with a handful of well-replicated
ones), heterogeneity is estimable from the network as a whole; surface the
node counts for information, but `rand_effect` vs. `fixed_effect` remains
the analyst's own call, same as always.

Then fit (or load a cached fit of) the model. **Must go through the JAGS
wrapper** — plain `Rscript` will fail to load `rjags` in this environment:

```bash
scripts/run_with_jags.sh scripts/fit_bnma_model.R \
  --batman /tmp/bnma_batman.rds --model model_random.txt \
  --cache <programs_folder>/samples_<run_name>.rds
```

**Which model file to use is driven by the manifest's `model_type` field**
(see Step 4's example) — pass the matching file here:
- `model_type: rand_effect` (recommended default for new runs) →
  `--model model_random.txt`
- `model_type: fixed_effect` → `--model model_fixed.txt`
- `model_type: simultaneous` (legacy) or omitted → `--model
  model_simultaneous.txt`

**MCMC settings and chain initialization follow the NMA Output Review
Process Guide** (2026 V2) — n.adapt 10,000, burn-in 20,000, 50,000 sampling
iterations thinned to 5 (3 chains), with chain 1 initialized to exactly 0 on
the baseline (`phi`, and `m` for `model_simultaneous.txt`) and
treatment-effect (`d`) nodes and chains 2–3 drawing from those same nodes'
own vague priors (Normal(0, SD=100)) — all built into `fit_bnma_model.R`
itself, nothing to configure per run. Override via `--n_adapt`/`--n_burnin`/
`--n_iter`/`--thin` if a specific run's convergence diagnostics (Step 5.5)
call for more.

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
(see Step 0); the real production tool has no absolute-effect view at all,
since a non-hierarchical model has no single global baseline to compute one
from.

**`effect_type: absolute`'s pooled baseline is *not* simply the model's own
`m` node.** `make_forest_plot.R` computes it as the average of `phi[i]`
across only the studies that actually have a real placebo arm (per
`study_info.rds`'s `has_placebo` column, set by `build_batman_data.R`) —
not `m` itself, which is drawn from *every* study's `phi[i]` including
head-to-head trials with no placebo row at all. Found by testing
(2026-08-19): a no-placebo study's `phi[i]` is purely a hierarchical-prior
artifact with nothing real anchoring it — two such studies had `phi[i]` of
-15 and -25 against every real-placebo study's -3 to +1, dragging the
naive `m`-based pooled baseline from a plausible ~-2% to an implausible
-5.9%. The plot's subtitle reports both this pooled baseline (`μ`, with its
own 95% CrI) and `τ` (the between-study SD of the *relative* treatment
effect — `sigma`, not `sigma_m` — per the user's explicit convention), so a
reviewer sees the method, not just the number.

**This is a modelled, shrunk placebo level, not any single trial's observed
placebo** — footnote it as such (this caveat, from a colleague's parallel
`atlas` skill's `model_spec.md`, applies equally to our own exchangeable-
baseline model) so it isn't mistaken for a directly-observed value.

Give the cache file a run-specific name (per the workflow doc's "cached MCMC
samples are expensive to regenerate, version-specific name" rule) — don't
reuse another run's cache path.

## Step 5.5 — Convergence diagnostics (automatic, never skipped)

`fit_bnma_model.R` runs MCMC convergence diagnostics itself, right after
every fit (fresh or loaded from cache) — nothing to invoke separately, and
no way to opt out, same "no silent skip" rule as every other gate. It
prints a summary and writes `<cache-name>_diagnostics.yaml` next to the
samples file, e.g. `samples.rds` → `samples_diagnostics.yaml`.

Thresholds come from the BayesianAgent plugin's `model-diagnostics` skill
(its own JAGS/R2jags bar — looser than the 1.01/400 it quotes for Stan/NUTS,
since a Gibbs sampler's per-iteration efficiency isn't comparable):

| Metric | Good | Concern (fails) |
|---|---|---|
| Rhat (max across nodes) | ≤ 1.01 | > 1.10 |
| ESS (min across nodes) | ≥ 400 | < 100 |

Verdict is `pass`, `warn`, or `fail`. The fixed reference treatment (`d[1]`)
and any other zero-variance node (e.g. `model_fixed.txt`'s deterministic
`delta[i,j]`) are excluded from scoring — they're not actually sampled, so
their ESS is mathematically 0 and would force a false `fail` on every run
otherwise.

**A `fail` verdict must be surfaced to the user before Step 6** — show them
the printed summary and get an explicit decision (re-fit with more
`--n_iter`/`--n_burnin`, or proceed anyway with the caveat documented in the
footnote) rather than quietly producing a forest plot from a fit that didn't
converge. A `warn` is worth mentioning but not blocking.

To re-check an already-cached run without refitting (e.g. after changing
thresholds), run the diagnostics standalone:
```bash
scripts/run_r.sh scripts/check_convergence.R --samples <cache.rds> --out <diagnostics.yaml>
```

## Step 5.6 — Network/consistency/DIC diagnostics gate (automatic, `--skip-dic` to opt out)

Adapted from a colleague's parallel `atlas` skill's `diagnostics.R`
(cherry-picked 2026-08-19) — four checks on top of Step 5.5's convergence
check, together forming a single combined gate:

```bash
scripts/run_with_jags.sh scripts/check_network_diagnostics.R \
  --batman <batman.rds> --arm-rows <arm_rows.rds> --arm-info <arm_info.rds> \
  --samples <cache.rds> --out <network_diagnostics.yaml> [--gate] [--skip-dic]
```

Requires `--arm-rows-out` to have been passed to Step 5's
`build_batman_data.R` call — the checks below need the real, non-phantom
study-level rows, not the BATMAN-augmented version. Runs via
`run_with_jags.sh` unless `--skip-dic` is passed (then plain `run_r.sh`
works, since only the DIC check needs a second `rjags` fit).

1. **Network** — `igraph`: is the network one connected component? Which
   treatments have no *direct* placebo comparison (indirect-only, wider by
   construction)? `FAIL` if disconnected, `WARN` if any node is
   indirect-only.
2. **Uncertainty** — flags every single-study ("fragile") arm via its CrI
   width and study count. `WARN` if any exist — expected and common for the
   obesity landscape data, not usually a reason to stop, but worth knowing
   which specific arms are provisional.
3. **Consistency** (node-splitting, `netmeta::netsplit()`) — for every
   loop-informed comparison (one with both direct and indirect evidence),
   compares the two; `FAIL` if any disagree at p<0.05. Reports `N/A` for a
   star-shaped network (no loops to test — add a head-to-head study to
   enable this) or `SKIP` if the real-evidence network splits into
   disconnected sub-networks that only phantom-placebo bridging connects
   (those cross-sub-network estimates lean on the imputed placebo and can't
   be genuinely consistency-checked).
4. **DIC inconsistency** (NICE DSU TSD4) — fits a second, unrelated-mean-
   effects (UME) model and compares DIC to the ordinary consistency model.
   `FAIL` if the consistency model's DIC exceeds the UME model's by more
   than 5, `WARN` if by more than 2 (ideally the difference is negative —
   consistency preferred). **Always uses `model_random.txt` for its own
   internal comparison, regardless of which model the main analysis
   fit used** — both sides of a DIC comparison must share the same
   baseline structure (flat/independent `phi[i]`, matching the UME model's
   own hardcoded baseline) or the DIC difference would partly reflect a
   baseline mismatch instead of purely the consistency question being
   tested. `--model` can override this default deliberately (e.g. to test
   a different baseline's own consistency profile), but never to reuse
   whatever `--model` the main fit happened to pass as a shortcut.

Overall verdict is the worst of these four plus Step 5.5's convergence
check. Written to YAML (`<out>`), printed to console per-check. `--gate`
exits non-zero (status 2) on an overall `FAIL` — **surface a `FAIL` to the
user and get explicit sign-off before Step 6**, same rule as every other
gate in this skill; a `WARN` is worth mentioning but not blocking.

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
compound (this skill has plotted 20+ over one session) falls back to an
auto-generated distinct color rather than erroring or rendering blank;
extend `FIXED_COMPOUND_COLORS` as more of the team's own conventions are
confirmed, don't just hardcode a one-off run's colors elsewhere.

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
  "--study-info-out", "<study_info.rds>", "--arm-rows-out", "<arm_rows.rds>"
))
sys2(file.path(skill_dir, "scripts/run_with_jags.sh"), c(
  file.path(skill_dir, "scripts/fit_bnma_model.R"),
  "--batman", "<batman.rds>", "--model", file.path(skill_dir, "<model_random.txt|model_fixed.txt|model_simultaneous.txt -- match the manifest's model_type>"),
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
- No absolute-effect view for `model_type: rand_effect`/`fixed_effect` —
  confirmed via `BNMA_forest_plot-main.zip` that the real production tool
  doesn't have one either, since its non-hierarchical model has no single
  pooled baseline to compute one from. `effect_type: absolute` only works
  with the legacy `model_simultaneous.txt` (`model_type: simultaneous`).
- No formal node-splitting-vs-DIC reconciliation logic — Step 5.6 reports
  both independently; when they diverge (a real, informative disagreement,
  not a bug), trace the node-split flags back to their source study by hand
  before deciding whether to exclude, relabel, or accept the result.
