# AI_USAGE.md — Log of AI-Assisted Work (Workflow Step 2)

> The brief requires: **"Use AI tools to inspect, clean, and preprocess the
> dataset."** This file is the evidence. It is **append-only**. Every time an
> AI tool (Claude, a coding agent, ChatGPT, Copilot…) inspects the data,
> flags a problem, proposes a cleaning or preprocessing rule, or writes or
> reviews code, add an entry. Summarise it in the report's Data section and
> include the full log as an appendix.

**Rules**
- Be honest. Record suggestions you rejected as well as ones you accepted.
- The owner (student) makes every final decision. The AI only proposes.
- AI must never supply data values or results, only analysis, code and
  suggestions.
- Link each entry to the code it produced and to any `DECISIONS.md` entry.

---

## Summary table (keep updated)

| ID | Date | Stage | Tool | What the AI did | Owner decision | Code / output |
|---|---|---|---|---|---|---|
| AI-001 | 2026-10-18 | Planning | Claude (claude.ai) | Proposed project, features, models, metrics, query cuts; drafted project docs | Accepted (D-001–D-016) | This doc pack |
| AI-002 | 2026-10-18 | Acquisition (code) | Claude Code (Claude Opus 5.5) | Tested the SkyServer web API, wrote the setup, utility and download scripts | Accepted | `R/00_setup.R`, `R/utils_*.R`, `R/01_acquire.R` |
| AI-003 | 2026-10-18 | Inspection | Claude Code (Claude Opus 5.5) | Checked structure, NA, sentinels, duplicates, ranges, errors, colour outliers; flagged 2 very blue galaxies | Noted | `outputs/logs/02_inspection.txt` |
| AI-004 | 2026-10-18 | Cleaning | Claude Code (Claude Opus 5.5) | Implemented rules 1–9; suggested flag-only for the 2 blue galaxies | Rejected the suggestion: removed them as planned | `R/02_inspect_clean.R`, `T02_cleaning_log.csv` |
| AI-005 | 2026-10-18 | Preprocessing | Claude Code (Claude Opus 5.5) | Derived colours, seeded sample to 100, column order | Accepted (scaling deferred to caret, D-010) | `R/02_inspect_clean.R` |
| AI-006 | 2026-10-18 | EDA (code) | Claude Code (Claude Opus 5.5) | Wrote the EDA script; checked every figure visually; captions generated from the data | Accepted (committed) | `R/03_eda.R`, T01, F01–F06, F20 |
| AI-007 | 2026-10-18 | Split (code) | Claude Code (Claude Opus 5.5) | Wrote the stratified 80/20 split with leakage assertions and F07 + KS test | Accepted (committed) | `R/04_split.R`, F07 |
| AI-008 | 2026-10-18 | Modelling (code) | Claude Code (Claude Opus 5.5) | Wrote training with shared CV folds, T03, T04, learning curves, F08–F13 | Accepted (committed) | `R/05_train.R` |
| AI-009 | 2026-10-18 | Evaluation (code) | Claude Code (Claude Opus 5.5) | Wrote test evaluation with bootstrap CIs, T05, F14–F17; diagnosed the CV/test gap | Pending owner review | `R/06_evaluate.R` |

---

## Entry template

```markdown
### AI-0xx — <short title>
- **Date:** YYYY-MM-DD
- **Stage:** Inspection | Cleaning | Preprocessing | Modelling | Code review | Report
- **Tool / model:** e.g. Claude Code (Claude Opus), ChatGPT, Copilot
- **Input given to AI:** what it saw (e.g. `str()`/`summary()` output,
  first 10 rows, NA counts). Never paste more data than needed.
- **Prompt (short):** "…"
- **AI output / suggestion:** what it found or proposed
- **Owner decision:** Accepted / Modified / Rejected, and why
- **Resulting code:** file + line range or function name
- **Effect on data:** rows before → after (from T02), columns added
- **Linked decision:** D-0xx (if any)
```

---

## Entries

### AI-001 — Project planning and documentation
- **Date:** 2026-10-18
- **Stage:** Planning
- **Tool / model:** Claude (claude.ai)
- **Input given to AI:** Unit 4 brief (PDF), the chosen topic "Photometric
  redshift prediction using SDSS data".
- **AI output / suggestion:** a SkyServer SQL query with quality cuts; colour
  features (u−g, g−r, r−i, i−z) + r magnitude; models (baseline, LM, kNN, RF,
  SVR, optional XGBoost); photo-z metrics (σ_NMAD, η); repository structure,
  figure list and these guidance documents.
- **Owner decision:** Accepted, pending instructor confirmation of topic (D-001).
- **Resulting code:** none yet (`data/sql/sdss_query.sql`, docs).
- **Linked decision:** D-001 to D-016.

### AI-002 — Data acquisition scripts
- **Date:** 2026-10-18
- **Stage:** Acquisition (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the project docs and `data/sql/sdss_query.sql`. No
  data values were given.
- **Prompt (short):** "Write the data collection scripts."
- **AI output / suggestion:**
  - Tested the SkyServer SqlSearch web service with throw-away `TOP 3` and
    `TOP 5` queries, outside the repository. Findings: DR18 accepts the
    project query unchanged and returns all 15 expected columns in about 15 s.
    The response starts with a `#Table1` line before the CSV header. `objid`
    values have 19 digits, so they must be read as text. SQL errors come back
    as HTTP 500 with a JSON `ErrorMessage`.
  - Wrote `R/00_setup.R` (packages, `SEED`, paths, data contract),
    `R/utils_metrics.R`, `R/utils_plot.R` and `R/01_acquire.R`. The
    acquisition script downloads via the web service (DR18, then DR17), strips
    `#Table1`, checks the header and row count, writes `ACQUISITION.md` with an
    MD5 checksum, and on later runs refuses to download again and stops if
    the raw file's MD5 has changed (D-015).
  - Added a `.here` file. The git repository root is the parent folder
    (`Kavya-jini/`), so without it `here::here()` would resolve paths
    there instead of inside `sdss-photoz-r/`.
- **Owner decision:** Accepted. The owner reviewed the scripts and committed
  them.
- **Resulting code:** files above
- **Effect on data:** `R/01_acquire.R` downloaded 120 rows × 15 columns from
  DR18 on 2026-10-18 (see `data/raw/ACQUISITION.md` for the MD5). A second run
  skipped the download and confirmed the MD5.
- **Linked decision:** D-003, D-004, D-005, D-015

### AI-003 — Inspection of the raw data
- **Date:** 2026-10-18
- **Stage:** Inspection
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** output of `str()`, `summary()`, NA, sentinel and
  duplicate counts, colour summaries and MAD outlier counts for
  `data/raw/sdss_raw.csv`. The full output is saved in
  `outputs/logs/02_inspection.txt`.
- **Prompt (short):** "Inspect the raw data and flag anything the cleaning
  rules must handle."
- **AI output / suggestion:**
  - 120 rows × 15 columns. No NA, no sentinel values (±9999), no duplicate
    `objid`, no fully duplicated rows, and no repeated sky positions.
  - All `objid` values have 19 digits and are intact as text.
  - All magnitudes lie well inside [10, 30] and redshift inside (0, 1). All
    magnitude errors are below the query's 0.2 cut.
  - The redshift range (about 0.025–0.22) is narrower than D-005 expected.
    At these redshifts the 4000 Å break stays inside the g band, which matters
    for the physics discussion.
  - With the 5·MAD rule, 2 galaxies are flagged, both on `i_z`:
    `1237665548892962975` (z = 0.031) and `1237657769630695800` (z = 0.050).
    Both are blue in **all four** colours, not just one. The first has
    typical photometric errors; the second has errors about 2–4× the sample
    median but well under the 0.2 cut. The AI judged them to be real blue
    star-forming galaxies rather than bad photometry, since bad photometry
    usually shifts a single colour.
- **Owner decision:** Noted. See AI-004 for how the outliers were handled.
- **Resulting code:** inspection block (step 2) of `R/02_inspect_clean.R`
- **Effect on data:** none (inspection only)
- **Linked decision:** D-012

### AI-004 — Cleaning rules
- **Date:** 2026-10-18
- **Stage:** Cleaning
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the AI-003 findings and the rules in README §6.
- **Prompt (short):** "Implement the cleaning pipeline; ask before changing
  any planned rule."
- **AI output / suggestion:** implemented rules 1–9 from README §6, with one
  row per rule in T02 (including rules that remove nothing). For rule 6 it
  suggested **flagging the two blue galaxies without removing them**: they look
  physically real, and removing them leaves the model with almost no blue
  galaxies to learn from.
- **Owner decision:** **Rejected the flag-only suggestion.** Rule 6 was
  applied as planned and both galaxies were removed. Every other rule was
  accepted as written.
- **Resulting code:** `R/02_inspect_clean.R`, steps 3–6
- **Effect on data (from T02):** 120 → 120 (rules 3–5 removed nothing) →
  118 (rule 6 removed 2)
- **Linked decision:** D-012
- **Note for the report:** after this cut the sample has no very blue
  galaxies, so the models are not tested on them. Mention this in
  Limitations.

### AI-005 — Preprocessing
- **Date:** 2026-10-18
- **Stage:** Preprocessing
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the cleaned 118 rows (no data values beyond what
  AI-003 lists).
- **Prompt (short):** "Derive features and produce the 100-row analysis set."
- **AI output / suggestion:** derive the colours `u_g, g_r, r_i, i_z`; sample
  exactly 100 rows with `set.seed(42)`; sort by `objid` and fix the column
  order; assert 30 ≤ n ≤ 100, no NA and unique `objid`. Centring and scaling
  are **not** done here. They run inside `caret::train()` on each training
  fold, so the test set cannot leak into them.
- **Owner decision:** Accepted
- **Resulting code:** `R/02_inspect_clean.R`, steps 7–9
- **Effect on data (from T02):** 118 → 100 rows (random sample); 4 colour
  columns added (19 columns in total). Verified: colours equal magnitude
  differences, values match the raw file, and a re-run gives a
  byte-identical `sdss_clean.csv`.
- **Linked decision:** D-003, D-006, D-010, D-014

### AI-006 — Exploratory data analysis
- **Date:** 2026-10-18
- **Stage:** EDA (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** `data/processed/sdss_clean.csv` (via the script) and
  the figure specification in `docs/REPORT_GUIDE.md`.
- **Prompt (short):** "Write and run R/03_eda.R for T01 and figures F01–F06
  and F20."
- **AI output / suggestion:**
  - Wrote `R/03_eda.R`. It is descriptive only: no model is fitted and nothing
    is selected from these plots. It produces T01 and F01–F06 and F20 as PNG
    (300 dpi) and PDF, plus draft captions whose numbers and claims are
    computed from the data.
  - Added the SDSS filter constants (`SDSS_FILTERS`, `BREAK_REST`) to
    `00_setup.R` and the band colours and colour labels to `utils_plot.R`.
  - Built F05 with plain ggplot2 instead of `ggcorrplot`, which avoids a
    package dependency.
  - Viewed every figure and fixed two layout issues: the F20 band labels
    overlapped the break line, and the F06 title showed one decimal place.
  - Physics observation for step 7: over this sample's redshift range, the
    break stays inside the g band (F20).
- **Owner decision:** Accepted. The owner committed it.
- **Resulting code:** `R/03_eda.R`, `R/00_setup.R`, `R/utils_plot.R`
- **Effect on data:** none (read-only)
- **Linked decision:** D-006

### AI-007 — Train/test split
- **Date:** 2026-10-18
- **Stage:** Split (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** `data/processed/sdss_clean.csv` (via the script).
- **Prompt (short):** "Write and run R/04_split.R (80/20 stratified split,
  F07 with KS test)."
- **AI output / suggestion:** wrote `R/04_split.R`. It splits the data with
  `caret::createDataPartition(redshift, p = 0.8)` and seed 42, then asserts
  80/20 sizes, no `objid` in both sets, and that every galaxy is used. It
  writes `train.csv` and `test.csv` and makes F07 with a two-sample KS test.
  Added `caret` to `renv.lock`. A re-run gives byte-identical files.
- **Observation for the report:** the lowest-redshift galaxy of the sample
  went to the test set, below the training minimum. At that point the models
  have to extrapolate slightly (see the split summary printed by the script).
- **Owner decision:** Accepted. The owner committed it.
- **Resulting code:** `R/04_split.R`
- **Effect on data:** 100 → 80 train + 20 test rows
- **Linked decision:** D-009, D-014

### AI-008 — Model training and tuning
- **Date:** 2026-10-18
- **Stage:** Modelling (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** `train.csv` (via the script). `test.csv` is used
  only to score the learning-curve refits after tuning.
- **Prompt (short):** "Write and run R/05_train.R (baseline, LM, kNN, RF, SVR
  with shared repeated-CV folds, T03, T04, F08–F13)."
- **AI output / suggestion:**
  - One fixed set of 25 resamples (`createMultiFolds`, 5-fold × 5, seed 42)
    is passed to every model through `trainControl(index = ...)`, so all
    models are compared on identical folds.
  - The baseline uses caret's built-in `"null"` model (predicts the training
    mean), so it goes through the same folds as the learners.
  - A custom `summaryFunction` scores CV with the same RMSE, MAE and
    R² = 1 − SS_res/SS_tot definitions as the test evaluation. caret's
    default R² is the squared correlation, which is undefined for the
    constant baseline.
  - Grids exactly as in D-008/D-010. XGBoost (optional M5) was not added.
  - Learning curves: 7 sizes × 20 repeats × 5 models = 700 refits with
    frozen hyperparameters (D-016).
  - Checked every figure visually. The F11 labels were unreadable on dark
    cells, so they now switch to white.
  - Re-running gives identical T03, T04 and learning-curve tables. Runtime is
    about 40 s.
- **Observations for the report (no modelling choice was changed):**
  - SVR's best σ = 0.01 is the smallest value in the grid (a smooth, nearly
    linear kernel), and RF's best mtry = 5 uses all features. Both sit at the
    edge of their grids.
  - In the learning curves (F12), test-set RMSE at n = 80 is clearly higher
    than CV RMSE for the linear and SVR models. Phase 7's residual plots
    should show whether one or two test galaxies cause this.
- **Owner decision:** Accepted. The owner committed it.
- **Resulting code:** `R/05_train.R`; `randomForest` and `kernlab` added
  to `renv.lock`
- **Effect on data:** none (models saved to `outputs/models/`, git-ignored)
- **Linked decision:** D-008, D-010, D-014, D-016

### AI-009 — Test-set evaluation
- **Date:** 2026-10-18
- **Stage:** Evaluation (code)
- **Tool / model:** Claude Code (Claude Opus 5.5)
- **Input given to AI:** the saved models and `test.csv` (via the script).
- **Prompt (short):** "Write and run R/06_evaluate.R (test metrics with
  bootstrap CIs, T05, test_predictions.csv, F14–F17)."
- **AI output / suggestion:**
  - Wrote `R/06_evaluate.R`. It predicts with the saved models unchanged,
    computes RMSE, MAE, R², bias, σ_NMAD and η (`utils_metrics.R`) and
    95% percentile bootstrap CIs (2000 resamples, seed 42) for RMSE, R² and
    σ_NMAD. It writes T05 and `test_predictions.csv` and draws F14–F17. A
    re-run gives byte-identical tables.
  - Checked every figure visually and fixed label overlaps in F14 and F17.
  - Diagnosed why test RMSE is higher than CV RMSE for the linear model and
    SVR, using the largest-|Δz| list the script prints and a one-off check of
    feature ranges (not part of the pipeline). One test galaxy
    (`1237661950779588703`) has a red u − g but g − r, r − i and i − z at
    the blue edge of the training set, with r − i below the training minimum.
    The linear model and the near-linear SVR extrapolate and predict a
    **negative** redshift for it. Random-forest predictions are averages of
    training redshifts, so they cannot leave the training range, which is
    why RF has the lowest test RMSE. In total, 4 of the 20 test galaxies have
    at least one colour outside the training range.
  - All learners predict the lowest-z test galaxy too high: no training
    galaxy is that close, so predictions are pulled towards the mean (F15).
- **Owner decision:** _pending review_. No modelling choice was changed
  after seeing the test results (AGENTS.md R5).
- **Notes for the report:** the 95% CIs overlap heavily, so with only 20 test
  galaxies no model is clearly better than another. The CV ranking
  (SVR ≈ LM > RF > k-NN) differs from the test ranking (RF best). Report both
  and explain the extrapolation effect. Negative z_phot is unphysical, and
  that belongs in Limitations.
- **Resulting code:** `R/06_evaluate.R`
- **Effect on data:** none (read-only)
- **Linked decision:** D-011, D-014
