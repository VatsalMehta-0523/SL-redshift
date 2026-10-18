# =============================================================================
# 06_evaluate.R — Workflow step 6: evaluate the models on the held-out test set
# Inputs : outputs/models/*.rds, data/processed/test.csv
# Outputs: outputs/tables/T05_test_metrics.csv/.md,
#          outputs/tables/test_predictions.csv,
#          outputs/figures/F14–F17 (.png + .pdf), captions.md
# Brief  : TASK.md §4, step 6; decisions D-011, D-014
# =============================================================================
#
# The models are used exactly as saved by 05_train.R. Nothing here feeds back
# into training or tuning (AGENTS.md R5).

source(here::here("R", "00_setup.R"))
suppressPackageStartupMessages(library(caret)) # predict() for train objects

test <- read_csv(PATHS$test, col_types = RAW_COL_TYPES, progress = FALSE)

model_ids <- MODEL_IDS[file.exists(file.path(PATHS$models, paste0(MODEL_IDS, ".rds")))]
models <- set_names(model_ids) |>
  map(\(id) readRDS(file.path(PATHS$models, paste0(id, ".rds"))))

N_BOOT <- 2000 # D-011
OUTLIER_DZ <- 0.15 # |dz| threshold for catastrophic outliers (eta)

# --- Predictions -------------------------------------------------------------

predictions <- test |>
  select(objid, z_spec = redshift) |>
  bind_cols(map_dfc(models, \(m) predict(m, newdata = test)))
write_csv(predictions, file.path(PATHS$tables, "test_predictions.csv"))

pred_long <- predictions |>
  pivot_longer(all_of(model_ids), names_to = "model", values_to = "z_phot") |>
  mutate(
    dz = dz(z_phot, z_spec),
    model = factor(model, levels = model_ids)
  )

# --- T05: test metrics with 95% bootstrap CIs --------------------------------

#' Percentile bootstrap CI for RMSE, R² and sigma_NMAD: resample the 20 test
#' galaxies with replacement N_BOOT times and recompute each metric.
bootstrap_ci <- function(pred, truth) {
  stat <- function(data, i) {
    c(rmse(data$pred[i], data$truth[i]),
      r2(data$pred[i], data$truth[i]),
      sigma_nmad(data$pred[i], data$truth[i]))
  }
  set.seed(SEED)
  b <- boot::boot(data.frame(pred = pred, truth = truth), stat, R = N_BOOT)
  ci <- apply(b$t, 2, quantile, probs = c(0.025, 0.975), na.rm = TRUE)
  tibble::tibble(
    rmse_lo = ci[1, 1], rmse_hi = ci[2, 1],
    r2_lo = ci[1, 2], r2_hi = ci[2, 2],
    sigma_nmad_lo = ci[1, 3], sigma_nmad_hi = ci[2, 3]
  )
}

t05 <- map_dfr(model_ids, \(id) {
  p <- predictions[[id]]
  z <- predictions$z_spec
  bind_cols(
    tibble::tibble(model = id, label = MODEL_LABELS[[id]], n = length(z)),
    all_metrics(p, z),
    bootstrap_ci(p, z),
    tibble::tibble(n_outliers = sum(abs(dz(p, z)) > OUTLIER_DZ))
  )
}) |>
  select(model, label, n, rmse, rmse_lo, rmse_hi, mae, r2, r2_lo, r2_hi,
         bias, sigma_nmad, sigma_nmad_lo, sigma_nmad_hi, eta, n_outliers)
save_table(t05, "T05", "test_metrics")

learners <- filter(t05, model != "M0_baseline")
best <- slice_min(learners, rmse, n = 1)
baseline_rmse <- t05$rmse[t05$model == "M0_baseline"]

# --- F14: predicted vs spectroscopic redshift (main result figure) ----------

lims <- range(c(pred_long$z_phot, pred_long$z_spec)) + c(-0.01, 0.01)
envelope <- tibble::tibble(z = seq(0, 1, by = 0.01)) |>
  mutate(lo = z - OUTLIER_DZ * (1 + z), hi = z + OUTLIER_DZ * (1 + z))
panel_text <- t05 |>
  mutate(
    model = factor(model, levels = model_ids),
    text = sprintf("RMSE = %.4f\nσ_NMAD = %.4f\nη = %.0f%%", rmse, sigma_nmad, 100 * eta)
  )

f14 <- ggplot(pred_long, aes(z_spec, z_phot)) +
  geom_line(data = envelope, aes(z, lo), linetype = "dashed", colour = "grey40") +
  geom_line(data = envelope, aes(z, hi), linetype = "dashed", colour = "grey40") +
  geom_abline(slope = 1, intercept = 0) +
  geom_point(aes(colour = model), size = 2, alpha = 0.85, show.legend = FALSE) +
  geom_label(data = panel_text, aes(x = -Inf, y = Inf, label = text),
             hjust = -0.05, vjust = 1.08, size = 2.9, lineheight = 0.95,
             fill = "white", linewidth = 0) +
  facet_wrap(~model, labeller = as_labeller(MODEL_LABELS)) +
  scale_colour_manual(values = MODEL_COLOURS) +
  coord_equal(xlim = lims, ylim = lims) +
  labs(x = "Spectroscopic redshift  z_spec", y = "Photometric redshift  z_phot",
       title = glue("Predicted versus true redshift on the test set (n = {nrow(test)})")) +
  theme_report()
save_fig(f14, "F14", "pred_vs_true", 7, 5.5)
add_caption("F14", glue(
  "Photometric versus spectroscopic redshift for the {nrow(test)} test galaxies. ",
  "The solid line is perfect agreement; dashed lines mark the catastrophic-",
  "outlier threshold |Δz| = {OUTLIER_DZ}(1 + z). Best learner by test RMSE: ",
  "{best$label} (RMSE {sprintf('%.4f', best$rmse)}, σ_NMAD ",
  "{sprintf('%.4f', best$sigma_nmad)}); baseline RMSE {sprintf('%.4f', baseline_rmse)}."
))

# --- F15: residuals vs redshift ----------------------------------------------

f15 <- ggplot(pred_long, aes(z_spec, dz)) +
  geom_hline(yintercept = 0) +
  geom_smooth(method = "loess", formula = y ~ x, se = FALSE,
              colour = "grey30", linewidth = 0.8) +
  geom_point(aes(colour = model), size = 2, alpha = 0.85, show.legend = FALSE) +
  facet_wrap(~model, labeller = as_labeller(MODEL_LABELS)) +
  scale_colour_manual(values = MODEL_COLOURS) +
  labs(x = "Spectroscopic redshift  z_spec", y = "Δz / (1 + z)  =  (z_phot − z_spec)/(1 + z_spec)",
       title = "Normalised residuals versus redshift (test set)") +
  theme_report()
save_fig(f15, "F15", "residuals_vs_z", 7, 5)
add_caption("F15", glue(
  "Normalised residuals Δz/(1 + z) versus spectroscopic redshift for each model ",
  "on the test set, with a LOESS trend. A trend from positive at low z to ",
  "negative at high z means predictions are pulled towards the mean redshift."
))

# --- F16: residual distributions ---------------------------------------------

f16 <- ggplot(pred_long, aes(dz, fill = model, colour = model)) +
  geom_histogram(aes(y = after_stat(density)), bins = 10, alpha = 0.35) +
  geom_density(fill = NA, linewidth = 0.9) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  facet_wrap(~model, labeller = as_labeller(MODEL_LABELS)) +
  scale_fill_manual(values = MODEL_COLOURS, guide = "none") +
  scale_colour_manual(values = MODEL_COLOURS, guide = "none") +
  labs(x = "Δz / (1 + z)", y = "Density",
       title = "Distribution of normalised residuals (test set)") +
  theme_report()
save_fig(f16, "F16", "residual_dist", 7, 5)
add_caption("F16", glue(
  "Distributions of the normalised residual Δz/(1 + z) on the {nrow(test)} test ",
  "galaxies for each model (histogram and kernel density); the dashed line is zero."
))

# --- F17: model comparison ---------------------------------------------------

f17 <- ggplot(learners, aes(factor(model, levels = model_ids), rmse, colour = model)) +
  geom_hline(yintercept = baseline_rmse, linetype = "dashed") +
  # Label sits between two models so it never touches an error bar
  annotate("text", x = 1.5, y = baseline_rmse, label = "M0 baseline",
           vjust = -0.5, size = 3.3) +
  geom_errorbar(aes(ymin = rmse_lo, ymax = rmse_hi), width = 0.15, linewidth = 0.9) +
  geom_point(size = 3.5) +
  scale_colour_manual(values = MODEL_COLOURS, guide = "none") +
  scale_x_discrete(labels = MODEL_LABELS) +
  labs(x = NULL, y = "Test RMSE (95% bootstrap CI)",
       title = "Test-set RMSE by model") +
  theme_report()
save_fig(f17, "F17", "model_comparison", 6.5, 4.5)
add_caption("F17", glue(
  "Test-set RMSE for each model with 95% percentile bootstrap confidence ",
  "intervals ({N_BOOT} resamples of the {nrow(test)} test galaxies). The dashed ",
  "line is the mean-prediction baseline (RMSE {sprintf('%.4f', baseline_rmse)})."
))

# --- Summary -----------------------------------------------------------------

message("\nTest-set metrics (n = ", nrow(test), "):")
print(as.data.frame(select(t05, label, rmse, rmse_lo, rmse_hi, r2, bias, sigma_nmad, eta)),
      digits = 3)

beats <- learners$label[learners$rmse < baseline_rmse]
message(glue(
  "\nBest learner by test RMSE: {best$label}. ",
  "Learners beating the baseline: {length(beats)} of {nrow(learners)}."
))

# Largest test errors: shows whether a few galaxies dominate the RMSE
message("\nLargest |Δz| per learner:")
pred_long |>
  filter(model != "M0_baseline") |>
  group_by(model) |>
  slice_max(abs(dz), n = 2) |>
  ungroup() |>
  select(model, objid, z_spec, z_phot, dz) |>
  as.data.frame() |>
  print(digits = 3)
