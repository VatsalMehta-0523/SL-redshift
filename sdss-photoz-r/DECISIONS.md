# DECISIONS.md — Architecture & Analysis Decision Log

Every significant choice in this project is recorded here so that the report
can justify it and so that agents do not silently change it.

**Rules**
- Append only. To change a decision, add a new entry that **supersedes** the
  old one, and set the old entry's status to `Superseded by D-xxx`.
- Status values: `Proposed` · `Accepted` · `Needs instructor confirmation` ·
  `Superseded by D-xxx` · `Rejected`.
- Each entry states its link to `TASK.md` where relevant.

---

## Index

| ID | Title | Status |
|---|---|---|
| D-001 | Project choice: photometric redshift from SDSS | Needs instructor confirmation |
| D-002 | Language: R only | Accepted |
| D-003 | Dataset size: exactly 100 galaxies (raw pull 120) | Accepted |
| D-004 | Data source: SDSS SkyServer SQL (DR18; fallback DR17) | Accepted |
| D-005 | Sample selection cuts | Accepted |
| D-006 | Features: four colours + r magnitude | Accepted |
| D-007 | Target: spectroscopic redshift | Accepted |
| D-008 | Model set: baseline + LM, kNN, RF, SVR (+ optional XGBoost) | Accepted |
| D-009 | Split: 80/20 stratified on redshift | Accepted |
| D-010 | Tuning: 5-fold CV repeated 5× on training set | Accepted |
| D-011 | Metrics: RMSE, MAE, R², bias, σ_NMAD, η + bootstrap CIs | Accepted |
| D-012 | Definition of "AI-assisted" cleaning and its logging | Accepted |
| D-013 | Frameworks: caret + ggplot2 + R Markdown + renv | Accepted |
| D-014 | Random seed = 42 | Accepted |
| D-015 | Raw data is frozen and committed | Accepted |
| D-016 | Learning curves evaluated on frozen hyperparameters | Accepted |
| D-017 | Static web demo: models exported from R, predictions reproduced in the browser | Accepted |

---

### D-001 — Project choice: photometric redshift from SDSS
- **Status:** Needs instructor confirmation
- **Context:** The brief lists example projects "such as" pendulum, Hooke's
  law, etc., and allows "publicly available physics data". The model choice
  is "left open".
- **Decision:** Predict galaxy redshift from broadband photometry (SDSS).
- **Rationale:** This is real astrophysical data with a clear physical mechanism
  (spectral features redshifting through filters). It is a natural regression
  problem, and it is freely available.
- **Consequences:** The owner must confirm with the instructor. If it is
  rejected, fall back to the cooling experiment (temperature prediction) and
  supersede this entry.
- **Owner note (fill in):** _Instructor confirmed on ____ / via ____._

### D-002 — Language: R only
- **Status:** Accepted
- **Context:** Brief step 3: "Import the dataset into R"; unit title "…in R".
- **Decision:** All acquisition, cleaning, modelling, plotting and reporting
  in R ≥ 4.3. SQL is used only to query SkyServer.
- **Consequences:** No Python. AI tools may *suggest* code, but the code that
  runs is R.

### D-003 — Dataset size: exactly 100 galaxies
- **Status:** Accepted
- **Context:** Brief step 1 requires 30–100 observations. SDSS has millions.
- **Decision:** Pull 120 random galaxies (cleaning buffer). After cleaning,
  randomly sample exactly 100 with `SEED`. If fewer than 100 survive but at
  least 30 do, keep all and note the count.
- **Rationale:** 100 is the maximum the brief allows and gives the most
  statistical power. The 20-row buffer keeps us from falling short after
  quality cuts without exceeding the limit in the analysis.
- **Consequences:** The test set has only 20 galaxies, so metrics have wide
  uncertainty. We mitigate this with repeated CV and bootstrap CIs (D-010,
  D-011), and discuss it in Limitations.

### D-004 — Data source: SDSS SkyServer SQL
- **Status:** Accepted
- **Decision:** Use SkyServer SQL Search on DR18 (`skyserver.sdss.org/dr18`).
  If DR18 is unavailable or the schema differs, use DR17. Record the exact
  release in `data/raw/ACQUISITION.md`.
- **Rationale:** Official source. It has `PhotoObj` + `SpecObj` joins and needs
  no account for small queries.

### D-005 — Sample selection cuts
- **Status:** Accepted
- **Decision:** `class = 'GALAXY'`, `zWarning = 0`, `clean = 1`,
  `14 ≤ dered_r ≤ 17.77`, `0.01 < z < 0.5`, all magnitude errors < 0.2.
- **Rationale:** `zWarning = 0` and `clean = 1` select reliable spectra and
  photometry. r ≤ 17.77 matches the SDSS Main Galaxy Sample flux limit, which
  gives a homogeneous population. The redshift range drops stars and
  near-zero-z contaminants. The error cut removes noisy photometry.
- **Consequences:** Redshifts will mostly lie in 0.02–0.3, so the model is
  valid only there. This must be stated in the report.

### D-006 — Features: four colours + r magnitude
- **Status:** Accepted
- **Decision:** Features are `u_g, g_r, r_i, i_z, r`.
- **Rationale:** Colours remove the overall brightness, so they trace the
  spectral shape, which encodes redshift. The r magnitude adds distance
  information, since fainter galaxies are farther on average. Using
  colours rather than five raw magnitudes also reduces collinearity.
- **Alternatives considered:** raw magnitudes only (highly collinear);
  colours only (loses the brightness–distance information).

### D-007 — Target: spectroscopic redshift
- **Status:** Accepted
- **Decision:** `SpecObj.z` (renamed `redshift`) is the ground truth.
- **Rationale:** Spectroscopic redshifts are accurate to about 10⁻⁴, far
  better than any photometric estimate.

### D-008 — Model set
- **Status:** Accepted
- **Decision:** M0 mean baseline, M1 linear regression, M2 k-NN, M3 random
  forest, M4 SVR (RBF kernel). M5 XGBoost is optional.
- **Rationale:** This spans a range from interpretable/parametric to flexible
  non-parametric models. kNN and RF are standard photo-z methods. The baseline
  shows whether the models learn anything at all.
- **Consequences:** The brief needs "one or more", so this goes beyond the
  minimum. If time is short, M4/M5 can be dropped by recording a new decision.

### D-009 — Split: 80/20 stratified on redshift
- **Status:** Accepted
- **Decision:** `caret::createDataPartition(redshift, p = 0.8)` gives 80 train
  and 20 test rows.
- **Rationale:** Stratifying makes both sets span the same redshift range,
  which matters a lot with small n.

### D-010 — Tuning: repeated 5-fold CV
- **Status:** Accepted
- **Decision:** 5-fold CV repeated 5 times (25 resamples) on the 80 training
  rows, with identical folds across models.
- **Rationale:** A single split with n = 80 is noisy. Repeated CV gives
  stable estimates and an SD for error bars. LOOCV was rejected because of its
  high variance and its cost for SVR/RF.

### D-011 — Metrics
- **Status:** Accepted
- **Decision:** With `dz = (z_pred − z_spec)/(1 + z_spec)`, report:
  - RMSE, MAE, R² (standard regression)
  - bias = mean(dz)
  - σ_NMAD = 1.4826 × median(|dz − median(dz)|)
  - η = fraction with |dz| > 0.15
  - 95% bootstrap CIs (2000 resamples) for test RMSE, R², σ_NMAD.
- **Rationale:** σ_NMAD and η are the standard photo-z metrics in the
  literature. The (1+z) normalisation reflects how redshift errors scale.
- **Note:** With 20 test points, η can only take multiples of 5%. State this.

### D-012 — Definition of "AI-assisted" cleaning
- **Status:** Accepted
- **Context:** Brief step 2: "Use AI tools to inspect, clean, and preprocess".
- **Decision:** An AI assistant (Claude / the coding agent) is used to inspect
  the raw data's structure and summary statistics, flag anomalies and
  outliers, propose cleaning rules, and write and review the cleaning code.
  The owner reviews every proposed rule. Each interaction is logged in
  `docs/AI_USAGE.md`, with the prompt, the AI's suggestion, the owner's
  decision, and the resulting code.
- **Consequences:** The log is part of the report appendix.

### D-013 — Frameworks
- **Status:** Accepted
- **Decision:** `caret` for modelling, `ggplot2` (+ `patchwork`) for plots,
  `rmarkdown` for the report (HTML + DOCX), `renv` for package locking,
  `testthat` for tests.
- **Rationale:** caret gives one interface for all models and is widely
  taught. tidymodels was considered; caret was chosen for simplicity. Word
  output is easy to paste into the final report. PDF needs LaTeX, so it is
  optional.

### D-014 — Random seed
- **Status:** Accepted
- **Decision:** `SEED <- 42`, set before every random operation.

### D-015 — Raw data frozen and committed
- **Status:** Accepted
- **Context:** `ORDER BY NEWID()` returns a different random sample on every
  run.
- **Decision:** The first download is saved to `data/raw/sdss_raw.csv`,
  checksummed in `ACQUISITION.md`, committed, and never modified.
- **Rationale:** Re-running the query would change the data and all results.

### D-016 — Learning curves on frozen hyperparameters
- **Status:** Accepted
- **Decision:** Learning curves (F12) refit each model on subsets of the
  training data (n = 20…80, 20 repeats) with hyperparameters fixed from D-010
  tuning. Error is reported on the subset (training error) and on the test
  set.
- **Rationale:** These curves show whether more data would help. The test set
  does not influence any modelling choice because the hyperparameters are
  already frozen.

---

### D-017 — Static web demo for free hosting
- **Status:** Accepted
- **Date:** 2026-10-22
- **Context:** The owner wants the project reachable at one free URL, deployable by drag and drop. Free static hosts (Netlify Drop) cannot run R, and free R hosts need a public repo or have tight hour limits.
- **Decision:** `R/08_export_web.R` exports the trained parameters of M1–M4 (scaling, linear coefficients, k-NN points, all 500 random-forest trees, SVR support vectors) to `site/model.js`. `site/predict.js` re-implements only the *prediction* step in JavaScript; `site/` is a static page that can be dropped on Netlify.
- **Rationale:** Zero cost, one URL, no server, instant load. All data handling, training, tuning and evaluation stay in R (D-002, TASK.md C4); the page only replays the frozen models.
- **Safeguard:** `tests/testthat/test-web.R` runs `predict.js` in R's V8 engine and requires its predictions to equal R's for all 20 test galaxies (tolerance 1e-9), the range check to flag the same galaxies, and the cosmology to match R's numerical integration.
- **Alternatives considered:** Posit Connect Cloud (free, but public repo only), shinyapps.io (25 active hours/month, token-based deploy), shinylive/webR (heavy downloads for caret and randomForest, slow first load).
- **Consequences:** Re-run `Rscript R/08_export_web.R` (or `run_all.R`) after retraining, then redeploy `site/`. The R Shiny app (`app/`) stays the R-native version.
- **Supersedes:** none

---

## Template for new decisions

```markdown
### D-0xx — <short title>
- **Status:** Proposed
- **Date:** YYYY-MM-DD
- **Context:** <what problem or question triggered this>
- **Decision:** <what we will do>
- **Rationale:** <why; link to TASK.md if relevant>
- **Alternatives considered:** <options and why rejected>
- **Consequences:** <what changes; follow-up actions>
- **Supersedes:** <D-xxx or none>
```
