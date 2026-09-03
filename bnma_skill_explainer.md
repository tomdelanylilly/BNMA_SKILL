# /cmh-ci — Guided Bayesian Network Meta-Analysis for Cardiometabolic Health Competitive Intelligence

**What this is for:** if you're pasting this file into a fresh Claude chat to
get started, read the whole thing first — it explains what the skill does,
why it exists, what a session looks like, and exactly what you'll have on
disk afterward.

- **Code / full design history:** https://github.com/EliLillyCo/BNMA_cmh_skill
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

`/cmh-ci` has two use cases, not one: just exploring what's in a PRD/QA
dataset (studies, compounds, phases, evidence tiers — a complete outcome on
its own, no analysis required), and, when that's the actual goal, running
the BNMA itself. It doesn't automate that analysis end-to-end. It **forces
every selection decision into the open** — naming/route conflicts, study
inclusion, treatment scope — and writes the result to a reviewable YAML
manifest instead of a commented-out vector, so a reviewer (or you, six
months later) can see exactly why each study is in the network.

## What a session actually looks like

Invoke it with `/cmh-ci` in Claude Code. It will walk you through, in order:

1. **Introduce and explain the available PRD dataset** — point it at an
   exact PRD file, or a folder (or nothing — it defaults to your project's
   own working directory), and it searches for PRD files specifically,
   lists every candidate it finds with modified dates, and waits for an
   explicit pick — it never guesses the newest or best-named match. (A
   newer, not-yet-promoted QA file is a later concern — step 4 — not this
   one; naming a QA file explicitly here still works, but the search itself
   only looks for PRD.) Once you've picked, it tells you what's actually in
   it — studies, compounds, phases, evidence tiers — before asking you to
   decide anything (it also runs the naming/pooling QA gate automatically
   here, mentioning the flag count — full resolution comes later). If
   you're just exploring, it stays conversational from here: no folders, no
   manifest, no naming-gate resolution demanded, until you say you want to
   move toward an actual run.
2. **Ask which studies you're interested in** — name specific studies (e.g.
   "ATTAIN-1 vs. SURMOUNT-4") and/or compounds/treatments up front if you
   already know what you want ("I need these 21 treatments"); either gets
   resolved first, and a study you name this way still shows up in step 3's
   full review with "include, per your request" as its stated reason —
   naming it doesn't skip the confirmation, it just sets the proposed
   answer. Then endpoint, route of administration (oral / injectable /
   both), evidence type (observed / prediction / both), and region — each a
   short question with a stated default, answered one at a time rather than
   bundled into one message.
3. **Create and review a subset of the PRD data based on those
   selections** — every distinct study in scope is listed, grouped so
   Phase 1/2 and prediction studies stand out, alongside every
   naming/pooling flag, in one grouped review message. You explicitly
   include or exclude each flagged study with a one-line reason. Nothing
   gets a default you didn't state.
4. **Ask whether additional, non-PRD data should be incorporated** — once
   your subset is chosen, it asks whether it's sufficient or whether you
   want to bring in something not yet in QA/PRD (a press release, a
   hand-digitized slide, a subset from another workbook).
5. **Convert and structure any additional data into the QA format** (only
   if step 4 said yes) — pasted rows, a file, or a subset of another
   workbook, mapped into the QA schema and shown for confirmation.
6. **Merge the supplemental data with the selected PRD subset** — new data
   defaults to a **temporary, project-only addition** — not written to the
   shared QA file unless you explicitly ask to promote it, since PRD only
   updates twice a year and most custom data is specific to one analysis.
   Loops back to step 4 until the (possibly enlarged) subset is confirmed
   sufficient.
7. **Confirm whether to proceed to a BNMA run** — your goal for this session
   might genuinely have been just reviewing the data or getting your own
   data into QA, and that's a complete outcome, not a shortfall. Only a
   "yes, let's run it" moves on to the next step — this is a distinct,
   later checkpoint from step 1's explore-or-run fork, since intent can
   become clear (or narrow) only after you've actually seen the data and
   made your selections.
8. **Generate the BNMA using the prepared dataset** — working folders (and
   an optional project CLAUDE.md) are proposed here, not before, so
   exploring or updating the data never drags you into project setup you
   didn't ask for; then the manifest is written and the BATMAN model-input
   structure is built.
9. **Collect modelling preferences** — heterogeneity (random- vs.
   fixed-effects) and effect type (placebo-adjusted vs. absolute), asked
   *after* step 8 has already built the real network structure, so the
   recommendation is stated directly (e.g. "this network is a full star,
   fixed-effects is recommended") instead of asked blind and corrected
   later.
10. **Produce analysis outputs and visualisations** — deterministic
    scripts, not model judgment, fit either the real production BNMA model
    (`model_random.txt` / `model_fixed.txt`, matching the actual CMH BNMA
    Shiny app's own specification) or the legacy hierarchical model, per
    the manifest's `model_type`; render the forest plot (every plotted arm
    superscript-marked observed (`ᵒ`) vs. projection (`ᵖ`), footnote listing
    every contributing study plus the exact source file path); and write a
    driver script — a small, directly re-runnable R script that reproduces
    the whole run from scratch by calling the skill's own scripts with this
    run's literal arguments baked in.

## What lands on disk when it's done

Two dated, paired folders, rooted under the QA tier (not wherever the PRD
file happened to be found — PRD is the curated, semi-annual read tier, QA
is the live working copy, so that's where a run's own work products
belong) — nothing hidden, nothing that requires re-deriving a decision
from a chat transcript:

```
<qa_root>/programs/YYYYMMDD_<run-name>/
  manifest.yaml            # every include/exclude decision, filters, reasons
  run_bnma_<run-name>.R    # driver script — reproduces the run standalone
  merged.rds               # cached: QA+PRD merge
  batman.rds               # cached: BATMAN-augmented model input
  arm_info.rds             # cached: per-arm metadata (compound, evidence_type)
  study_info.rds           # cached: study_ind <-> study_name lookup
  samples.rds              # cached: JAGS posterior samples (expensive, reused)

<qa_root>/output/shared/YYYYMMDD_<run-name>/
  forest_plot.png          # the deliverable, footnoted + evidence-marked
```

The manifest is the artifact worth reading if you want to know *why* a
result looks the way it does. The driver script is the artifact worth
running if you want to reproduce it later without Claude in the loop at all.

## Getting set up in a new project

1. Clone https://github.com/EliLillyCo/BNMA_cmh_skill (private repo — request
   access if you can't see it).
2. Copy the whole repo (it's a flat, skill-at-root layout — `SKILL.md` +
   `compound_registry.yaml`, everything else is embedded inline in
   `SKILL.md`'s appendices and materialized at runtime) into your own
   project's `.claude/skills/cmh-ci/` folder.
3. Make sure your R environment has `rjags`/JAGS available — the skill
   materializes its own `run_with_jags.sh` wrapper at runtime, which loads
   the `jags` environment module before invoking R; if your environment
   resolves JAGS differently, you'll need to adjust Appendix D's wrapper
   text in `SKILL.md` itself.
4. In Claude Code, invoke `/cmh-ci` and point it at your PRD file (or a
   folder to search for one) when asked — see step 1 above for how the
   search/pick works.

## What it deliberately does not do

- No fully automated pipeline — every selection decision is a forced,
  explicit step. If you want a script that just runs end-to-end with no
  questions, this isn't it, on purpose.
- No external grounding (ClinicalTrials.gov/INN lookups) for the naming
  check — string-similarity + same-study disconfirmation + a persisted
  decision registry only.

See [DESIGN.md](DESIGN.md) for the full history of why each of these
decisions was made the way it was, including the specific incidents and
reference scripts that shaped them.
