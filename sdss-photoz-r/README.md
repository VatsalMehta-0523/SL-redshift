# Photometric Redshift Prediction of Galaxies using SDSS Data

**Unit 4 Mini-Project: AI-assisted Analysis of Physics Data using Supervised Learning in R**

This project predicts how far away galaxies are by estimating their
**redshift (z)** from their brightness in five colour filters. The data
comes from the Sloan Digital Sky Survey (SDSS). We train and compare several
supervised machine-learning models in **R**, evaluate them with standard
regression metrics and with the metrics astronomers use for photo-z, and
explain the results with the underlying physics (the **4000 Å break**
redshifting through the filters).

> 📌 **The assignment brief is [`TASK.md`](TASK.md), and it overrides every
> other document in this repository.**
> Coding agents: start with [`AGENTS.md`](AGENTS.md) and paste
> [`PROMPT.md`](PROMPT.md) as your first instruction.

---

## Table of contents

1. [Project at a glance](#1-project-at-a-glance)
2. [How this maps to the assignment brief](#2-how-this-maps-to-the-assignment-brief)
3. [Physics background](#3-physics-background)
4. [Requirements & installation](#4-requirements--installation)
5. [Getting the data (SDSS SkyServer)](#5-getting-the-data-sdss-skyserver)
6. [AI-assisted inspection & cleaning](#6-ai-assisted-inspection--cleaning)
7. [Repository structure](#7-repository-structure)
8. [Features & target](#8-features--target)
9. [Models](#9-models)
10. [Training, validation & metrics](#10-training-validation--metrics)
11. [How to run](#11-how-to-run)
12. [Results](#12-results)
13. [Outputs: figures & tables for the report](#13-outputs-figures--tables-for-the-report)
14. [Limitations](#14-limitations)
15. [References](#15-references)
16. [Documentation map, FAQ & troubleshooting](#16-documentation-map-faq--troubleshooting)

---

## 1. Project at a glance

| Item | Value |
|---|---|
| Physics question | Can a galaxy's colours predict its redshift (distance)? |
| Data | SDSS DR18 galaxies with spectroscopic redshifts (public) |
| Observations | **100 galaxies** (brief: 30–100) → 80 train / 20 test |
| Inputs (features) | Colours `u_g`, `g_r`, `r_i`, `i_z` + r-band magnitude `r` |
| Output (target) | Spectroscopic redshift `redshift` (continuous → **regression**) |
| Models | Mean baseline, Linear Regression, k-NN, Random Forest, SVR (+ optional XGBoost) |
| Validation | 5-fold CV repeated 5× on training set; held-out test set |
| Metrics | RMSE, MAE, R², bias, σ_NMAD, outlier fraction η, 95% bootstrap CIs |
| Language | **R ≥ 4.3** only (caret, ggplot2, R Markdown) |
| Deliverables | 20+ report-ready figures, 6 tables, an HTML + Word report |

---

## 2. How this maps to the assignment brief

| Brief step | What we do | Where |
|---|---|---|
| 1. Collect or obtain a physics dataset (30–100 obs.) | SQL query to SDSS SkyServer, 120 raw rows, cleaned and sampled to **100** | `data/sql/`, `R/01_acquire.R` |
| 2. Use AI tools to inspect, clean, preprocess | An AI assistant inspects the structure, flags anomalies, and proposes cleaning rules; the owner approves; everything is logged | `R/02_inspect_clean.R`, `docs/AI_USAGE.md`, T02 |
| 3. Import the dataset into R | `readr` with explicit column types; EDA | `R/02_…`, `R/03_eda.R` |
| 4. Split into training and testing sets | Stratified 80/20 split, seed 42 | `R/04_split.R` |
| 5. Train one or more supervised models | 5 models, tuned by repeated CV | `R/05_train.R` |
| 6. Evaluate using suitable metrics | Test-set metrics with bootstrap CIs | `R/06_evaluate.R` |
| 7. Interpret in the context of the physics | Feature importance, partial dependence, 4000 Å break | `R/07_interpret.R`, report |

The brief's project table lists examples ("projects *such as*") and leaves
the model open. This project uses **publicly available physics data**, which
the unit description explicitly allows. ⚠️ Instructor confirmation is pending
(`DECISIONS.md` D-001).

---

## 3. Physics background

### 3.1 Redshift
Light from a receding galaxy is stretched to longer (redder) wavelengths:

$$ z = \frac{\lambda_{\text{obs}} - \lambda_{\text{emit}}}{\lambda_{\text{emit}}}, \qquad \lambda_{\text{obs}} = (1+z)\,\lambda_{\text{emit}} $$

At low redshift, Hubble's law gives v ≈ cz = H₀d, so redshift measures
**distance**. For example, z = 0.1 corresponds to roughly 1.3 billion
light-years.

### 3.2 Spectroscopic vs photometric redshift
- **Spectroscopic (z_spec):** split the light into a spectrum and measure the
  shift of the lines. This is very precise (~10⁻⁴) but slow and expensive, so
  only a few million galaxies have one.
- **Photometric (z_phot):** estimate z from brightness in a few broad
  filters. It is less precise but works for **billions** of galaxies, which is
  essential for surveys such as LSST/Rubin, Euclid and DES.

We **train** on galaxies that have both, so that z_phot can later be
estimated for galaxies that have only photometry. This is a textbook
supervised-learning problem.

### 3.3 SDSS filters and magnitudes
SDSS imaged the sky through five filters (approximate effective wavelengths):

| Filter | u | g | r | i | z |
|---|---|---|---|---|---|
| λ_eff (Å) | 3551 | 4686 | 6166 | 7480 | 8932 |

A **magnitude** is a logarithmic brightness, m = −2.5 log₁₀(F) + const.
Larger m means fainter. A **colour** is the difference of two magnitudes
(e.g. g − r), which equals a flux **ratio**. Colours describe the *shape* of
the spectrum, independent of overall brightness.

### 3.4 Why colours encode redshift: the 4000 Å break
Older stellar populations produce a sharp drop in galaxy spectra blueward of
**4000 Å** (metal absorption plus the Balmer break). As z increases, the
break moves to 4000(1 + z) Å:

| z | Break observed at | Lies in filter |
|---|---|---|
| 0.05 | 4200 Å | g |
| 0.15 | 4600 Å | g |
| 0.30 | 5200 Å | g → r edge |
| 0.40 | 5600 Å | entering r |

So as z grows, flux is removed from the g band, and **g − r gets redder
(larger)**. This is the main physical signal our models should learn, and we
test for it in step 7.

### 3.5 Why the r magnitude helps
Flux falls as 1/d² (inverse-square law). In a flux-limited sample
(r ≤ 17.77), more distant galaxies are on average **fainter** (larger r), so
r adds distance information that colours alone lack.

### 3.6 Hypotheses tested in this project
- **H1:** g − r is the most important predictor (4000 Å break).
- **H2:** Predicted z increases monotonically with g − r over 0 < z < 0.5.
- **H3:** Non-linear models (kNN, RF, SVR) beat linear regression, because
  the colour–redshift relation is curved.
- **H4:** All models beat the mean baseline.

---

## 4. Requirements & installation

| Software | Version | Notes |
|---|---|---|
| R | ≥ 4.3 (developed on 4.6.1) | <https://cran.r-project.org>, or `winget install --id RProject.R` |
| VS Code + R extension | recent | Editor. RStudio is **not** needed |
| Pandoc | ≥ 2.0 | Needed only to render the report (`pandoc --version` to check); `winget install --id JohnMacFarlane.Pandoc` |
| LaTeX (optional) | TinyTeX | Only for PDF reports: `tinytex::install_tinytex()` |

Add R's `bin` folder (e.g. `C:\Program Files\R\R-4.6.1\bin`) to your PATH so
that `Rscript` works in any terminal. Check it with `Rscript --version`.

**R packages** are managed by **renv** and locked in `renv.lock`:

| Purpose | Packages |
|---|---|
| Data handling | `readr`, `dplyr`, `tidyr`, `purrr`, `tibble`, `janitor`, `here`, `glue` |
| Data download | `httr2` |
| Modelling | `caret`, `randomForest`, `kernlab` (SVR), `FNN`, `xgboost` (optional) |
| Evaluation | `boot` |
| Plotting | `ggplot2`, `patchwork`, `ggcorrplot`, `viridisLite` |
| Interpretation | `pdp`, `vip` |
| Reporting | `rmarkdown`, `knitr` |
| Testing / tooling | `testthat`, `renv`, `styler`, `lintr`, `languageserver` (VS Code) |

`renv.lock` grows phase by phase: a phase that needs a new package runs
`renv::install()` and then `renv::snapshot()`.

### 4.1 Install the packages

Run this once, from inside the `sdss-photoz-r/` folder:

```bash
Rscript -e "renv::restore(prompt = FALSE)"
```

You don't need to install renv first. `.Rprofile` runs `renv/activate.R`,
which installs renv itself if it's missing and then restores the exact
package versions from `renv.lock` into the project library `renv/library/`.

### 4.2 renv activates automatically

There is **no activate step** (unlike a Python virtualenv). Whenever R starts
with `sdss-photoz-r/` as its working directory, `.Rprofile` switches on the
project library. So:

- Always open **the `sdss-photoz-r/` folder** in VS Code (*File → Open
  Folder*), not its parent folder.
- Run scripts from that folder: `Rscript R/01_acquire.R`.
- Check the setup with `Rscript -e "renv::status()"`. It should report a
  consistent state.

### 4.3 VS Code setup

1. Install the R extension: `code --install-extension REditorSupport.r`.
2. `languageserver` (autocomplete, linting) is already in `renv.lock`, so step
   4.1 installs it.
3. Open a script and press **Ctrl+Enter** to send the current line or
   selection to an R terminal. You can also run whole scripts with `Rscript`
   in the integrated terminal.

**PowerShell quoting:** Windows PowerShell 5.1 drops double quotes nested
inside single quotes when it calls `Rscript`. Always put the R code in
**double quotes, with single quotes inside**, as every command in this
repository does:

```bash
Rscript -e "testthat::test_dir('tests/testthat')"
```

This form works in PowerShell, cmd and bash.

---

## 5. Getting the data (SDSS SkyServer)

**Option A (automatic):** run `Rscript R/01_acquire.R` from the
`sdss-photoz-r/` folder. It sends the query below to the SkyServer SqlSearch
web service (DR18, falling back to DR17), saves `data/raw/sdss_raw.csv`, and
writes `ACQUISITION.md`. It never downloads again once the file exists.

**Option B (manual):** use this if the script can't reach SkyServer. It takes
about 2 minutes.

1. Open **<https://skyserver.sdss.org/dr18/SearchTools/sql>**
   (if DR18 is unavailable, use `/dr17/`).
2. Paste the query below. It is also in `data/sql/sdss_query.sql`.
3. Set **Output format → CSV** and click **Submit**.
4. Save the file as **`data/raw/sdss_raw.csv`**. If SkyServer adds a first
   line such as `#Table1`, delete only that line.
5. Commit it. **Never edit this file again** (D-015). The query uses
   `ORDER BY NEWID()`, so a re-run gives *different* galaxies.

```sql
SELECT TOP 120
    p.objid,
    p.dered_u AS u, p.dered_g AS g, p.dered_r AS r,
    p.dered_i AS i, p.dered_z AS zmag,
    p.err_u, p.err_g, p.err_r, p.err_i, p.err_z,
    s.z    AS redshift,
    s.zErr AS redshift_err,
    p.ra, p.dec
FROM PhotoObj AS p
JOIN SpecObj  AS s ON s.bestobjid = p.objid
WHERE s.class    = 'GALAXY'
  AND s.zWarning = 0
  AND p.clean    = 1
  AND p.dered_r BETWEEN 14 AND 17.77
  AND s.z > 0.01 AND s.z < 0.5
  AND p.err_u < 0.2 AND p.err_g < 0.2 AND p.err_r < 0.2
  AND p.err_i < 0.2 AND p.err_z < 0.2
ORDER BY NEWID()
```

**What each cut does** (see D-005):

| Cut | Purpose |
|---|---|
| `class = 'GALAXY'` | Excludes stars and quasars |
| `zWarning = 0` | Keeps only reliable spectroscopic redshifts |
| `clean = 1` | Keeps only photometry without known problems (saturation, edges, blends) |
| `dered_r 14–17.77` | SDSS Main Galaxy Sample flux limit, for a homogeneous sample |
| `0.01 < z < 0.5` | Removes local and peculiar-velocity-dominated objects; keeps a range the filters can resolve |
| `err_* < 0.2` | Removes noisy photometry |
| `dered_*` | Magnitudes corrected for Milky Way dust (extinction) |

**Raw file columns:** `objid, u, g, r, i, zmag, err_u, err_g, err_r, err_i,
err_z, redshift, redshift_err, ra, dec`.

⚠️ **`objid` must be read as text**, because 64-bit IDs lose digits as
numbers. ⚠️ **`zmag`** is the z-*band* magnitude. **`redshift`** is the
target.

After the download, `R/01_acquire.R` writes `data/raw/ACQUISITION.md` with
the date, data release, query, row count and MD5 checksum.

---

## 6. AI-assisted inspection & cleaning

Brief step 2 asks for **AI tools** to inspect, clean and preprocess the data.
Here is how we do it (D-012):

1. **Inspect:** the AI assistant reviews `str()`, `summary()`, NA and
   duplicate counts, and range checks, then flags anomalies.
2. **Propose:** the AI suggests cleaning rules with a reason for each.
3. **Decide:** the owner accepts, modifies or rejects each rule.
4. **Implement:** the rules are coded in `R/02_inspect_clean.R`. Each rule logs
   its row counts to `outputs/tables/T02_cleaning_log.csv`.
5. **Record:** every interaction is written to `docs/AI_USAGE.md` (prompt →
   suggestion → decision → code).

**Cleaning pipeline:**

| # | Rule | Why |
|---|---|---|
| 1 | Read with explicit column types; `janitor::clean_names()` | Type safety; consistent names |
| 2 | Report structure, NAs, duplicates | Inspection evidence |
| 3 | Remove duplicate `objid` | One row per galaxy |
| 4 | Remove NA or sentinel values (−9999, 9999) | SDSS uses sentinels for missing photometry |
| 5 | Physical ranges: magnitudes 10–30, 0 < z < 1 | Removes impossible values |
| 6 | Colour outliers beyond median ± 5·MAD | Removes blended or bad photometry (robust to skew) |
| 7 | Derive colours `u_g, g_r, r_i, i_z` | Features (D-006) |
| 8 | Random sample to **exactly 100** (seed 42) | Brief: 30–100 (D-003) |
| 9 | Assert 30 ≤ n ≤ 100; write `data/processed/sdss_clean.csv` | Hard constraint C1 |

**Preprocessing done inside modelling:** centring and scaling are fitted on
each CV training fold only (`caret::train(preProcess = c("center","scale"))`).
This prevents leakage from the test set.

---

## 7. Repository structure

```
sdss-photoz-r/
├── TASK.md                 ← ABSOLUTE task spec (course brief). Overrides all.
├── README.md               ← this file
├── AGENTS.md               ← operating manual for AI coding agents
├── CLAUDE.md               ← pointer for Claude Code → AGENTS.md
├── PROMPT.md               ← master prompt to paste into the coding agent
├── CONTRIBUTING.md         ← style, commits, how to add models/figures
├── DECISIONS.md            ← decision log (D-001 …)
├── docs/
│   ├── REPORT_GUIDE.md     ← every figure/table + report outline
│   └── AI_USAGE.md         ← log of AI-assisted work (brief step 2)
├── data/
│   ├── sql/sdss_query.sql  ← the SkyServer query
│   ├── raw/                ← sdss_raw.csv (frozen) + ACQUISITION.md
│   └── processed/          ← sdss_clean.csv, train.csv, test.csv
├── R/
│   ├── 00_setup.R          ← packages, SEED = 42, paths, theme
│   ├── utils_metrics.R     ← rmse(), mae(), r2(), bias(), sigma_nmad(), eta()
│   ├── utils_plot.R        ← theme_report(), save_fig(), model colours
│   ├── 01_acquire.R        ← step 1
│   ├── 02_inspect_clean.R  ← steps 2–3
│   ├── 03_eda.R            ← step 3 (exploration)
│   ├── 04_split.R          ← step 4
│   ├── 05_train.R          ← step 5
│   ├── 06_evaluate.R       ← step 6
│   └── 07_interpret.R      ← step 7
├── run_all.R               ← runs 00 → 07, logs time, writes sessionInfo
├── report/report.Rmd       ← → report.html + report.docx
├── outputs/
│   ├── figures/            ← F01–F20 (.png 300 dpi + .pdf) + captions.md
│   ├── tables/             ← T01–T06 (.csv + .md), test_predictions.csv
│   ├── models/             ← fitted models (.rds)
│   └── logs/               ← run_log.txt, sessionInfo.txt
├── tests/testthat/         ← test-metrics.R, test-data.R, test-leakage.R
├── renv.lock               ← exact package versions (renv)
├── renv/                   ← activate.R + settings (library/ is git-ignored)
├── .Rprofile               ← auto-activates renv when R starts here
├── .here                   ← marks this folder as the root for here::here()
├── .gitattributes          ← keeps data/raw byte-exact (no CRLF conversion)
└── .gitignore
```

The git repository root is the folder above `sdss-photoz-r/`. The `.here`
file makes `here::here()` resolve paths inside `sdss-photoz-r/` anyway.

---

## 8. Features & target

| Variable | Formula | Role | Physical meaning |
|---|---|---|---|
| `u_g` | u − g | feature | UV slope, star-formation and Balmer-break region |
| `g_r` | g − r | feature | **4000 Å break position**, the key redshift signal |
| `r_i` | r − i | feature | Break enters r at higher z; red continuum slope |
| `i_z` | i − zmag | feature | Near-IR slope, sensitive at the high-z end |
| `r` | dered_r | feature | Apparent brightness, a distance proxy (1/d²) |
| `redshift` | SpecObj.z | **target** | Spectroscopic redshift (ground truth) |

Why colours rather than raw magnitudes? The five magnitudes are strongly
correlated (bright galaxies are bright in every band). Colours remove that
common brightness factor and keep the spectral shape (D-006).

---

## 9. Models

| ID | Model | R implementation | Hyperparameters tuned | Why include it |
|---|---|---|---|---|
| M0 | Mean baseline | predicts mean of training z | — | Floor: any useful model must beat it |
| M1 | Linear regression | `caret`, `method = "lm"` | — | Interpretable coefficients; tests linearity |
| M2 | k-Nearest Neighbours | `method = "knn"` | k = 1…20 | "Similar colours ⇒ similar z", a classic photo-z method |
| M3 | Random Forest | `method = "rf"`, 500 trees | mtry = 1…5 | Non-linear, robust, gives feature importance |
| M4 | Support Vector Regression (RBF) | `method = "svmRadial"` | C = 2⁻²…2⁶, σ ∈ {0.01, 0.05, 0.1, 0.5, 1} | Smooth non-linear fit, good with small n |
| M5 | XGBoost *(optional)* | `xgboost::xgb.cv` | rounds (early stopping), depth, η | Gives train-vs-validation curves for the report |

All models use the formula `redshift ~ u_g + g_r + r_i + i_z + r` and the
**same CV folds**, so the comparison is fair.

---

## 10. Training, validation & metrics

**Split (D-009):** `caret::createDataPartition(redshift, p = 0.8)`,
stratified on redshift quantiles, seed 42 → **80 train / 20 test**.

**Tuning (D-010):** 5-fold cross-validation repeated 5 times (25 resamples)
on the 80 training galaxies. Hyperparameters are chosen by minimum mean CV
RMSE. **The test set is never used for tuning.**

**Learning curves (D-016):** after tuning, each model is refit on random
training subsets of size 20, 30, …, 80 (20 repeats each), with the tuned
hyperparameters fixed, to show how error changes with more data.

**Metrics (D-011).** Let Δz = (z_phot − z_spec) / (1 + z_spec).

| Metric | Formula | Meaning | Good value |
|---|---|---|---|
| RMSE | √mean((z_phot − z_spec)²) | Typical error size | → 0 |
| MAE | mean\|z_phot − z_spec\| | Robust average error | → 0 |
| R² | 1 − SS_res/SS_tot | Variance explained | → 1 |
| Bias | mean(Δz) | Systematic over/under-prediction | ≈ 0 |
| σ_NMAD | 1.4826 × median(\|Δz − median(Δz)\|) | Robust scatter (astronomy standard) | < 0.05 |
| η (outlier fraction) | fraction with \|Δz\| > 0.15 | Catastrophic failures | → 0 |

95% bootstrap confidence intervals (2000 resamples) are reported for test
RMSE, R² and σ_NMAD. With only 20 test galaxies, η can only take values in
steps of 5%.

---

## 11. How to run

All commands run from the `sdss-photoz-r/` folder, in PowerShell, cmd or bash.

```bash
# 0. One-time setup (§4.1)
Rscript -e "renv::restore(prompt = FALSE)"

# 1. Get the data: data/raw/sdss_raw.csv is already committed; if it is
#    missing, 01_acquire.R downloads it (§5)

# 2. Run the full pipeline (steps 1–7)
Rscript run_all.R

# 3. Run the tests
Rscript -e "testthat::test_dir('tests/testthat')"

# 4. Build the report (HTML + Word)
Rscript -e "rmarkdown::render('report/report.Rmd', output_format = 'all')"
```

You can also run the scripts one at a time, in order, with `Rscript R/01_acquire.R`
… `Rscript R/07_interpret.R`, or open one in VS Code and send it to the R
terminal (§4.3).

| Script | Approx. runtime |
|---|---|
| 01–04 | seconds |
| 05_train (with learning curves) | 1–5 min |
| 06–07 | < 1 min |

Using a coding agent? Paste **[PROMPT.md](PROMPT.md)** into it. It works in 10
phases and reports back after each one.

---

## 12. Results

> ⚠️ **Fill this section only from `outputs/tables/T05_test_metrics.csv`
> after running the pipeline. Never type numbers from memory or estimate
> them.** (AGENTS.md rule R7)

**Test-set performance (n = 20):**

| Model | RMSE [95% CI] | MAE | R² [95% CI] | Bias | σ_NMAD [95% CI] | η |
|---|---|---|---|---|---|---|
| M0 Baseline | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| M1 Linear | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| M2 k-NN | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| M3 Random Forest | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |
| M4 SVR | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ | _TBD_ |

**Best model:** _TBD_  **Most important feature:** _TBD_ (from T06)

**Hypotheses:** H1 _TBD_ · H2 _TBD_ · H3 _TBD_ · H4 _TBD_

**Key figures:** `F14_pred_vs_true.png` (main result), `F04_colour_vs_redshift.png`
(physics), `F12_learning_curves.png` (training).

---

## 13. Outputs: figures & tables for the report

The full specification is in [`docs/REPORT_GUIDE.md`](docs/REPORT_GUIDE.md).

| Group | IDs | Highlights |
|---|---|---|
| Data / physics (EDA) | F01–F06, F20 | Redshift histogram, colour–colour diagram, **colours vs z**, correlation heatmap, **4000 Å break across filters** |
| Split | F07 | Train vs test redshift distributions + KS test |
| **Training** | F08–F13 | kNN k-tuning, RF OOB convergence, RF mtry, SVR C×σ heatmap, **learning curves**, CV RMSE boxplots |
| Evaluation | F14–F17 | **Predicted vs true z**, residuals vs z, residual distributions, model comparison with CIs |
| Interpretation | F18–F19 | Feature importance (RF + LM), partial dependence on g−r and r−i |
| Tables | T01–T06 | Data summary, cleaning log, hyperparameters, CV metrics, **test metrics**, feature importance |

Every figure is saved as **PNG (300 dpi)** for Word and **PDF (vector)** for
LaTeX. Draft captions are in `outputs/figures/captions.md`.

---

## 14. Limitations

- **Small sample (n = 100)** is set by the brief. Real photo-z work uses
  10⁵–10⁶ galaxies, so expect larger errors than published SDSS photo-z
  (σ_NMAD ≈ 0.02–0.03).
- **20-galaxy test set:** metrics have wide confidence intervals, so read
  the CIs, not just the point estimates.
- **Redshift range 0.01–0.5** and r ≤ 17.77: the models must not be used
  outside this range.
- **Mixed galaxy types:** red ellipticals have a strong 4000 Å break; blue
  star-forming galaxies have a weaker one. This causes scatter.
- **Very blue galaxies are excluded.** The 5·MAD colour cut removed two
  galaxies that are blue in every colour (likely real star-forming galaxies),
  so the models were never trained or tested on such objects (T02,
  `docs/AI_USAGE.md` AI-004).
- **Magnitude errors are not used** as weights or inputs.
- **Spectroscopic selection bias:** galaxies chosen for SDSS spectra are
  brighter than typical photometric-only galaxies.

---

## 15. References

1. York, D. G. et al. (2000). *The Sloan Digital Sky Survey: Technical Summary.* AJ, 120, 1579.
2. Strauss, M. A. et al. (2002). *Spectroscopic Target Selection in the SDSS: The Main Galaxy Sample.* AJ, 124, 1810.
3. Csabai, I. et al. (2003). *The Application of Photometric Redshifts to the SDSS Early Data Release.* AJ, 125, 580.
4. Collister, A. A. & Lahav, O. (2004). *ANNz: Estimating Photometric Redshifts Using Artificial Neural Networks.* PASP, 116, 345.
5. Beck, R. et al. (2016). *Photometric redshifts for the SDSS Data Release 12.* MNRAS, 460, 1371.
6. Salvato, M., Ilbert, O. & Hoyle, B. (2019). *The many flavours of photometric redshifts.* Nature Astronomy, 3, 212.
7. Bruzual, G. (1983). *Spectral evolution of galaxies. I. Early-type systems.* ApJ, 273, 105 (4000 Å break).
8. Kuhn, M. (2008). *Building Predictive Models in R Using the caret Package.* J. Stat. Softw., 28(5).
9. Breiman, L. (2001). *Random Forests.* Machine Learning, 45, 5–32.
10. SDSS SkyServer DR18: <https://skyserver.sdss.org/dr18>. Please acknowledge SDSS as described at <https://www.sdss.org/collaboration/citing-sdss/>.

---

## 16. Documentation map, FAQ & troubleshooting

### Documentation map

| File | Read it when… |
|---|---|
| [TASK.md](TASK.md) | You need to know what is *required* (the brief; it always wins) |
| [AGENTS.md](AGENTS.md) | You are an AI agent, or want the hard rules |
| [PROMPT.md](PROMPT.md) | You are starting a coding agent |
| [DECISIONS.md](DECISIONS.md) | You wonder *why* something was chosen |
| [CONTRIBUTING.md](CONTRIBUTING.md) | You are changing code, adding a model or figure |
| [docs/REPORT_GUIDE.md](docs/REPORT_GUIDE.md) | You are writing the report or making figures |
| [docs/AI_USAGE.md](docs/AI_USAGE.md) | You need evidence of AI-assisted cleaning (brief step 2) |

### FAQ

**Why not use thousands of galaxies? Models would be better.**
The brief requires 30–100 observations. We use the maximum (100) and
compensate with repeated CV and bootstrap CIs.

**Is this really "physics"?**
Yes. Redshift is a direct consequence of cosmic expansion (Doppler and
cosmological redshift), and the model works because of a physical spectral
feature (the 4000 Å break) moving through the filters.

**Where is the "AI-assisted" part?**
Brief step 2. See §6 and `docs/AI_USAGE.md`.

**Why de-reddened (`dered_`) magnitudes?**
Dust in our own galaxy makes objects look redder. That would mimic redshift,
so we remove it.

### Troubleshooting

| Problem | Fix |
|---|---|
| CSV has a `#Table1` first line | Delete that line only, or `read_csv(skip = 1)` |
| `objid` values look like `1.237e18` | Read with `col_types = cols(objid = col_character())` |
| Query times out | Re-submit; or reduce to `TOP 120` (already small) |
| DR18 page errors | Use `https://skyserver.sdss.org/dr17/SearchTools/sql` and record DR17 in ACQUISITION.md |
| Fewer than 100 rows after cleaning | Acceptable if ≥ 30 (record in DECISIONS); otherwise download again with `TOP 150` via a new decision |
| `svmRadial` very slow | Normal for 25 resamples × 45 grid points; still < 2 min |
| Report fails to render | Check `pandoc --version` (≥ 2.0); install with `winget install --id JohnMacFarlane.Pandoc`. For PDF install TinyTeX |
| `Unexpected token '-e'` in PowerShell | Put `&` before a quoted path: `& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" ...`, or add R to PATH (§4) |
| `object 'x' not found` from `Rscript -e '...("x")'` | PowerShell dropped the inner quotes. Use `Rscript -e "...('x')"` (§4.3) |
| `there is no package called …` | Run R from inside `sdss-photoz-r/` so renv activates, then `Rscript -e "renv::restore(prompt = FALSE)"` |
| `01_acquire.R` stops: MD5 has changed | The raw CSV was edited or its line endings were converted. Restore it with `git checkout -- data/raw/sdss_raw.csv` |
| A model is worse than baseline | Report it honestly. Never tune on the test set |

---

*Data: Sloan Digital Sky Survey. Funding for SDSS has been provided by the
Alfred P. Sloan Foundation, the Participating Institutions, the National
Science Foundation, and the U.S. Department of Energy Office of Science.*
