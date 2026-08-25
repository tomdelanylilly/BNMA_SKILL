# BNMA_SKILL

A Claude Code skill (`/bnma`) for running obesity/diabetes-landscape Bayesian
network meta-analyses (BNMA) on a single continuous endpoint — weight loss,
HbA1c, physical function, etc. — from a QA/PRD dataset or a standalone
workbook.

It replaces a hardcoded, hand-edited study list with a guided workflow: it
always introduces what's in the data before asking you to decide anything,
walks scope questions (route, evidence, region, heterogeneity, effect type)
one at a time rather than as a wall of text, then confirms the study
selection and naming/pooling flags in a grouped review, confirms the
resulting subset is actually sufficient (offering to bring in custom data
if not) before touching disk, and only then runs straight through to a
forest plot, hard-stopping only on a real gate failure (a study missing
from the manifest). It does not run any automated post-fit diagnostics (no
Rhat/ESS, no DIC/consistency check) — matching the real production
`EliLillyCo/CMH.BNMA` app's own behavior.

See [DESIGN.md](DESIGN.md) for the full design rationale — problem statement,
current-state findings, and the skill architecture.

## What's included

- `plugins/bnma/skills/bnma/SKILL.md` — the skill itself: the full step-by-step
  workflow (introduce data → locate → load/merge → naming/pooling QA →
  scope questions → study confirmation → sufficiency/custom-data check →
  build model input → fit → forest plot → driver script).
- `plugins/bnma/skills/bnma/scripts/` — the deterministic R steps behind each
  of those stages (data load/merge, the naming/route pooling-risk QA gate,
  BATMAN augmentation, the JAGS fit, the forest plot). `run_with_jags.sh`
  wraps the JAGS-fitting step so the `jags`
  environment module gets loaded first (`rjags` fails to link without it).
- `model_random.txt` / `model_fixed.txt` / `model_simultaneous.txt` /
  `model_simultaneous_fixed.txt` — the JAGS model specs, selected per run by
  the manifest's `model_type`.
- `model_placebo_random.txt` + `scripts/fit_pooled_placebo_model.R` — a
  separate, standalone pooled-placebo model that supplies the baseline for
  `--effect absolute` forest plots, independent of `model_type` (adopted
  from the real production package, `EliLillyCo/CMH.BNMA`).
- `plugins/bnma/skills/bnma/compound_registry.yaml` — persisted naming-QA
  decisions, so a resolved compound-name pair is never re-flagged.
- `plugins/bnma/skills/bnma/tests/` — a synthetic fixture with deliberately
  seeded edge cases (near-duplicate compound names, a route-pooling
  collision, a Phase 2 study, a study with no placebo arm, a closed loop)
  and the manifest used to smoke-test the full
  pipeline end-to-end, including an actual JAGS fit.
- `.claude-plugin/marketplace.json` / `plugins/bnma/.claude-plugin/plugin.json`
  — this repo is both the plugin source and its own marketplace.

## Prerequisites

This plugin does **not** bundle R, JAGS, or any R package — your own
HPC/Positron environment needs, before first use:
- `module load R` and `module load jags` on `PATH` (or `Rscript` directly on
  `PATH` — `scripts/_resolve_rscript.sh` tries both, in that order)
- R packages: `dplyr`, `readxl`, `writexl`, `ggplot2`, `ggtext`, `coda`,
  `yaml`, `rjags`

## Install

```
/plugin marketplace add tomdelanylilly/BNMA_SKILL
/plugin install bnma@bnma-marketplace
```

`/bnma` is then available in any Claude Code session.

### Verify your setup

Before pointing it at a real dataset, run the pipeline against the bundled
synthetic fixture — the fastest way to confirm your environment (JAGS
module, R packages) actually works:

```bash
cd ~/.claude/plugins/cache/bnma-marketplace/bnma/<installed-version>/skills/bnma
scripts/run_r.sh tests/make_fixture.R --out /tmp/bnma_fixture.xlsx
scripts/run_r.sh scripts/load_merge_data.R --prd /tmp/bnma_fixture.xlsx --out /tmp/bnma_merged.rds
scripts/run_r.sh scripts/build_batman_data.R --data /tmp/bnma_merged.rds \
  --manifest tests/fixtures/smoke_test_manifest.yaml \
  --batman-out /tmp/batman.rds --arm-info-out /tmp/arm_info.rds --study-info-out /tmp/study_info.rds
```

If that runs clean, you're ready to point `/bnma` at a real QA/PRD file or
standalone workbook.

### Updating

```
/plugin marketplace update bnma-marketplace
/reload-plugins
```

Third-party marketplaces (this one included) don't auto-update, so both
steps are needed to pick up a new version after a `git push` to this repo.
`plugins/bnma/.claude-plugin/plugin.json`'s `version` is bumped on every
meaningful change — that's the only signal `/plugin marketplace update` has
that anything changed.

## Using it

In a Claude Code session, invoke `/bnma` (or just describe the run you want
— "run a BNMA on these compounds", "refresh the weight-loss forest plot"). From
there:

1. **Point it at your data** — an exact QA/PRD file path, a folder to search,
   or a standalone workbook that isn't in the QA/PRD schema (it adapts those
   automatically rather than silently misreading them). It always introduces
   what's actually in the data first — studies, compounds, phases, evidence
   tiers — before asking you to decide anything. If you're just exploring,
   it stays conversational here; no folders or manifest until you say you
   want to move toward a run.
2. It loads/merges the data and runs a naming/route pooling-risk QA check
   automatically — no stop here, the results feed into the next step.
3. **Scope questions, one at a time** — endpoint, route, evidence tier,
   region, heterogeneity model, effect type (placebo-adjusted vs. absolute)
   — each a short question with a stated default, answered one at a time
   rather than as one big form.
4. **Study confirmation** — every naming/pooling flag, every study (with
   phase 1/2 and no-placebo-arm studies always called out individually),
   and the plot's treatment list, in one grouped message with a stated
   default per item. Reply with just what you want to change; everything
   else proceeds on the shown default/proposal.
5. **A follow-up confirms the subset is sufficient** and offers to bring in
   custom/external data not yet in QA/PRD — new data defaults to a
   temporary, project-only addition (not written to the shared QA file
   unless you explicitly ask to promote it). This is also where working
   folders and an optional project CLAUDE.md are proposed.
6. It writes a YAML manifest recording every decision, builds the model
   input, fits the model via JAGS, and renders the
   forest plot with a traceable footnote (source data, source program,
   contributing studies).
7. It writes a driver script next to the manifest that reproduces the whole
   run from scratch — re-running it later just reloads the cached JAGS
   samples unless you delete them.

See `SKILL.md` for the full step-by-step detail, including exactly what each
manifest field controls.

## Status

Built and smoke-tested end-to-end against the synthetic fixture (steps 1–7,
including a real JAGS fit and forest plot render), and run against real
datasets — which caught and fixed a genuine star-network CI-inflation bug
(see `model_simultaneous_fixed.txt` and its own header comment), and
reconfirmed that same finding independently against a real hand-written team
script fit on the same data.
