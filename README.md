# `/cmh-ci` — PRD/QA dataset filtering & guided BNMA skill

A Claude Code skill (`/cmh-ci`) for a Cardiometabolic Health
competitive-intelligence QA/PRD dataset. It has two use cases, not one:
just exploring what's in the data (studies, compounds, phases, evidence
tiers — a complete outcome on its own, no analysis required), and, when
that's the goal, running a Bayesian network meta-analysis (BNMA) on a
single continuous endpoint — weight loss, HbA1c, physical function, etc. —
from that same reviewed data or a standalone workbook.

It replaces a hardcoded, hand-edited study list with a guided workflow: it
always introduces what's in the data before asking you to decide anything
— and stays there, conversationally, if that's all you wanted — lets you
name specific studies or compounds up front if you know what you
want, walks the remaining scope questions (endpoint, route, evidence,
region) one at a time rather than as a wall of text, confirms the study
selection and naming/pooling flags in a grouped review, confirms the
resulting subset is actually sufficient (offering to bring in custom data
if not) before touching disk, asks explicitly whether the goal is a full
BNMA run at all — reviewing or updating the data is a complete outcome on
its own — and only then builds the model input and collects modelling
preferences (heterogeneity, effect type) — informed by the real network
structure, not asked blind — before running straight through to a forest
plot, hard-stopping only on a real gate failure (a study missing from the
manifest). It does not run any automated post-fit diagnostics (no Rhat/ESS,
no DIC/consistency check) — matching the real production
`EliLillyCo/CMH.BNMA` app's own behavior.

See [DESIGN.md](DESIGN.md) for the full design rationale — problem statement,
current-state findings, and the skill architecture.

## What's included

- `SKILL.md` — the skill itself: the full step-by-step workflow (introduce
  the PRD dataset, list studies, pick which to include with a naming/route
  pooling-risk QA gate on the selection → ask whether non-PRD data should
  be added → convert it to the QA schema → merge it in → confirm run
  intent, create folders, write the manifest → collect modelling
  preferences → fit and produce both forest plots plus a re-runnable
  `.Rmd`/rendered `.html` report) *and* every deterministic script/model
  file it calls, embedded verbatim in its own appendices rather than kept
  as separate files:
  - **Appendix A** — the JAGS model specs (`model_random.txt` /
    `model_fixed.txt` / `model_simultaneous.txt` /
    `model_simultaneous_fixed.txt` / `model_placebo_random.txt`), selected
    per run by the manifest's `model_type`.
  - **Appendix B** — the R scripts behind the pipeline: `run_bnma_pipeline.R`
    (B1) — one consolidated script covering data load/merge, the
    naming/pooling QA check, BATMAN construction, the JAGS fit, and both
    forest plots — and `append_to_qa.R` (B2), the promote-to-QA path. The
    per-stage scripts this used to call as separate files (`lib_common.R`,
    `load_merge_data.R`, `check_naming_pooling.R`, `build_batman_data.R`,
    `fit_bnma_model.R`, `fit_pooled_placebo_model.R`, `make_forest_plot.R`,
    `make_placebo_forest_plot.R`, `named_contrast.R`) were retired and
    inlined into `run_bnma_pipeline.R`. There's no separate shell-wrapper
    appendix either anymore — the `run_r.sh`/`run_with_jags.sh` wrappers
    were dropped; `module load R jags` now runs inline before the
    `Rscript` call itself.

  During a session, the skill materializes whichever of these it needs into
  a real file (a session lib dir, then `programs/<slug>/lib/` once that
  folder exists) before invoking it — nothing needs to pre-exist on disk
  beyond `SKILL.md` itself.
- `.claude-plugin/marketplace.json` — marketplace manifest for the
  plugin-install path. Currently **not** the supported install method for
  this branch's flat layout (its `plugins/bnma` source path predates the
  flatten and no longer exists) — see Install below for what actually works
  today.

There is no bundled test fixture / `tests/` directory, and no
`compound_registry.yaml` either — naming/pooling decisions are resolved
live each run via the manifest's `compound_relabels`/`treatment_relabels`
fields, not persisted to a lookup file across runs (see Verify your setup
below for the missing test fixture).

## Prerequisites

This skill does **not** bundle R, JAGS, or any R package — your own
HPC/Positron environment needs, before first use:
- `module load R` and `module load jags` on `PATH` (or `Rscript` directly on
  `PATH` — the materialized `_resolve_rscript.sh` tries both, in that order)
- R packages: `dplyr`, `readxl`, `writexl`, `ggplot2`, `ggtext`, `coda`,
  `yaml`, `jsonlite`, `rjags`

## Install

The plugin-marketplace path (`/plugin marketplace add` / `/plugin install`)
isn't wired up for this branch's flat repo layout — the marketplace
manifest still points at a nested `plugins/bnma/` path this branch's
flatten commit removed. Until that's fixed, install as a personal skill
instead:

1. Clone https://github.com/tomdelanylilly/BNMA_SKILL (private repo —
   request access if you can't see it), and check out the `cmh-ci_v3`
   branch.
2. Copy the repo's `SKILL.md` (and, optionally, `CLAUDE.md` for the
   always-loaded pointer) into your own `.claude/skills/cmh-ci/` folder —
   that's the only file actually needed at runtime; `README.md`/
   `DESIGN.md`/etc. are documentation, not required for the skill to load.
3. `/cmh-ci` is then available in any Claude Code session.

### Verify your setup

There's no bundled smoke-test fixture to run non-interactively (see What's
included above). Confirm your R/JAGS environment resolves before pointing
`/cmh-ci` at real data:

```bash
module load R jags 2>/dev/null
Rscript -e 'library(rjags); library(dplyr); library(readxl); library(writexl); library(ggplot2); library(ggtext); library(coda); library(yaml); library(jsonlite)'
```

If that loads cleanly, invoke `/cmh-ci` directly — step 1 materializes and
runs its own scripts against whatever PRD file you point it at, no separate
verification run needed.

### Updating

There's no `/plugin marketplace update` for a personal skill install —
`git pull` (or re-clone) this repo and re-copy `SKILL.md` (and `CLAUDE.md`)
into `~/.claude/skills/cmh-ci/` to pick up changes.

## Using it

In a Claude Code session, invoke `/cmh-ci` (or just describe what you want
— "what's in this dataset", "run a BNMA on these compounds", "refresh the
weight-loss forest plot"). From there:

1. **Point it at your data** — an exact PRD file path, a folder to search
   (defaults to your project's own working directory if you give nothing),
   or a standalone workbook that isn't in the QA/PRD schema (it adapts those
   automatically rather than silently misreading them). It always
   introduces what's actually in the data first — every study, compound,
   phase, and evidence tier from both the Observed and Prediction sheets —
   before asking you to decide anything. If you're just exploring, it stays
   conversational here; nothing else happens until you say what you want.
2. **Which studies do you want to include** — name specific studies (e.g.
   "ATTAIN-1 vs. SURMOUNT-4") and/or compounds up front if you already know
   what you want; either gets pre-resolved and proposed as the include
   list. Once you pick, it echoes the confirmed selection with phase,
   route, and compound stated plainly right in the confirmation — no
   separate naming/route round-trip for the routine case. A genuine
   anomaly a phase/route/compound line wouldn't surface on its own (two
   studies that are actually the same trial at different follow-up points,
   a real spelling inconsistency, the same study appearing in both sheets)
   still gets its own explicit call-out before proceeding.
3. **Anything else to add** — a press release, new readout, hand-digitized
   data, or another workbook not yet in the QA/PRD schema. Saying no here
   is a complete outcome — reviewing or updating the data without fitting
   anything is a valid session.
4. **Convert the new data into the QA schema** (only if step 3 said yes) —
   pasted rows, a file, or a subset of another workbook, shown for
   confirmation before anything is written.
5. **Merge it with the selected subset and reload** (only if step 3 said
   yes) — loops back to step 3 ("anything else?") until you say the subset
   is sufficient.
6. **Confirm you actually want a BNMA run** — your goal for this session
   might just have been reviewing the data or getting it into QA. Only if
   you say yes does it create the QA-rooted working folders and write the
   YAML manifest recording every decision made so far.
7. **Collect modelling preferences** — heterogeneity (random/fixed) and
   route/evidence filters, asked *after* the real network structure is
   known, so any recommendation is stated directly rather than corrected
   after the fact. It then fits the model via JAGS and produces both
   forest plots (placebo-adjusted and absolute), a re-runnable `.Rmd` with
   real code chunks, and a rendered `.html` report — the permanent audit
   trail for the run.

See `SKILL.md` for the full step-by-step detail, including exactly what each
manifest field controls.

## Status

Smoke-tested end-to-end (steps 1–7 under that earlier version's own, since
superseded, step numbering — load/merge through a real JAGS fit and forest
plot render) against a synthetic fixture during this skill's earlier,
separate-script-files version — that fixture wasn't carried over into the
embedded-in-`SKILL.md` layout (see What's included above), and the step
numbers don't correspond to the current Step 1–7 structure described above
(see DESIGN.md's design-iteration history for the renumbering). Since then,
run against real datasets, which caught and fixed a genuine star-network
CI-inflation bug (see `model_simultaneous_fixed.txt`'s own header comment in
Appendix A), and reconfirmed that same finding independently against a real
hand-written team script fit on the same data.
