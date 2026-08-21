# BNMA_SKILL

A Claude Code skill (`/bnma`) for running obesity/diabetes-landscape Bayesian
network meta-analyses (BNMA) on a single continuous endpoint — weight loss,
HbA1c, physical function, etc. — from a QA/PRD dataset or a standalone
workbook.

It replaces a hardcoded, hand-edited study list with a guided, one-round-trip
workflow: it computes everything it can from the data, asks you to confirm
every genuinely discretionary choice in one consolidated message, then runs
straight through to a forest plot, hard-stopping only on a real gate failure
(non-convergence, a broken network, a study missing from the manifest).

See [DESIGN.md](DESIGN.md) for the full design rationale — problem statement,
current-state findings, and the skill architecture.

## What's included

- `plugins/bnma/skills/bnma/SKILL.md` — the skill itself: the full step-by-step
  workflow (locate data → load/merge → naming/pooling QA → one consolidated
  confirmation → build model input → fit → convergence/network diagnostics →
  forest plot → driver script).
- `plugins/bnma/skills/bnma/scripts/` — the deterministic R steps behind each
  of those stages (data load/merge, the naming/route pooling-risk QA gate,
  BATMAN augmentation, the JAGS fit, convergence/network/DIC diagnostics, the
  forest plot). `run_with_jags.sh` wraps the JAGS-fitting step so the `jags`
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
  collision, a Phase 2 study, a study with no placebo arm, a closed loop for
  the consistency/DIC gate) and the manifest used to smoke-test the full
  pipeline end-to-end, including an actual JAGS fit.
- `.claude-plugin/marketplace.json` / `plugins/bnma/.claude-plugin/plugin.json`
  — this repo is both the plugin source and its own marketplace.

## Prerequisites

This plugin does **not** bundle R, JAGS, or any R package — your own
HPC/Positron environment needs, before first use:
- `module load R` and `module load jags` on `PATH` (or `Rscript` directly on
  `PATH` — `scripts/_resolve_rscript.sh` tries both, in that order)
- R packages: `dplyr`, `readxl`, `writexl`, `ggplot2`, `ggtext`, `coda`,
  `igraph`, `netmeta`, `yaml`, `rjags`

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
   automatically rather than silently misreading them).
2. It loads/merges the data and runs a naming/route pooling-risk QA check
   automatically — no stop here, the results feed into the next step.
3. **One consolidated message** — endpoint, route, evidence tier, region,
   heterogeneity model, every naming/pooling flag, every study (with phase
   1/2 and no-placebo-arm studies always called out individually), and the
   plot's treatment list — each with a stated default. Reply with just what
   you want to change; everything else proceeds on the shown default/proposal.
4. It writes a YAML manifest recording every decision, builds the model
   input, fits the model via JAGS, runs convergence and network/consistency/
   DIC diagnostics (hard-stopping only on an actual `FAIL`), and renders the
   forest plot with a traceable footnote (source data, source program,
   contributing studies).
5. It writes a driver script next to the manifest that reproduces the whole
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
