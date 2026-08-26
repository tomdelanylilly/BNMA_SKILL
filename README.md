# BNMA_SKILL

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
  the PRD dataset → ask which studies → review the subset → optionally
  augment with custom data → confirm run intent → build the model input →
  collect modelling preferences → fit → forest plot → driver script) *and*
  every deterministic script/model file it calls, embedded verbatim in its
  own appendices rather than kept as separate files:
  - **Appendix A** — the JAGS model specs (`model_random.txt` /
    `model_fixed.txt` / `model_simultaneous.txt` /
    `model_simultaneous_fixed.txt` / `model_placebo_random.txt`), selected
    per run by the manifest's `model_type`.
  - **Appendix B** — the R scripts behind each pipeline stage
    (`lib_common.R`'s shared helpers, `load_merge_data.R`,
    `append_to_qa.R`, `check_naming_pooling.R`, `build_batman_data.R`,
    `fit_bnma_model.R`, `fit_pooled_placebo_model.R`, `make_forest_plot.R`,
    `make_placebo_forest_plot.R`, `named_contrast.R`).
  - **Appendix D** — the shell wrappers (`_resolve_rscript.sh`, `run_r.sh`,
    `run_with_jags.sh`) that resolve `Rscript`/JAGS portably;
    `run_with_jags.sh` loads the `jags` environment module first (`rjags`
    fails to link without it).

  During a session, the skill materializes whichever of these it needs into
  a real file (a session lib dir, then `programs/<slug>/lib/` once that
  folder exists) before invoking it — nothing needs to pre-exist on disk
  beyond `SKILL.md` itself.
- `compound_registry.yaml` — persisted naming-QA decisions, so a resolved
  compound-name pair is never re-flagged.
- `.claude-plugin/marketplace.json` — marketplace manifest for the
  plugin-install path. Currently **not** the supported install method for
  this branch's flat layout (its `plugins/bnma` source path predates the
  flatten and no longer exists) — see Install below for what actually works
  today.

There is no bundled test fixture / `tests/` directory anymore — that was
part of the pre-consolidation, separate-script-files layout and wasn't
carried over into the embedded-in-`SKILL.md` design (see Verify your setup
below).

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
   request access if you can't see it), and check out the `cmh-ci` branch.
2. Copy the repo into your own `.claude/skills/cmh-ci/` folder — only
   `SKILL.md` and `compound_registry.yaml` are actually needed at runtime;
   `README.md`/`DESIGN.md`/etc. are documentation, not required for the
   skill to load.
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
`git pull` (or re-clone) this repo and re-copy `SKILL.md` and
`compound_registry.yaml` into `~/.claude/skills/cmh-ci/` to pick up changes.

## Using it

In a Claude Code session, invoke `/cmh-ci` (or just describe what you want
— "what's in this dataset", "run a BNMA on these compounds", "refresh the
weight-loss forest plot"). From there:

1. **Point it at your data** — an exact PRD file path, a folder to search
   (defaults to your project's own working directory if you give nothing),
   or a standalone workbook that isn't in the QA/PRD schema (it adapts those
   automatically rather than silently misreading them). Given a folder, it
   searches for PRD files specifically (a newer, not-yet-promoted QA file is
   a later concern — step 4 — not this one) and lists every candidate with
   modified dates for an explicit pick, rather than guessing the newest or
   best-named match. Once picked, it always introduces what's actually in
   the data first — studies, compounds, phases, evidence tiers — before
   asking you to decide anything. If you're just exploring, it stays
   conversational here; no folders or manifest until you say you want to
   move toward a run. It also runs a naming/route pooling-risk QA check
   automatically at this point — no stop here, the results feed into the
   next step.
2. **Which studies are you interested in** — name specific studies (e.g.
   "ATTAIN-1 vs. SURMOUNT-4") and/or compounds up front if you already know
   what you want; either gets resolved first. Then endpoint, route,
   evidence tier, region — each a short question with a stated default,
   answered one at a time rather than as one big form.
3. **Review the subset** — every naming/pooling flag and every study (with
   phase 1/2 and no-placebo-arm studies always called out individually) in
   one grouped message with a stated default per item. A study you named
   in step 2 shows up here too, with "include, per your request" as the
   stated reason — nothing skips this review. Reply with just what you
   want to change; everything else proceeds on the shown default/proposal.
4. **A follow-up confirms the subset is sufficient** and offers to bring in
   custom/external data not yet in QA/PRD.
5. **Convert the new data into the QA schema** (only if step 4 said yes) —
   pasted rows, a file, or a subset of another workbook, shown for
   confirmation.
6. **Merge it with the selected subset** — new data defaults to a
   temporary, project-only addition (not written to the shared QA file
   unless you explicitly ask to promote it). Loops back to step 4 until
   the subset is confirmed sufficient.
7. **Confirms whether you actually want a BNMA run** — your goal for this
   session might just have been reviewing the data or getting it into QA,
   and that's a complete outcome. Only if you say yes does it move on.
8. It proposes working folders (rooted under the QA tier, not wherever the
   PRD file happened to be found) and an optional project CLAUDE.md, writes
   a YAML manifest recording every decision, and builds the model input
   (the BATMAN data structure).
9. **Collect modelling preferences** — heterogeneity and effect type
   (placebo-adjusted vs. absolute), asked *after* the real network
   structure from step 8 is known, so the recommendation is stated directly
   rather than corrected after the fact.
10. It fits the model via JAGS, renders the forest plot with a traceable
    footnote (source data, source program, contributing studies), and
    writes a driver script next to the manifest that reproduces the whole
    run from scratch — re-running it later just reloads the cached JAGS
    samples unless you delete them.

See `SKILL.md` for the full step-by-step detail, including exactly what each
manifest field controls.

## Status

Smoke-tested end-to-end (steps 1–7 under that earlier version's own, since
superseded, step numbering — load/merge through a real JAGS fit and forest
plot render) against a synthetic fixture during this skill's earlier,
separate-script-files version — that fixture wasn't carried over into the
embedded-in-`SKILL.md` layout (see What's included above), and the step
numbers don't correspond to the current Step 1–10 structure described above
(see DESIGN.md's design-iteration history for the renumbering). Since then,
run against real datasets, which caught and fixed a genuine star-network
CI-inflation bug (see `model_simultaneous_fixed.txt`'s own header comment in
Appendix A), and reconfirmed that same finding independently against a real
hand-written team script fit on the same data.
