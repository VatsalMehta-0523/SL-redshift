# =============================================================================
# 05_train.R — Workflow step 5: train supervised learning models
# Inputs : data/processed/train.csv
#          (data/processed/test.csv only for the learning curves, after all
#           hyperparameters are frozen: D-016)
# Outputs: outputs/models/{M0..M4}.rds,
#          outputs/tables/T03_hyperparameters, T04_cv_metrics,
#          outputs/tables/learning_curves.csv,
#          outputs/figures/F08–F13 (.png + .pdf), captions.md
# Brief  : TASK.md §4, step 5; decisions D-008, D-010, D-014, D-016
# =============================================================================

source(here::here("R", "00_setup.R"))
suppressPackageStartupMessages(library(caret))

train <- read_csv(PATHS$train, col_types = RAW_COL_TYPES, progress = FALSE)

FORMULA <- redshift ~ u_g + g_r + r_i + i_z + r # D-006

# --- Cross-validation set-up (D-010) -----------------------------------------

# One fixed set of 25 resamples (5-fold CV repeated 5 times). Every model uses
# exactly these folds, so differences between models are not due to luck in
# how the folds were drawn.
set.seed(SEED)
cv_index <- createMultiFolds(train$redshift, k = 5, times = 5)

# Same metric definitions as the test-set evaluation (utils_metrics.R).
# caret's default R² is the squared correlation; we use 1 − SS_res/SS_tot,
# which can be negative for a model worse than the mean.
photoz_summary <- function(data, lev = NULL, model = NULL) {
  c(
    RMSE     = rmse(data$pred, data$obs),
    Rsquared = r2(data$pred, data$obs),
    MAE      = mae(data$pred, data$obs)
  )
}

cv_control <- trainControl(
  method = "repeatedcv", number = 5, repeats = 5,
  index = cv_index, savePredictions = "final",
  summaryFunction = photoz_summary
)

# --- Model specifications (D-008) --------------------------------------------

SVR_C <- 2^(-2:6)
SVR_SIGMA <- c(0.01, 0.05, 0.1, 0.5, 1)

MODEL_SPECS <- list(
  # Predicts the training-set mean redshift: the floor every model must beat
  M0_baseline = list(method = "null"),
  # Standardised inputs make the coefficients comparable (used in T06)
  M1_lm = list(method = "lm", preProcess = c("center", "scale")),
  # Distances need features on the same scale
  M2_knn = list(
    method = "knn", preProcess = c("center", "scale"),
    tuneGrid = data.frame(k = 1:20)
  ),
  # Trees are scale-free, so no preprocessing
  M3_rf = list(
    method = "rf", tuneGrid = data.frame(mtry = 1:5),
    extra = list(ntree = 500, importance = TRUE)
  ),
  M4_svr = list(
    method = "svmRadial", preProcess = c("center", "scale"),
    tuneGrid = expand.grid(sigma = SVR_SIGMA, C = SVR_C)
  )
)

#' Fit one model with caret. tune_grid overrides the spec's grid; the learning
#' curves pass the frozen best values here.
fit_model <- function(spec, data, control, tune_grid = spec$tuneGrid) {
  args <- c(
    list(form = FORMULA, data = data, method = spec$method,
         trControl = control, metric = "RMSE"),
    if (!is.null(tune_grid)) list(tuneGrid = tune_grid),
    if (!is.null(spec$preProcess)) list(preProcess = spec$preProcess),
    spec$extra
  )
  do.call(caret::train, args)
}

# --- Train and tune ----------------------------------------------------------

models <- list()
for (id in names(MODEL_SPECS)) {
  message("Training ", MODEL_LABELS[id], " ...")
  set.seed(SEED) # same RNG state for every model (e.g. RF bootstrap samples)
  models[[id]] <- fit_model(MODEL_SPECS[[id]], train, cv_control)
  saveRDS(models[[id]], file.path(PATHS$models, paste0(id, ".rds")))
}

# --- T03: hyperparameters ----------------------------------------------------

best <- map(models, "bestTune")
t03 <- tibble::tribble(
  ~model, ~parameter, ~search_grid, ~selected,
  "M0_baseline", "(none)", "predicts the training mean", "—",
  "M1_lm", "(none)", "ordinary least squares", "—",
  "M2_knn", "k", "1, 2, …, 20", as.character(best$M2_knn$k),
  "M3_rf", "mtry", "1, 2, …, 5", as.character(best$M3_rf$mtry),
  "M3_rf", "ntree", "fixed", "500",
  "M4_svr", "C", "2^-2, 2^-1, …, 2^6", as.character(best$M4_svr$C),
  "M4_svr", "sigma", paste(SVR_SIGMA, collapse = ", "), as.character(best$M4_svr$sigma)
) |>
  mutate(label = MODEL_LABELS[model], .after = model)
save_table(t03, "T03", "hyperparameters")

# --- T04: cross-validation metrics -------------------------------------------

cv_resamples <- imap_dfr(models, \(m, id) mutate(m$resample, model = id))
stopifnot("Every model must have 25 CV resamples" =
            all(count(cv_resamples, model)$n == 25))

t04 <- cv_resamples |>
  group_by(model) |>
  summarise(
    resamples = n(),
    rmse_mean = mean(RMSE), rmse_sd = sd(RMSE),
    r2_mean = mean(Rsquared), r2_sd = sd(Rsquared),
    mae_mean = mean(MAE), mae_sd = sd(MAE),
    .groups = "drop"
  ) |>
  mutate(label = MODEL_LABELS[model], .after = model)
save_table(t04, "T04", "cv_metrics")

# --- F08: k-NN tuning --------------------------------------------------------

knn_res <- models$M2_knn$results
f08 <- ggplot(knn_res, aes(k, RMSE)) +
  geom_ribbon(aes(ymin = RMSE - RMSESD, ymax = RMSE + RMSESD),
              fill = MODEL_COLOURS["M2_knn"], alpha = 0.2) +
  geom_line(colour = MODEL_COLOURS["M2_knn"], linewidth = 1) +
  geom_point(colour = MODEL_COLOURS["M2_knn"]) +
  geom_vline(xintercept = best$M2_knn$k, linetype = "dashed") +
  annotate("text", x = best$M2_knn$k, y = Inf, label = glue("chosen k = {best$M2_knn$k}"),
           hjust = -0.1, vjust = 1.5, size = 3.4) +
  scale_x_continuous(breaks = seq(0, 20, 2)) +
  labs(x = "Number of neighbours  k", y = "CV RMSE (mean ± 1 SD)",
       title = "k-NN: cross-validated error versus k") +
  theme_report()
save_fig(f08, "F08", "knn_tuning", 6.5, 4.5)
add_caption("F08", glue(
  "k-NN tuning: mean CV RMSE over 25 resamples (5-fold × 5) versus k, with a ",
  "±1 SD band. The chosen k = {best$M2_knn$k} has the lowest mean RMSE ",
  "({sprintf('%.4f', min(knn_res$RMSE))})."
))

# --- F09: random-forest OOB convergence --------------------------------------

oob <- tibble::tibble(trees = seq_along(models$M3_rf$finalModel$mse),
                      mse = models$M3_rf$finalModel$mse)
f09 <- ggplot(oob, aes(trees, mse)) +
  geom_line(colour = MODEL_COLOURS["M3_rf"], linewidth = 0.9) +
  labs(x = "Number of trees", y = "Out-of-bag MSE",
       title = glue("Random forest: OOB error versus number of trees (mtry = {best$M3_rf$mtry})")) +
  theme_report()
save_fig(f09, "F09", "rf_oob_vs_trees", 6.5, 4.5)
add_caption("F09", glue(
  "Out-of-bag mean squared error of the final random forest (mtry = ",
  "{best$M3_rf$mtry}, 80 training galaxies) as trees are added. The curve is ",
  "flat well before 500 trees, so 500 is enough."
))

# --- F10: random-forest mtry tuning ------------------------------------------

rf_res <- models$M3_rf$results
f10 <- ggplot(rf_res, aes(mtry, RMSE)) +
  geom_errorbar(aes(ymin = RMSE - RMSESD, ymax = RMSE + RMSESD), width = 0.15,
                colour = MODEL_COLOURS["M3_rf"]) +
  geom_line(colour = MODEL_COLOURS["M3_rf"], linewidth = 1) +
  geom_point(aes(shape = mtry == best$M3_rf$mtry), size = 3,
             colour = MODEL_COLOURS["M3_rf"], show.legend = FALSE) +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 8)) +
  labs(x = "Features tried at each split  mtry", y = "CV RMSE (mean ± 1 SD)",
       title = "Random forest: cross-validated error versus mtry") +
  theme_report()
save_fig(f10, "F10", "rf_mtry_tuning", 6.5, 4.5)
add_caption("F10", glue(
  "Random-forest tuning: mean CV RMSE (±1 SD, 25 resamples) versus mtry. ",
  "The star marks the chosen mtry = {best$M3_rf$mtry}."
))

# --- F11: SVR tuning heatmap -------------------------------------------------

svr_res <- models$M4_svr$results |>
  mutate(C_lab = factor(glue("2^{log2(C)}"), levels = glue("2^{log2(SVR_C)}")),
         sigma_lab = factor(sigma))
svr_best <- filter(svr_res, sigma == best$M4_svr$sigma, C == best$M4_svr$C)

f11 <- ggplot(svr_res, aes(C_lab, sigma_lab, fill = RMSE)) +
  geom_tile(colour = "white") +
  # White labels on the dark (high-RMSE) cells so every value is readable
  geom_text(aes(label = sprintf("%.3f", RMSE),
                colour = RMSE > mean(range(RMSE))), size = 2.6, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "black")) +
  geom_tile(data = svr_best, fill = NA, colour = "black", linewidth = 1.2) +
  scale_fill_viridis_c(option = "magma", direction = -1, name = "CV RMSE") +
  labs(x = "Cost  C", y = "RBF kernel width  σ",
       title = "SVR: cross-validated RMSE over the C × σ grid") +
  theme_report() +
  theme(panel.grid = element_blank(), legend.position = "right")
save_fig(f11, "F11", "svr_tuning_heatmap", 7, 4.5)
add_caption("F11", glue(
  "SVR (RBF kernel) tuning: mean CV RMSE for each (C, σ) pair. The outlined ",
  "cell is the chosen C = {best$M4_svr$C}, σ = {best$M4_svr$sigma}."
))

# --- F12: learning curves (D-016) --------------------------------------------

# Hyperparameters are frozen above. Each model is refit on random subsets of
# the training set; the test set is only used to score these refits and
# influences no modelling choice.
test <- read_csv(PATHS$test, col_types = RAW_COL_TYPES, progress = FALSE)
LC_SIZES <- seq(20, 80, by = 10)
LC_REPEATS <- 20
no_resampling <- trainControl(method = "none")

message("Learning curves: ", length(LC_SIZES) * LC_REPEATS * length(models), " refits ...")
set.seed(SEED)
learning <- map_dfr(LC_SIZES, \(size) {
  map_dfr(seq_len(LC_REPEATS), \(rep) {
    subset <- slice_sample(train, n = size)
    map_dfr(names(MODEL_SPECS), \(id) {
      fit <- fit_model(MODEL_SPECS[[id]], subset, no_resampling,
                       tune_grid = models[[id]]$bestTune)
      tibble::tibble(
        model = id, size = size, rep = rep,
        train_rmse = rmse(predict(fit, subset), subset$redshift),
        test_rmse = rmse(predict(fit, test), test$redshift)
      )
    })
  })
})
write_csv(learning, file.path(PATHS$tables, "learning_curves.csv"))

lc_summary <- learning |>
  pivot_longer(c(train_rmse, test_rmse), names_to = "set", values_to = "rmse") |>
  group_by(model, size, set) |>
  summarise(mean = mean(rmse), sd = sd(rmse), .groups = "drop") |>
  mutate(
    set = factor(set, levels = c("train_rmse", "test_rmse"),
                 labels = c("Training subset", "Test set")),
    model = factor(model, levels = names(MODEL_SPECS), labels = MODEL_LABELS[names(MODEL_SPECS)])
  )

f12 <- ggplot(lc_summary, aes(size, mean, colour = set, fill = set)) +
  geom_ribbon(aes(ymin = mean - sd, ymax = mean + sd), alpha = 0.2, colour = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.5) +
  facet_wrap(~model) +
  scale_colour_manual(values = unname(OKABE_ITO[c("blue", "vermillion")]), name = NULL) +
  scale_fill_manual(values = unname(OKABE_ITO[c("blue", "vermillion")]), name = NULL) +
  scale_x_continuous(breaks = LC_SIZES) +
  labs(x = "Training-set size (galaxies)", y = "RMSE (mean ± 1 SD)",
       title = "Learning curves with frozen hyperparameters") +
  theme_report()
save_fig(f12, "F12", "learning_curves", 7, 5)
add_caption("F12", glue(
  "Learning curves: mean training and test RMSE (±1 SD over {LC_REPEATS} random ",
  "subsets) versus training-set size, for each model with its tuned ",
  "hyperparameters frozen."
))

# --- F13: CV RMSE distribution per model -------------------------------------

cv_plot <- cv_resamples |>
  mutate(model = factor(model, levels = names(MODEL_SPECS)))
f13 <- ggplot(cv_plot, aes(model, RMSE, colour = model)) +
  geom_boxplot(outlier.shape = NA, width = 0.6) +
  geom_jitter(width = 0.12, alpha = 0.6, size = 1.4) +
  scale_colour_manual(values = MODEL_COLOURS, guide = "none") +
  scale_x_discrete(labels = MODEL_LABELS) +
  labs(x = NULL, y = "CV RMSE per resample",
       title = "Cross-validated RMSE over 25 resamples") +
  theme_report()
save_fig(f13, "F13", "cv_rmse_boxplot", 6.5, 4.5)

best_cv <- t04 |> filter(model != "M0_baseline") |> slice_min(rmse_mean, n = 1)
add_caption("F13", glue(
  "Distribution of CV RMSE over the same 25 resamples (5-fold × 5) for each ",
  "model. Lowest mean CV RMSE: {best_cv$label} ",
  "({sprintf('%.4f', best_cv$rmse_mean)}); baseline ",
  "{sprintf('%.4f', t04$rmse_mean[t04$model == 'M0_baseline'])}."
))

# --- Summary -----------------------------------------------------------------

message("\nCross-validation results (25 resamples, training set only):")
print(as.data.frame(select(t04, label, rmse_mean, rmse_sd, r2_mean, mae_mean)), digits = 4)
