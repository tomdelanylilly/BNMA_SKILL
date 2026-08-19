# BNMA_SKILL

A Claude Code skill (`/bnma`) for running obesity-landscape Bayesian network
meta-analyses with forced study-selection confirmation and a naming/route
pooling-risk QA gate, instead of hardcoded, hand-edited study lists.

See [DESIGN.md](DESIGN.md) for the full design doc — problem statement,
current-state findings, and the skill architecture.

## Install (Claude Code plugin)

This repo is both the plugin source and its own marketplace. One-time setup:

```
/plugin marketplace add tomdelanylilly/BNMA_SKILL
/plugin install bnma@bnma-marketplace
```

`/bnma` is then available in any Claude Code session. This plugin does
**not** bundle R, JAGS, or any R package — every teammate's own HPC/Positron
environment must already have:
- `module load R` and `module load jags` on `PATH` (or `Rscript` directly on
  `PATH` — `scripts/_resolve_rscript.sh` tries both, in that order)
- R packages: `dplyr`, `readxl`, `writexl`, `ggplot2`, `ggtext`, `coda`,
  `igraph`, `netmeta`, `yaml`, `rjags`

### Updating

```
/plugin marketplace update bnma-marketplace
/reload-plugins
```

Third-party marketplaces (this one included) don't auto-update, so both
steps are needed to pick up a new version after a `git push` to this repo.

### Repo layout

- `.claude-plugin/marketplace.json` — the marketplace manifest (this repo
  lists itself).
- `plugins/bnma/.claude-plugin/plugin.json` — the plugin manifest. **Bump
  `version` on every meaningful change** — that's the only signal a
  teammate's `/plugin marketplace update` has that anything changed.
- `plugins/bnma/skills/bnma/SKILL.md` — the skill itself.
- `plugins/bnma/skills/bnma/scripts/` — the deterministic R steps (data
  load/merge, naming/pooling QA gate, BATMAN augmentation, JAGS fit, forest
  plot). `run_with_jags.sh` wraps the JAGS-fitting step so the `jags`
  environment module gets loaded first (`rjags` fails to link without it).
- `plugins/bnma/skills/bnma/compound_registry.yaml` — persisted naming-QA
  decisions, so a resolved compound-name pair is never re-flagged.
- `plugins/bnma/skills/bnma/tests/` — a synthetic fixture with deliberately
  seeded edge cases (near-duplicate compound names, a route-pooling
  collision, a Phase 2 study, a study with no placebo arm, a closed loop for
  the consistency/DIC gate) and the manifest used to smoke-test the full
  pipeline end-to-end, including an actual JAGS fit.

## Status

Built and smoke-tested end-to-end against the synthetic fixture (steps 1–7,
including a real JAGS fit and forest plot render), and run against a real
dataset (an ADA oral-compounds landscape NMA) — which caught and fixed a
genuine star-network CI-inflation bug in `model_simultaneous.txt` (see
`model_simultaneous_fixed.txt` and its own header comment).