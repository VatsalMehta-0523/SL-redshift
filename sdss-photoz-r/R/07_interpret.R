# =============================================================================
# 07_interpret.R — Workflow step 7: interpret the results physically
# Inputs : outputs/models/M1_lm.rds, M3_rf.rds, data/processed/train.csv,
#          data/processed/test.csv, outputs/tables/T04, T05, test_predictions
# Outputs: outputs/tables/T06_feature_importance.csv/.md,
#          outputs/tables/interpretation_notes.md,
#          outputs/figures/F18–F19 (.png + .pdf), captions.md
# Brief  : TASK.md §4, step 7; README §3.6 hypotheses H1–H4
# =============================================================================
#
# The physics story under test (README §3): the 4000 Å break moves through the
# g band as z grows, so g − r should redden with z and be the top predictor
# (H1, H2); r magnitude helps because more distant galaxies look fainter.
# Every statement in interpretation_notes.md is computed here from the saved
# models and tables, so the report never relies on typed-in numbers (R7).

source(here::here("R", "00_setup.R"))
suppressPackageStartupMessages({
  library(caret)
  library(randomForest)
})

train <- read_csv(PATHS$train, col_types = RAW_COL_TYPES, progress = FALSE)
test <- read_csv(PATHS$test, col_types = RAW_COL_TYPES, progress = FALSE)
t04 <- read_csv(file.path(PATHS$tables, "T04_cv_metrics.csv"), show_col_types = FALSE)
t05 <- read_csv(file.path(PATHS$tables, "T05_test_metrics.csv"), show_col_types = FALSE)
preds <- read_csv(file.path(PATHS$tables, "test_predictions.csv"),
                  col_types = RAW_COL_TYPES, show_col_types = FALSE)

lm_fit <- readRDS(file.path(PATHS$models, "M1_lm.rds"))
rf_fit <- readRDS(file.path(PATHS$models, "M3_rf.rds"))

FEATURES <- c("u_g", "g_r", "r_i", "i_z", "r")
FEATURE_LABELS <- c(COLOUR_LABELS, r = "r (mag)")

# --- T06: feature importance -------------------------------------------------

# Random forest: permutation importance (%IncMSE) = how much the out-of-bag
# error grows when one feature is shuffled, so larger = more important.
rf_imp <- importance(rf_fit$finalModel, type = 1, scale = TRUE)
rf_imp <- tibble::tibble(feature = rownames(rf_imp), rf_inc_mse = rf_imp[, 1])

# Linear model: inputs were centred and scaled inside caret, so each
# coefficient is the change in predicted z per 1 SD of that feature.
lm_coef <- coef(summary(lm_fit$finalModel))
lm_ci <- confint(lm_fit$finalModel, level = 0.95)
lm_tab <- tibble::tibble(
  feature = rownames(lm_coef),
  lm_std_coef = lm_coef[, "Estimate"],
  lm_ci_lo = lm_ci[, 1], lm_ci_hi = lm_ci[, 2],
  lm_p_value = lm_coef[, "Pr(>|t|)"]
) |>
  filter(feature %in% FEATURES)

t06 <- rf_imp |>
  left_join(lm_tab, by = "feature") |>
  mutate(
    label = FEATURE_LABELS[feature], .after = feature
  ) |>
  mutate(
    rf_rank = rank(-rf_inc_mse),
    lm_rank = rank(-abs(lm_std_coef))
  ) |>
  arrange(rf_rank)
save_table(t06, "T06", "feature_importance")

# --- F18: feature importance (RF and LM side by side) -----------------------

feature_order <- t06$label[order(t06$rf_inc_mse)] # least -> most important

f18_rf <- ggplot(t06, aes(rf_inc_mse, factor(label, levels = feature_order))) +
  geom_col(fill = MODEL_COLOURS["M3_rf"], width = 0.6) +
  labs(x = "Permutation importance (%IncMSE)", y = NULL, title = "Random forest") +
  theme_report()

f18_lm <- ggplot(t06, aes(lm_std_coef, factor(label, levels = feature_order))) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = lm_ci_lo, xmax = lm_ci_hi), width = 0.2,
                colour = MODEL_COLOURS["M1_lm"], orientation = "y") +
  geom_point(size = 3, colour = MODEL_COLOURS["M1_lm"]) +
  labs(x = "Standardised coefficient (Δz per 1 SD, 95% CI)", y = NULL,
       title = "Linear regression") +
  theme_report()

f18 <- patchwork::wrap_plots(f18_rf, f18_lm, nrow = 1) +
  patchwork::plot_annotation(
    title = "Which features drive the redshift predictions?",
    theme = theme(plot.title = element_text(face = "bold", size = 13))
  )
save_fig(f18, "F18", "feature_importance", 8, 4.5)

top_rf <- t06$feature[t06$rf_rank == 1]
top_lm <- t06$feature[t06$lm_rank == 1]
add_caption("F18", glue(
  "Feature importance. Left: random-forest permutation importance (%IncMSE). ",
  "Right: standardised linear-regression coefficients with 95% CIs (change in ",
  "predicted z per 1 SD of each feature). Most important: ",
  "{FEATURE_LABELS[top_rf]} (RF) and {FEATURE_LABELS[top_lm]} (LM)."
))

# --- F19: partial dependence of the RF on g − r and r − i --------------------

# Partial dependence = the forest's average prediction as one feature is
# swept over its range, with the other features kept at their observed values.
# Computed on the training data only.
pd_data <- as.data.frame(train[FEATURES])
pd <- map_dfr(c("g_r", "r_i"), \(v) {
  p <- pdp::partial(rf_fit$finalModel, pred.var = v, train = pd_data,
                    grid.resolution = 40)
  tibble::tibble(feature = v, x = p[[v]], yhat = p$yhat)
})

# H2: does predicted z rise with g − r? Spearman correlation of the PD curve
pd_rho <- pd |>
  group_by(feature) |>
  summarise(rho = cor(x, yhat, method = "spearman"),
            rise = max(yhat) - min(yhat), .groups = "drop")
rho_gr <- pd_rho$rho[pd_rho$feature == "g_r"]

rugs <- train |>
  select(g_r, r_i) |>
  pivot_longer(everything(), names_to = "feature", values_to = "x")

facet_labels <- as_labeller(c(
  g_r = glue("g − r  (Spearman ρ = {sprintf('%.2f', pd_rho$rho[pd_rho$feature == 'g_r'])})"),
  r_i = glue("r − i  (Spearman ρ = {sprintf('%.2f', pd_rho$rho[pd_rho$feature == 'r_i'])})")
))

f19 <- ggplot(pd, aes(x, yhat)) +
  geom_line(colour = MODEL_COLOURS["M3_rf"], linewidth = 1.1) +
  geom_rug(data = rugs, aes(x = x), inherit.aes = FALSE, alpha = 0.5) +
  facet_wrap(~feature, scales = "free_x", labeller = facet_labels) +
  labs(x = "Colour (mag)", y = "Partial dependence: predicted z",
       title = "Random forest: predicted redshift versus colour") +
  theme_report()
save_fig(f19, "F19", "partial_dependence", 7, 4)
add_caption("F19", glue(
  "Partial dependence of the random-forest redshift prediction on g − r and ",
  "r − i (training data; rugs show the observed values). Over the observed ",
  "range, predicted z changes by {sprintf('%.3f', pd_rho$rise[pd_rho$feature == 'g_r'])} ",
  "with g − r (Spearman ρ = {sprintf('%.2f', rho_gr)})."
))

# --- interpretation_notes.md -------------------------------------------------

fmt <- \(x, d = 4) formatC(x, format = "f", digits = d)
yes_no <- \(x) if (isTRUE(x)) "**supported**" else "**not supported**"

learners <- c("M1_lm", "M2_knn", "M3_rf", "M4_svr")
nonlinear <- c("M2_knn", "M3_rf", "M4_svr")
cv <- set_names(t04$rmse_mean, t04$model)
te <- set_names(t05$rmse, t05$model)

h1 <- top_rf == "g_r" && top_lm == "g_r"
h1_partial <- xor(top_rf == "g_r", top_lm == "g_r")
h2 <- rho_gr > 0.8
#' "supported" if every non-linear model beats LM, "partly" if some do
h3_verdict <- function(rmse) {
  winners <- nonlinear[rmse[nonlinear] < rmse["M1_lm"]]
  if (length(winners) == length(nonlinear)) return("**supported**")
  if (length(winners) == 0) return("**not supported**")
  glue("**partly supported** (only {paste(MODEL_LABELS[winners], collapse = ', ')} beat LM)")
}
h4_cv <- all(cv[learners] < cv["M0_baseline"])
h4_test <- all(te[learners] < te["M0_baseline"])

r_row <- t06[t06$feature == "r", ]
ug_row <- t06[t06$feature == "u_g", ]
ug_cor <- cor(train$u_g, train$redshift) # marginal correlation (training set)
neg_preds <- preds |>
  pivot_longer(all_of(learners), names_to = "model", values_to = "z_phot") |>
  filter(z_phot < 0)
# Test galaxies with any feature outside the range seen in training
out_of_range <- map(FEATURES, \(f) {
  test[[f]] < min(train[[f]]) | test[[f]] > max(train[[f]])
})
outside_n <- sum(Reduce(`|`, out_of_range))

rank_list <- glue_collapse(glue(
  "{t06$rf_rank}. {t06$label} (%IncMSE {fmt(t06$rf_inc_mse, 1)})"
), sep = "; ")

notes <- c(
  "# Interpretation notes (auto-generated by R/07_interpret.R)",
  "",
  "Facts for the Discussion section. Every number is computed from the saved",
  "models and the tables in `outputs/tables/`. Do not edit by hand.",
  "",
  "## Feature importance (T06, F18)",
  "",
  glue("- Random-forest ranking: {rank_list}."),
  glue("- Most important feature: {FEATURE_LABELS[top_rf]} (random forest), ",
       "{FEATURE_LABELS[top_lm]} (largest |standardised coefficient| in the linear model)."),
  glue("- r magnitude: RF rank {r_row$rf_rank} of {nrow(t06)}; LM coefficient ",
       "{fmt(r_row$lm_std_coef)} [95% CI {fmt(r_row$lm_ci_lo)}, {fmt(r_row$lm_ci_hi)}]",
       "{if (r_row$lm_ci_lo > 0) ': positive, so fainter galaxies are predicted at higher z, as the inverse-square law expects' else ''}."),
  glue("- u − g: {if (abs(ug_cor) < 0.2) 'almost no' else 'some'} correlation with z ",
       "on its own (training r = {fmt(ug_cor, 2)}) ",
       "but RF rank {ug_row$rf_rank} and LM coefficient {fmt(ug_row$lm_std_coef)} ",
       "[{fmt(ug_row$lm_ci_lo)}, {fmt(ug_row$lm_ci_hi)}] at fixed g − r. ",
       "Interpretation: u − g traces galaxy type (old/red vs star-forming/blue), ",
       "which lets the models tell an intrinsically red galaxy from one reddened ",
       "by redshift in g − r."),
  "- The colours are strongly correlated with each other (F05), so individual",
  "  linear coefficients can trade off against each other; their CIs are wide.",
  "",
  "## Hypotheses (README §3.6)",
  "",
  glue("- **H1** (g − r is the most important predictor): ",
       "{if (h1) '**supported** by both RF and LM' else if (h1_partial) '**partly supported** (only one of RF / LM ranks it first)' else '**not supported**'}."),
  glue("- **H2** (predicted z rises monotonically with g − r): {yes_no(h2)}. ",
       "Spearman ρ of the RF partial-dependence curve = {fmt(rho_gr, 2)} (threshold 0.8)."),
  glue("- **H3** (non-linear models beat linear regression): ",
       "CV {h3_verdict(cv)}; test {h3_verdict(te)}. ",
       "CV RMSE: LM {fmt(cv['M1_lm'])}, k-NN {fmt(cv['M2_knn'])}, RF {fmt(cv['M3_rf'])}, SVR {fmt(cv['M4_svr'])}. ",
       "Test RMSE: LM {fmt(te['M1_lm'])}, k-NN {fmt(te['M2_knn'])}, RF {fmt(te['M3_rf'])}, SVR {fmt(te['M4_svr'])}."),
  glue("- **H4** (all models beat the mean baseline): CV {yes_no(h4_cv)}, ",
       "test {yes_no(h4_test)} (point estimates; baseline CV {fmt(cv['M0_baseline'])}, ",
       "test {fmt(te['M0_baseline'])}). The test CIs in T05 overlap the baseline for ",
       "{sum(t05$rmse_hi[t05$model %in% learners] > te['M0_baseline'])} of 4 learners."),
  "",
  "## Physics of the sample",
  "",
  glue("- Test galaxies with at least one feature outside the training range: ",
       "{outside_n} of {nrow(test)}."),
  glue("- Negative (unphysical) test predictions: {nrow(neg_preds)}",
       "{if (nrow(neg_preds) > 0) paste0(' (', paste(unique(MODEL_LABELS[neg_preds$model]), collapse = ', '), ')') else ''}. ",
       "Linear and kernel models can extrapolate beyond the training redshifts; ",
       "random-forest predictions are averages of training redshifts and cannot."),
  glue("- Over this sample's redshift range ({fmt(min(train$redshift, test$redshift), 3)}–",
       "{fmt(max(train$redshift, test$redshift), 3)}) the 4000 Å break stays inside the ",
       "g band (F20), so the redshift signal is the break moving *within* g, which ",
       "reddens g − r.")
)
writeLines(notes, file.path(PATHS$tables, "interpretation_notes.md"))
cat(notes, sep = "\n")
