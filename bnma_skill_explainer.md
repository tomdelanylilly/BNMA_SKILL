# /bnma — Guided Bayesian Network Meta-Analysis for the Obesity Landscape

**What this is for:** if you're pasting this file into a fresh Claude chat to
get started, read the whole thing first — it explains what the skill does,
why it exists, what a session looks like, and exactly what you'll have on
disk afterward.

- **Code / full design history:** https://github.com/tomdelanylilly/BNMA_SKILL
- **One-page visual overview (open in a browser):** [docs/bnma_skill_overview_slide.html](docs/bnma_skill_overview_slide.html)
- **Full design rationale (problem statement, architecture, every decision):** [DESIGN.md](DESIGN.md)

---

## The problem this solves

Obesity-landscape BNMAs (GLP-1 / GIP / amylin / dual- and triple-agonist
weight-loss comparisons) were being run from hand-edited R scripts with a
hardcoded `!study %in% c(...)` exclusion vector — often with commented-out
lines and no record of *why* a study was in or out. Two real incidents drove
this skill's design:

1. **A silent inclusion skewed a result.** A low-dose Phase 2 study entered a
   semaglutide analysis with no one deciding to include it — nobody noticed
   until the pooled estimate looked wrong.
2. **Naming/pooling drift broke scripts silently.** A compound spelling
   changed (or an oral- and injectable-route arm shared one treatment label)
   and two rows silently collapsed into one arm, or a study quietly stopped
   matching an exclusion list.

`/bnma` doesn't automate the analysis end-to-end. It **forces every
selection decision into the open** — naming/route conflicts, study
inclusion, treatment scope — and writes the result to a reviewable YAML
manifest instead of a commented-out vector, so a reviewer (or you, six
months later) can see exactly why each study is in the network.

## What a session actually looks like

Invoke it with `/bnma` in Claude Code. It will walk you through, in order:

1. **Introduce the data** — you point it at a PRD file/folder (and a QA
   path if there's newer unpromoted data), and it tells you what's actually
   in it — studies, compounds, phases, evidence tiers — before asking you to
   decide anything. If you're just exploring, it stays conversational from
   here: no folders, no manifest, no naming-gate resolution demanded, until
   you say you want to move toward an actual run.
2. **Naming/pooling QA gate** — it flags near-duplicate compound spellings
   and oral/injectable route-pooling risk, and makes you resolve every flag
   explicitly before moving on. Resolutions are persisted so the same pair
   is never re-flagged.
3. **Scope questions, asked one at a time** — endpoint, route of
   administration (oral / injectable / both), evidence type (observed /
   prediction / both), region, heterogeneity model, and effect type
   (placebo-adjusted vs. absolute) — each a short question with a stated
   default, answered one at a time rather than bundled into one message.
   (If you already named specific treatments up front — "I need these 21
   treatments" — that's resolved separately, before these questions.)
4. **Study confirmation** — every distinct study in scope is listed, grouped so
   Phase 1/2 and prediction studies stand out, alongside every naming/pooling
   flag, in one grouped review message. You explicitly include or exclude
   each flagged study with a one-line reason. Nothing gets a default you
   didn't state.
5. **Confirm the subset, optionally add custom data, propose folders** —
   once your subset is chosen, it asks whether it's sufficient or whether
   you want to bring in something not yet in QA/PRD (a press release, a
   hand-digitized slide, a subset from another workbook). New data defaults
   to a **temporary, project-only addition** — not written to the shared QA
   file unless you explicitly ask to promote it, since PRD only updates
   twice a year and most custom data is specific to one analysis. This is
   also where working folders (and an optional project CLAUDE.md) are
   proposed — not before, so exploring the data never drags you into
   project setup you didn't ask for.
6. **Manifest written** — every decision above becomes a YAML file. This is
   the audit trail; nothing downstream is inferred from a conversation you'd
   have to re-read.
7. **BATMAN build + JAGS fit** — deterministic scripts, not model judgment.
   Fits either the real production BNMA model (`model_random.txt` /
   `model_fixed.txt`, matching the actual CMH BNMA Shiny app's own
   specification) or the legacy hierarchical model, per the manifest's
   `model_type`.
8. **Forest plot + footnote** — every plotted arm is superscript-marked
   observed (`ᵒ`) vs. projection (`ᵖ`), and the footnote lists every
   contributing study plus the exact source file path.
9. **Driver script** — a small, directly re-runnable R script that
   reproduces the whole run from scratch by calling the skill's own scripts
   with this run's literal arguments baked in.

## What lands on disk when it's done

Two dated, paired folders — nothing hidden, nothing that requires re-deriving
a decision from a chat transcript:

```
programs/YYYYMMDD_<run-name>/
  manifest.yaml            # every include/exclude decision, filters, reasons
  run_bnma_<run-name>.R    # driver script — reproduces the run standalone
  merged.rds               # cached: QA+PRD merge
  batman.rds               # cached: BATMAN-augmented model input
  arm_info.rds             # cached: per-arm metadata (compound, evidence_type)
  study_info.rds           # cached: study_ind <-> study_name lookup
  samples.rds              # cached: JAGS posterior samples (expensive, reused)

output/shared/YYYYMMDD_<run-name>/
  forest_plot.png          # the deliverable, footnoted + evidence-marked
```

The manifest is the artifact worth reading if you want to know *why* a
result looks the way it does. The driver script is the artifact worth
running if you want to reproduce it later without Claude in the loop at all.

## Getting set up in a new project

1. Clone https://github.com/tomdelanylilly/BNMA_SKILL (private repo — request
   access if you can't see it).
2. Copy `.claude/skills/bnma/` into your own project's `.claude/skills/`
   folder.
3. Make sure your R environment has `rjags`/JAGS available — the skill's
   `scripts/run_with_jags.sh` wrapper loads the `jags` environment module
   before invoking R; adjust that wrapper if your environment resolves JAGS
   differently.
4. In Claude Code, invoke `/bnma` and give it your PRD (and QA, if
   applicable) file path when asked.

## What it deliberately does not do

- No fully automated pipeline — every selection decision is a forced,
  explicit step. If you want a script that just runs end-to-end with no
  questions, this isn't it, on purpose.
- No absolute-effect view for the real production model types
  (`rand_effect`/`fixed_effect`) — confirmed against the real production
  tool's own source that it doesn't have one either, since its
  non-hierarchical model has no single pooled baseline to compute one from.
  `effect_type: absolute` only works with the legacy `model_simultaneous`
  model.
- No external grounding (ClinicalTrials.gov/INN lookups) for the naming
  check — string-similarity + same-study disconfirmation + a persisted
  decision registry only.

See [DESIGN.md](DESIGN.md) for the full history of why each of these
decisions was made the way it was, including the specific incidents and
reference scripts that shaped them.
