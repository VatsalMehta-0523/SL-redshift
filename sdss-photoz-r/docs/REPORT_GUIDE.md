# REPORT_GUIDE.md — Figures, Tables & Report Structure

This is the specification for every figure and table the pipeline must
produce, and where each one goes in the written report. Agents must create
**all** items marked *Required*.

Conventions: `ggplot2` + `theme_report()`, Okabe-Ito palette, fixed model
colours. Every figure is saved as `outputs/figures/F{nn}_{name}.png` (300 dpi)
**and** `.pdf`. Tables are saved as `outputs/tables/T{nn}_{name}.csv` plus `.md`.

---

## 1. Tables

| ID | File | Required | Contents | Report section |
|---|---|---|---|---|
| T01 | `T01_dataset_summary` | ✅ | n, mean, SD, min, median, max for every magnitude, colour and redshift | Data |
| T02 | `T02_cleaning_log` | ✅ | step, rule, rows_before, rows_after, removed, reason | Data (AI-assisted cleaning) |
| T03 | `T03_hyperparameters` | ✅ | model, parameter, search grid, selected value | Methods |
| T04 | `T04_cv_metrics` | ✅ | model, CV RMSE mean ± SD, R² mean ± SD, MAE mean ± SD (25 resamples) | Results: training |
| T05 | `T05_test_metrics` | ✅ | model, RMSE [95% CI], MAE, R² [CI], bias, σ_NMAD [CI], η | Results: test (**main table**) |
| T06 | `T06_feature_importance` | ✅ | feature, RF %IncMSE, LM standardised coef ± 95% CI, rank | Discussion |
| — | `test_predictions.csv` | ✅ | objid, z_spec, prediction per model | Appendix / reproducibility |

---

## 2. Figures

### A. Data & physics (EDA), from `03_eda.R`

| ID | Name | Required | What it shows | Size (in) |
|---|---|---|---|---|
| F01 | `redshift_hist` | ✅ | Histogram + density of spectroscopic z (n = 100) | 6.5×4.5 |
| F02 | `magnitude_dists` | ✅ | Density of u, g, r, i, z magnitudes (one panel or overlaid) | 7×5 |
| F03 | `colour_colour` | ✅ | u−g vs g−r scatter, points coloured by redshift (viridis) | 6.5×5 |
| F04 | `colour_vs_redshift` | ✅ | 4 panels: each colour vs z with LOESS fit. **Key physics figure** | 7×5 |
| F05 | `correlation_heatmap` | ✅ | Pearson correlations among features + redshift, values annotated | 6×5 |
| F06 | `r_mag_vs_redshift` | ✅ | r magnitude vs z (brightness–distance relation) | 6.5×4.5 |
| F20 | `break_vs_filters` | ✅ | Observed wavelength of the 4000 Å break, 4000(1+z), vs z, over shaded SDSS filter bands (approx. effective λ: u 3551, g 4686, r 6166, i 7480, z 8932 Å). Mark the sample's z-range | 6.5×4.5 |

### B. Split, from `04_split.R`

| ID | Name | Required | What it shows |
|---|---|---|---|
| F07 | `train_test_split` | ✅ | Overlaid histograms/densities of z for train (80) vs test (20); KS-test p-value in subtitle |

### C. Training (the "training graphs"), from `05_train.R`

| ID | Name | Required | What it shows |
|---|---|---|---|
| F08 | `knn_tuning` | ✅ | CV RMSE vs k (1–20), ±1 SD ribbon, chosen k marked |
| F09 | `rf_oob_vs_trees` | ✅ | RF OOB MSE vs number of trees (convergence) |
| F10 | `rf_mtry_tuning` | ✅ | CV RMSE vs mtry (1–5) with error bars |
| F11 | `svr_tuning_heatmap` | ✅ | CV RMSE over C × sigma grid, best cell outlined |
| F11b | `xgb_training_curve` | if M5 | Train vs CV RMSE vs boosting round, early-stopping point marked |
| F12 | `learning_curves` | ✅ | Training & test RMSE vs training size (20–80), mean ± SD over 20 repeats, one facet per model |
| F13 | `cv_rmse_boxplot` | ✅ | Distribution of CV RMSE over 25 resamples per model (incl. baseline) |

### D. Evaluation, from `06_evaluate.R`

| ID | Name | Required | What it shows |
|---|---|---|---|
| F14 | `pred_vs_true` | ✅ | z_phot vs z_spec, facet per model; y = x line; dashed ±0.15(1+z) envelope; RMSE, σ_NMAD, η annotated. **Main result figure** |
| F15 | `residuals_vs_z` | ✅ | Δz/(1+z) vs z_spec per model, zero line, LOESS trend (shows systematic bias at low/high z) |
| F16 | `residual_dist` | ✅ | Density/histogram of Δz/(1+z) per model |
| F17 | `model_comparison` | ✅ | Bar/point chart of test RMSE with 95% bootstrap CI; baseline as dashed line |

### E. Interpretation, from `07_interpret.R`

| ID | Name | Required | What it shows |
|---|---|---|---|
| F18 | `feature_importance` | ✅ | Left: RF permutation importance. Right: LM standardised coefficients ± CI |
| F19 | `partial_dependence` | ✅ | RF partial dependence of predicted z on g−r and r−i |

---

## 3. Suggested report structure and where each item goes

1. **Title, Abstract** (≈150 words): goal, data (n = 100 SDSS galaxies),
   best model and its test RMSE / σ_NMAD from T05, and the main physics finding.
2. **Introduction & Physics Background**
   - What redshift is: z = (λ_obs − λ_emit)/λ_emit; Hubble's law v ≈ cz at low z.
   - Spectroscopic vs photometric redshift: spectroscopy is accurate but slow;
     photometry is fast and works for many more galaxies.
   - The 4000 Å break and how it moves through the filters → **F20**.
   - Aim and research question.
3. **Data**
   - Source, query, cuts (D-004, D-005) → `data/sql/sdss_query.sql`
   - AI-assisted inspection & cleaning (workflow step 2) → **T02**, summary of
     `docs/AI_USAGE.md`
   - Summary statistics → **T01**, **F01**, **F02**
   - Exploratory physics → **F03**, **F04**, **F05**, **F06**
4. **Methods**
   - Features and target (D-006, D-007)
   - Train/test split → **F07** (D-009)
   - Models (D-008) and tuning (D-010) → **T03**
   - Metrics with formulas (D-011)
5. **Results**
   - Training: **F08–F11**, **T04**, **F13**
   - Learning curves → **F12**
   - Test performance → **T05** (main table), **F14**, **F17**
   - Error analysis → **F15**, **F16**
6. **Discussion: Physics Interpretation**
   - Which features matter and why → **T06**, **F18**, **F19**
   - Does g−r lead (4000 Å break)? Does r help (inverse-square brightness)?
   - Where the models fail (low/high z, outliers) and the physical reasons
     (galaxy type mix, the break leaving the band, photometric noise)
   - Comparison with the literature (SDSS photo-z σ_NMAD is typically
     ~0.02–0.03 with large training sets; expect worse with n = 80)
7. **Limitations**: n = 100 (constraint), 20-point test set, z-range < 0.5,
   single galaxy population, no magnitude errors used in training.
8. **Conclusion**
9. **References**: see README §15
10. **Appendix**: AI usage log, sessionInfo, full hyperparameter grids

---

## 4. Caption drafts (agents append real numbers in captions.md)

- **F04:** Colours of 100 SDSS galaxies vs spectroscopic redshift. Solid
  lines are LOESS fits. g−r reddens with z as the 4000 Å break moves toward
  the r band.
- **F12:** Learning curves showing mean training and test RMSE (±1 SD, 20
  repeats) versus training-set size, for each model with frozen
  hyperparameters.
- **F14:** Photometric vs spectroscopic redshift on the 20-galaxy test set.
  The solid line marks perfect agreement and the dashed lines mark the
  catastrophic-outlier threshold |Δz| = 0.15(1+z).
- **F17:** Test-set RMSE per model with 95% bootstrap confidence intervals.
  The dashed line shows the mean-prediction baseline.
