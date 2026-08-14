# BNMA_SKILL

A Claude Code skill (`/bnma`) for running obesity-landscape Bayesian network
meta-analyses with forced study-selection confirmation and a naming/route
pooling-risk QA gate, instead of hardcoded, hand-edited study lists.

See [DESIGN.md](DESIGN.md) for the full design doc — problem statement,
current-state findings, and the skill architecture.

## Layout

- `.claude/skills/bnma/SKILL.md` — the skill itself. Drop the
  `.claude/skills/bnma/` folder into any project to make `/bnma` available.
- `.claude/skills/bnma/scripts/` — the deterministic R steps (data load/merge,
  naming/pooling QA gate, BATMAN augmentation, JAGS fit, forest plot).
  `run_with_jags.sh` wraps the JAGS-fitting step so the `jags` environment
  module gets loaded first (`rjags` fails to link without it).
- `.claude/skills/bnma/compound_registry.yaml` — persisted naming-QA
  decisions, so a resolved compound-name pair is never re-flagged.
- `.claude/skills/bnma/tests/` — a synthetic fixture with deliberately seeded
  edge cases (near-duplicate compound names, a route-pooling collision, a
  Phase 2 study, a study with no placebo arm) and the manifest used to
  smoke-test the full pipeline end-to-end, including an actual JAGS fit.

## Status

Built and smoke-tested end-to-end against the synthetic fixture (steps 1–6,
including a real JAGS fit and forest plot render). Not yet run against real
QA/PRD data.