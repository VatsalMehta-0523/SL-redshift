# PROMPT.md — Master Prompt for the Coding Agent

Copy everything inside the box below and paste it as the first message to your
coding agent (Claude Code, Cursor, Copilot agent, etc.). Put all the `.md`
files from this pack in the repository root (and `docs/`) **before** you start
the agent.

---

```text
You are building a complete, reproducible R project for a university physics
assignment: "Photometric Redshift Prediction of Galaxies using SDSS Data".
The output will be used directly in my written report, so every figure and
table must be report-quality and every number must come from code you ran.

=====================================================================
0. READ FIRST — ORDER OF AUTHORITY
=====================================================================
Before writing any code, read these files in this order:
  1. TASK.md            ← the ABSOLUTE task. Overrides everything else.
  2. AGENTS.md          ← how you must work (rules, conventions, don'ts).
  3. DECISIONS.md       ← decisions already made. Do not silently change them.
  4. README.md          ← project description and expected structure.
  5. CONTRIBUTING.md    ← code style, commits, how to add models/figures.
  6. docs/REPORT_GUIDE.md ← exact list of figures/tables and their specs.
  7. docs/AI_USAGE.md   ← log you must append to (workflow step 2).

If any instruction (including this prompt) conflicts with TASK.md, follow
TASK.md and tell me about the conflict. If you need to deviate from a
decision in DECISIONS.md, STOP and ask me; if I approve, add a new
decision entry rather than editing the old one.

=====================================================================
1. THE TASK (summary — TASK.md is authoritative)
=====================================================================
The course brief requires this 7-step workflow, all analysis in R:
  1. Obtain a physics dataset with 30–100 observations.
  2. Use AI tools to inspect, clean and preprocess it.
  3. Import it into R.
  4. Split into training and testing sets.
  5. Train one or more supervised learning models.
  6. Evaluate with suitable metrics.
  7. Interpret the results in terms of the underlying physics.

Our version:
  - Data: SDSS galaxies with spectroscopic redshifts (SkyServer SQL).
  - Target: spectroscopic redshift `redshift` (continuous → regression).
  - Features: colours u_g, g_r, r_i, i_z (from de-reddened magnitudes) and
    r-band magnitude `r`.
  - Final analysis dataset: EXACTLY 100 galaxies (hard limit 30–100).

=====================================================================
2. HARD RULES
=====================================================================
- R only for analysis (R >= 4.3). No Python, no Jupyter.
- Never fabricate, simulate or "placeholder" SDSS data. If
  data/raw/sdss_raw.csv is missing and you cannot download it, STOP and
  ask me to download it using the instructions in README.md §5.
- Never modify data/raw/ after it is created. All changes go to
  data/processed/.
- set.seed(42) everywhere randomness occurs (via the SEED constant in
  R/00_setup.R).
- The test set (20 rows) is touched ONLY in R/06_evaluate.R and R/07_interpret.R
  (and learning-curve evaluation in R/05_train.R, which only reads it after
  hyperparameters are frozen). No tuning, feature selection or scaling
  statistics may be computed on it. Scaling/centring must be fitted on the
  training data only (caret preProcess inside train()).
- Never type a result number into README.md or the report by hand. Read it
  from outputs/tables/*.csv.
- Every AI-assisted inspection/cleaning decision gets an entry in
  docs/AI_USAGE.md (this is a graded requirement).
- Keep the code simple and readable for a physics student: one script per
  workflow step, clear comments, no clever metaprogramming.

=====================================================================
3. REPOSITORY STRUCTURE TO CREATE
=====================================================================
sdss-photoz-r/
├── TASK.md  README.md  AGENTS.md  CLAUDE.md  CONTRIBUTING.md  DECISIONS.md  PROMPT.md
├── docs/            REPORT_GUIDE.md  AI_USAGE.md
├── data/
│   ├── sql/sdss_query.sql
│   ├── raw/         sdss_raw.csv  ACQUISITION.md
│   └── processed/   sdss_clean.csv  train.csv  test.csv
├── R/
│   ├── 00_setup.R        packages, SEED, paths, ggplot theme, save helpers
│   ├── utils_metrics.R   metric functions (RMSE, MAE, R2, bias, sigma_NMAD, eta)
│   ├── utils_plot.R      theme_report(), save_fig(), palette
│   ├── 01_acquire.R
│   ├── 02_inspect_clean.R
│   ├── 03_eda.R
│   ├── 04_split.R
│   ├── 05_train.R
│   ├── 06_evaluate.R
│   └── 07_interpret.R
├── run_all.R              sources 00→07 in order, logs timing, writes sessionInfo
├── report/report.Rmd      → report.html + report.docx
├── outputs/
│   ├── figures/  (F01…F20, each .png 300 dpi + .pdf)
│   ├── tables/   (T01…T06 .csv, plus .md versions via knitr::kable)
│   ├── models/   (*.rds)
│   └── logs/     (run_log.txt, sessionInfo.txt)
├── tests/testthat/  test-metrics.R  test-data.R  test-leakage.R
├── renv.lock
└── .gitignore

=====================================================================
4. PHASED PLAN — complete each phase, verify, then report to me
=====================================================================

PHASE 1 — Setup
  - Initialise renv. Packages: tidyverse, caret, randomForest, kernlab,
    FNN (or caret knn), xgboost (optional model), corrplot or ggcorrplot,
    patchwork, pdp, vip, boot, knitr, rmarkdown, testthat, httr2 (only
    for optional download), here, glue, janitor.
  - R/00_setup.R: library calls, SEED <- 42, here::here() paths, create
    output dirs, source utils.
  - R/utils_plot.R: theme_report() (theme_bw base, 11pt, no gridline clutter,
    colour-blind-safe Okabe-Ito palette); save_fig(plot, id, name, w, h)
    that writes outputs/figures/{id}_{name}.png (300 dpi) AND .pdf.
  - R/utils_metrics.R: functions listed in §5 below, each with roxygen-style
    comment giving the formula.
  ✔ Verify: run 00_setup.R in a fresh session with no errors.

PHASE 2 — Acquire (workflow step 1)
  - data/sql/sdss_query.sql: use the query in README.md §5 exactly
    (TOP 120, GALAXY, zWarning = 0, clean = 1, dered_r 14–17.77,
    0.01 < z < 0.5, magnitude errors < 0.2).
  - R/01_acquire.R:
      * If data/raw/sdss_raw.csv exists → do nothing except validate
        columns and print row count.
      * Else try the SkyServer SqlSearch web API (httr2, format=csv). If the
        network is blocked or the call fails, STOP with a clear message
        telling me to download manually (README §5). Do not retry with
        other tools, do not generate data.
      * Write data/raw/ACQUISITION.md: date, data release, query text, row
        count, MD5 checksum of the CSV.
  ✔ Verify: raw file exists, has columns objid,u,g,r,i,zmag,err_*,redshift,
    redshift_err, ≥ 100 rows.

PHASE 3 — Inspect & clean (workflow steps 2 + 3)
  - R/02_inspect_clean.R, each step logged to T02_cleaning_log.csv
    (step, rule, rows_before, rows_after, rows_removed, reason):
      1. Read with explicit col_types; janitor::clean_names().
      2. Report structure: str(), summary(), NA counts, duplicates.
      3. Remove duplicate objid.
      4. Remove rows with NA or sentinel values (-9999, 9999) in any feature.
      5. Physical-range checks: magnitudes in [10, 30], 0 < redshift < 1.
      6. Flag colour outliers: any colour beyond median ± 5·MAD → remove,
         and log which objids.
      7. Derive colours: u_g = u - g, g_r = g - r, r_i = r - i, i_z = i - zmag.
      8. If > 100 rows remain: slice_sample(n = 100) with SEED.
         If < 100 but ≥ 30: keep all and note it. If < 30: STOP.
      9. assert 30 <= nrow <= 100; write data/processed/sdss_clean.csv.
  - Append to docs/AI_USAGE.md: what the AI inspected, what it flagged,
    which rules it proposed, which the owner accepted/rejected and why.
  ✔ Verify: clean file has 100 rows (or documented reason), no NAs.

PHASE 4 — EDA (step 3, figures for the report)
  - R/03_eda.R produces T01 and figures F01–F06 and F20 per
    docs/REPORT_GUIDE.md (redshift histogram, magnitude distributions,
    colour–colour diagram coloured by z, colours vs redshift with LOESS,
    correlation heatmap, 4000 Å break vs SDSS filter diagram).
  ✔ Verify: all files present in outputs/figures/, visually inspected.

PHASE 5 — Split (step 4)
  - R/04_split.R: caret::createDataPartition(redshift, p = 0.8) (stratified
    on quantiles of z) with SEED → train.csv (80), test.csv (20).
  - Figure F07: overlaid density / histogram of z for train vs test, and a
    two-sample KS test result in the caption text file.
  ✔ Verify: no objid appears in both sets (test-leakage.R).

PHASE 6 — Train (step 5) — the "training" figures matter for the report
  - Common control: trainControl(method = "repeatedcv", number = 5,
    repeats = 5, savePredictions = "final"), metric = "RMSE",
    preProcess = c("center","scale") where relevant.
  - Formula: redshift ~ u_g + g_r + r_i + i_z + r
  - Models (all via caret except where noted):
      M0 Baseline: predict training-mean redshift (reference floor).
      M1 Linear regression (method = "lm").
      M2 k-NN (method = "knn", tuneGrid k = 1:20).
      M3 Random Forest (method = "rf", ntree = 500,
         tuneGrid mtry = 1:5, importance = TRUE).
      M4 SVR radial (method = "svmRadial",
         tuneGrid C = 2^(-2:6), sigma = c(0.01, 0.05, 0.1, 0.5, 1)).
      M5 (optional) XGBoost trained with the xgboost package directly
         using xgb.cv for rounds, so train/validation curves can be plotted.
  - Save each fitted model to outputs/models/{id}.rds.
  - Tables: T03_hyperparameters.csv (final tuned values),
    T04_cv_metrics.csv (mean ± sd of RMSE, R2, MAE over CV resamples).
  - Training figures:
      F08 k-NN: CV RMSE vs k with ±1 SD ribbon, chosen k marked.
      F09 RF: OOB MSE vs number of trees (from rf$finalModel$mse).
      F10 RF: CV RMSE vs mtry.
      F11 SVR: CV RMSE heatmap over (C, sigma).
      F12 Learning curves: for training sizes 20, 30, …, 80, draw 20
          random subsets of train.csv, refit each model with FROZEN
          tuned hyperparameters, compute RMSE on the subset (training
          error) and on test.csv (test error); plot mean ± SD vs size,
          facet by model. (Hyperparameters are frozen before this, so the
          test set does not influence model selection.)
      F13 CV RMSE distribution per model (boxplot over 25 resamples).
      (+ F11b XGBoost train vs CV RMSE vs boosting round, if M5 used.)
  ✔ Verify: models load from .rds and predict; figures exist.

PHASE 7 — Evaluate (step 6)
  - R/06_evaluate.R: predict on test.csv for every model.
  - Metrics (utils_metrics.R): RMSE, MAE, R², bias = mean(dz),
    sigma_NMAD = 1.4826 * median(|dz - median(dz)|),
    outlier fraction eta = mean(|dz| > 0.15),
    where dz = (z_pred - z_spec) / (1 + z_spec).
  - 95% bootstrap CIs (boot, R = 2000) for RMSE, R², sigma_NMAD on the
    test predictions.
  - T05_test_metrics.csv; also save outputs/tables/test_predictions.csv
    (objid, z_spec, prediction per model).
  - Figures: F14 predicted vs spectroscopic z (facet per model, y = x line,
    ±0.15(1+z) outlier envelope dashed, metrics annotated in panel),
    F15 dz vs z_spec residual plot, F16 dz histogram/density per model,
    F17 model comparison bar chart of test RMSE with CI error bars and
    the baseline as a dashed horizontal line.
  ✔ Verify: best model beats baseline; if not, report it honestly.

PHASE 8 — Interpret physics (step 7)
  - R/07_interpret.R:
      * T06 feature importance: RF permutation importance (%IncMSE) +
        standardised LM coefficients with 95% CI.
      * F18 feature importance plot (both methods side by side).
      * F19 partial dependence of predicted z on g_r and r_i (pdp package,
        training data only).
      * Write outputs/tables/interpretation_notes.md: auto-generated bullet
        facts (e.g. "g_r is the most important feature (X %IncMSE)")
        pulled from the tables, to help me write the discussion.
  - The physics story to test against the numbers: the 4000 Å break moves
    from the g into the r filter around z ≈ 0.4 (4000 × 1.4 ≈ 5600 Å),
    so g−r should redden monotonically with z over our range and be the
    top predictor; r magnitude helps because more distant galaxies appear
    fainter (inverse-square law + flux-limited sample). Say clearly
    whether the results support or contradict this.

PHASE 9 — Report + README results
  - report/report.Rmd (output: html_document AND word_document), sections:
    Abstract, Introduction & physics background, Data (acquisition,
    AI-assisted cleaning, summary table), Methods (split, models, CV,
    metrics with formulas), Results (training figures, test metrics,
    comparison), Discussion (physics interpretation, limitations of
    n = 100), Conclusion, References, Appendix (sessionInfo, AI usage log).
    All numbers inline via `r` chunks that read outputs/tables.
    Figures included from outputs/figures with numbered captions taken
    from docs/REPORT_GUIDE.md.
  - Fill README.md §12 "Results" with the real numbers from T05.

PHASE 10 — Tests & final check
  - tests/testthat:
      test-metrics.R: metrics on hand-computed toy vectors.
      test-data.R: clean data has 30–100 rows, no NA, expected columns,
                   colours equal magnitude differences.
      test-leakage.R: train ∩ test objid is empty; sizes 80/20.
  - run_all.R in a fresh R session; write outputs/logs/sessionInfo.txt.
  - Walk through the Definition of Done checklist in TASK.md §5 and report
    each item as ✅ or ❌ with a reason.

=====================================================================
5. FIGURE & TABLE STYLE (for the report)
=====================================================================
- ggplot2 only, theme_report(), Okabe-Ito palette, consistent model colours
  across all figures (define once in utils_plot.R).
- Axis labels with units and LaTeX-like notation where helpful:
  "Spectroscopic redshift  z_spec", "Photometric redshift  z_phot",
  "Δz/(1+z)", "Colour  g − r  (mag)".
- Default size 6.5 × 4.5 in; facet plots 7 × 5 in. Text ≥ 9 pt at print size.
- File naming: F{nn}_{short_snake_name}.png/.pdf; T{nn}_{name}.csv.
- For each figure also write a one-line draft caption into
  outputs/figures/captions.md.

=====================================================================
6. HOW TO COMMUNICATE WITH ME
=====================================================================
- At the end of each phase, give me: what was done, files created, any
  warnings, and anything I must decide. Keep it short.
- Ask me before: changing a decision in DECISIONS.md, changing the dataset
  size, adding/removing a model, installing system-level software.
- If something fails, show the exact error and your proposed fix.
- Never claim a step works unless you ran it.

Start with PHASE 1 now.
```

---

## Tips for using this prompt

- If your agent has a short context window, paste the prompt, then say
  "Do Phase 1 only", review, then "Do Phase 2", and so on.
- Most coding agents cannot reach SkyServer from their sandbox. Download the
  CSV yourself (README §5) and put it at `data/raw/sdss_raw.csv` **before**
  Phase 2. This is also the most reproducible approach.
- Keep `docs/AI_USAGE.md` honest. It is evidence for workflow step 2.
