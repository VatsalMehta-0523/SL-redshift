# =============================================================================
# 09_compare_versions.R — Does training on 20 more galaxies help? (v1 vs v2)
# Inputs : outputs/v1/ and outputs/v2/ tables (T03, T04, T05, test_predictions,
#          learning_curves), data/processed/v1/ and v2/ (train, test)
# Outputs: outputs/comparison/tables/T07_version_comparison.csv/.md,
#          outputs/comparison/tables/T08_hyperparameter_drift.csv/.md,
#          outputs/comparison/tables/comparison_notes.md,
#          outputs/comparison/figures/F21_version_comparison, F22_learning_curves_v1_v2,
#          outputs/comparison/figures/captions.md
# Brief  : TASK.md §4, steps 6–7 (evaluation, interpretation); decision D-018
# =============================================================================
#
# Design: v1 and v2 are scored on the SAME 20 held-out test galaxies, so the
# comparison is paired. The uncertainty of the change in test RMSE comes from a
# paired bootstrap: resample the 20 galaxies once and recompute RMSE for both
# versions on that resample. This cancels the galaxy-to-galaxy variation that
# dominates each version's own CI (T05), so it is much tighter than comparing
# the two separate CIs.
#
# Nothing here feeds back into any model. It only reads saved outputs.

source(here::here("R", "00_setup.R"))

COMP <- PATHS$comparison
PATHS$figures <- file.path(COMP, "figures") # save_fig() / add_caption() target
PATHS$tables <- file.path(COMP, "tables") # save_table() target
for (d in PATHS[c("figures", "tables")]) dir.create(d, recursive = TRUE, showWarnings = FALSE)

N_BOOT <- 2000 # same as D-011
LEARNERS <- c("M1_lm", "M2_knn", "M3_rf", "M4_svr")
ALL <- c("M0_baseline", LEARNERS)

vp <- map(set_names(names(VERSIONS)), version_paths)
read_tab <- \(v, name, ...) read_csv(file.path(vp[[v]]$tables, name), show_col_types = FALSE, ...)
read_data <- \(v, which) read_csv(vp[[v]][[which]], col_types = RAW_COL_TYPES, progress = FALSE)

t05 <- map(set_names(names(VERSIONS)), \(v) read_tab(v, "T05_test_metrics.csv"))
t04 <- map(set_names(names(VERSIONS)), \(v) read_tab(v, "T04_cv_metrics.csv"))
t03 <- map(set_names(names(VERSIONS)), \(v) read_tab(v, "T03_hyperparameters.csv"))
preds <- map(set_names(names(VERSIONS)), \(v) {
  read_tab(v, "test_predictions.csv", col_types = RAW_COL_TYPES) |> arrange(objid)
})
train <- map(set_names(names(VERSIONS)), \(v) read_data(v, "train"))
test <- map(set_names(names(VERSIONS)), \(v) read_data(v, "test"))

stopifnot(
  "v1 and v2 must share the same test galaxies (D-018)" =
    identical(preds$v1$objid, preds$v2$objid),
  "the true redshifts must be identical" = identical(preds$v1$z_spec, preds$v2$z_spec),
  "v2 training set must contain v1's" = all(train$v1$objid %in% train$v2$objid)
)
z <- preds$v1$z_spec
new_ids <- read_csv(file.path(vp$v2$processed, "new_galaxies.csv"), col_types = "c")$objid
new_gal <- filter(train$v2, objid %in% new_ids)

# --- T07: paired comparison on the shared test set ---------------------------

set.seed(SEED)
boot_idx <- replicate(N_BOOT, sample.int(length(z), replace = TRUE), simplify = FALSE)

paired <- map_dfr(ALL, \(id) {
  p1 <- preds$v1[[id]]
  p2 <- preds$v2[[id]]
  boot_d_rmse <- map_dbl(boot_idx, \(i) rmse(p2[i], z[i]) - rmse(p1[i], z[i]))
  boot_d_nmad <- map_dbl(boot_idx, \(i) sigma_nmad(p2[i], z[i]) - sigma_nmad(p1[i], z[i]))
  # Per-galaxy view: how many of the 20 test galaxies got closer to the truth?
  closer <- sum(abs(p2 - z) < abs(p1 - z))
  tibble::tibble(
    model = id, label = MODEL_LABELS[[id]], n_test = length(z),
    rmse_v1 = rmse(p1, z), rmse_v2 = rmse(p2, z),
    d_rmse = rmse(p2, z) - rmse(p1, z),
    d_rmse_lo = unname(quantile(boot_d_rmse, 0.025)), d_rmse_hi = unname(quantile(boot_d_rmse, 0.975)),
    p_improved = mean(boot_d_rmse < 0),
    pct_change = 100 * (rmse(p2, z) / rmse(p1, z) - 1),
    sigma_nmad_v1 = sigma_nmad(p1, z), sigma_nmad_v2 = sigma_nmad(p2, z),
    d_sigma_nmad = sigma_nmad(p2, z) - sigma_nmad(p1, z),
    d_sigma_nmad_lo = unname(quantile(boot_d_nmad, 0.025)),
    d_sigma_nmad_hi = unname(quantile(boot_d_nmad, 0.975)),
    r2_v1 = r2(p1, z), r2_v2 = r2(p2, z),
    bias_v1 = bias(p1, z), bias_v2 = bias(p2, z),
    galaxies_closer = closer,
    cv_rmse_v1 = t04$v1$rmse_mean[t04$v1$model == id],
    cv_rmse_v2 = t04$v2$rmse_mean[t04$v2$model == id]
  )
})
save_table(paired, "T07", "version_comparison")

# --- T08: did the tuned hyperparameters move? --------------------------------

t08 <- t03$v1 |>
  select(model, label, parameter, search_grid, selected_v1 = selected) |>
  left_join(select(t03$v2, model, parameter, selected_v2 = selected),
            by = c("model", "parameter")) |>
  mutate(changed = selected_v1 != selected_v2)
save_table(t08, "T08", "hyperparameter_drift")

# --- F21: test RMSE v1 -> v2 and the paired change ---------------------------

learn <- filter(paired, model %in% LEARNERS) |>
  mutate(model = factor(model, levels = LEARNERS))
ci <- bind_rows(
  t05$v1 |> mutate(version = "v1"),
  t05$v2 |> mutate(version = "v2")
) |>
  filter(model %in% LEARNERS) |>
  mutate(model = factor(model, levels = LEARNERS),
         version = factor(version, levels = c("v1", "v2"),
                          labels = c(glue("v1: {VERSIONS$v1$n_train} training galaxies"),
                                     glue("v2: {VERSIONS$v2$n_train} training galaxies"))))
version_cols <- set_names(unname(OKABE_ITO[c("sky_blue", "vermillion")]), levels(ci$version))
base_rmse <- paired$rmse_v1[paired$model == "M0_baseline"]

f21_a <- ggplot(ci, aes(model, rmse, colour = version)) +
  geom_hline(yintercept = base_rmse, linetype = "dashed") +
  annotate("text", x = 0.6, y = base_rmse, label = "M0 baseline", hjust = 0,
           vjust = -0.5, size = 3.1) +
  geom_errorbar(aes(ymin = rmse_lo, ymax = rmse_hi), width = 0.2, linewidth = 0.8,
                position = position_dodge(width = 0.5)) +
  geom_point(size = 3, position = position_dodge(width = 0.5)) +
  scale_colour_manual(values = version_cols, name = NULL) +
  scale_x_discrete(labels = MODEL_LABELS) +
  labs(x = NULL, y = "Test RMSE (95% bootstrap CI)", title = "Test RMSE per version") +
  theme_report() +
  theme(axis.text.x = element_text(angle = 15, hjust = 1))

f21_b <- ggplot(learn, aes(d_rmse, model, colour = model)) +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_errorbar(aes(xmin = d_rmse_lo, xmax = d_rmse_hi), width = 0.2, linewidth = 0.9,
                orientation = "y") +
  geom_point(size = 3.2) +
  geom_text(aes(label = sprintf("P(better) = %.2f", p_improved)), vjust = -1.1, size = 2.9,
            show.legend = FALSE) +
  scale_colour_manual(values = MODEL_COLOURS, guide = "none") +
  scale_y_discrete(labels = MODEL_LABELS, limits = rev) +
  labs(x = "Δ test RMSE = v2 − v1 (paired 95% CI)", y = NULL,
       title = "Change from 20 more training galaxies") +
  theme_report()

f21 <- patchwork::wrap_plots(f21_a, f21_b, nrow = 1, widths = c(1.1, 1)) +
  patchwork::plot_annotation(
    title = glue("v1 ({VERSIONS$v1$n_total} galaxies) versus v2 ({VERSIONS$v2$n_total} galaxies) ",
                 "on the same {length(z)} test galaxies"),
    theme = theme(plot.title = element_text(face = "bold", size = 13))
  )
save_fig(f21, "F21", "version_comparison", 9.5, 4.8)

n_better <- sum(learn$d_rmse < 0)
n_sig <- sum(learn$d_rmse_hi < 0)
add_caption("F21", glue(
  "Left: test RMSE of each learner for v1 ({VERSIONS$v1$n_train} training galaxies) and v2 ",
  "({VERSIONS$v2$n_train} training galaxies, 20 of them new), with 95% bootstrap CIs; the dashed ",
  "line is the v1 mean-prediction baseline. Right: paired change in test RMSE (v2 − v1) with a ",
  "95% paired-bootstrap CI ({N_BOOT} resamples of the same {length(z)} test galaxies) and the ",
  "bootstrap probability that v2 is better. {n_better} of {nrow(learn)} learners improve; ",
  "for {n_sig} the whole CI lies below zero."
))

# --- F22: learning curves of both versions on one axis -----------------------

lc <- bind_rows(
  read_tab("v1", "learning_curves.csv") |> mutate(version = "v1"),
  read_tab("v2", "learning_curves.csv") |> mutate(version = "v2")
) |>
  filter(model %in% LEARNERS) |>
  group_by(version, model, size) |>
  summarise(mean = mean(test_rmse), sd = sd(test_rmse), .groups = "drop") |>
  mutate(model = factor(model, levels = LEARNERS, labels = MODEL_LABELS[LEARNERS]),
         version = factor(version, levels = c("v1", "v2"), labels = levels(ci$version)))

f22 <- ggplot(lc, aes(size, mean, colour = version, fill = version)) +
  geom_hline(yintercept = base_rmse, linetype = "dashed", colour = "grey40") +
  geom_ribbon(aes(ymin = mean - sd, ymax = mean + sd), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.5) +
  facet_wrap(~model) +
  scale_colour_manual(values = version_cols, name = NULL) +
  scale_fill_manual(values = version_cols, name = NULL) +
  scale_x_continuous(breaks = seq(20, VERSIONS$v2$n_train, 10)) +
  labs(x = "Training-set size (galaxies)", y = "Test RMSE (mean ± 1 SD of 20 subsets)",
       title = "Learning curves on the shared test set: v1 and v2") +
  theme_report()
save_fig(f22, "F22", "learning_curves_v1_v2", 7.5, 5.2)
add_caption("F22", glue(
  "Test RMSE versus training-set size for each learner (mean ± 1 SD over 20 random subsets, ",
  "hyperparameters frozen at each version's tuned values, D-016). v1 subsets are drawn from ",
  "its {VERSIONS$v1$n_train} training galaxies, v2 subsets from its {VERSIONS$v2$n_train}; both ",
  "are scored on the same {length(z)} test galaxies. The dashed line is the baseline."
))

# --- Coverage and population checks ------------------------------------------

outside <- \(tr, te) sum(Reduce(`|`, map(FEATURES, \(f) te[[f]] < min(tr[[f]]) | te[[f]] > max(tr[[f]]))))
extends <- sum(Reduce(`|`, map(FEATURES, \(f) new_gal[[f]] < min(train$v1[[f]]) |
                                  new_gal[[f]] > max(train$v1[[f]]))))
ks_z <- suppressWarnings(ks.test(new_gal$redshift, train$v1$redshift))
ks_gr <- suppressWarnings(ks.test(new_gal$g_r, train$v1$g_r))

fmt <- \(x, d = 4) formatC(x, format = "f", digits = d)
row <- \(id) paired[paired$model == id, ]
rec <- row("M3_rf")
best_v1 <- as.character(learn$model[which.min(learn$rmse_v1)])
best_v2 <- as.character(learn$model[which.min(learn$rmse_v2)])
changed <- filter(t08, changed)

#' Plain-language verdict from the paired CI
verdict <- function(r) {
  ci <- glue("paired 95% CI [{sprintf('%+.4f', r$d_rmse_lo)}, {sprintf('%+.4f', r$d_rmse_hi)}]")
  if (r$d_rmse_hi < 0) glue("**clear improvement** ({ci} lies below zero)")
  else if (r$d_rmse_lo > 0) glue("**clearly worse** ({ci} lies above zero)")
  else glue("**no clear change** ({ci} includes zero; P(better) = {fmt(r$p_improved, 2)})")
}

# End of the v2 learning curves: is the test error still falling?
lc_tail <- read_tab("v2", "learning_curves.csv") |>
  filter(model %in% LEARNERS, size >= max(size) - 20) |>
  group_by(model, size) |>
  summarise(mean = mean(test_rmse), .groups = "drop")
lc_tail_txt <- lc_tail |>
  group_by(model) |>
  summarise(delta = mean[size == max(size)] - mean[size == min(size)], .groups = "drop") |>
  mutate(label = MODEL_LABELS[model])
falling <- lc_tail_txt$label[lc_tail_txt$delta < -0.001]
lc_reading <- if (length(falling) == 0) {
  paste("No curve is still falling by more than 0.001 in RMSE, so further galaxies of the same",
        "kind would give only small gains: the remaining error is set mainly by how much",
        "redshift information five broad-band magnitudes carry (intrinsic scatter of the",
        "colour–redshift relation), not by the sample size.")
} else {
  glue("Still falling: {paste(falling, collapse = ', ')}, so these models would gain from more data.")
}

notes <- c(
  "# v1 versus v2 (auto-generated by R/09_compare_versions.R)",
  "",
  "Facts for the comparison section. Every number is computed from the saved",
  "tables of both versions. Do not edit by hand.",
  "",
  "## Design",
  "",
  glue("- v1: {VERSIONS$v1$n_total} galaxies ({nrow(train$v1)} train / {nrow(test$v1)} test). ",
       "v2: {VERSIONS$v2$n_total} galaxies ({nrow(train$v2)} train / {nrow(test$v2)} test)."),
  glue("- The {length(new_ids)} new galaxies come from a second, independent SkyServer pull ",
       "with the same query (batch 2) and passed the same cleaning rules. They were added to ",
       "the training set only; the {length(z)} test galaxies are identical in both versions."),
  glue("- New galaxies: z = {fmt(min(new_gal$redshift), 3)}–{fmt(max(new_gal$redshift), 3)} ",
       "(median {fmt(median(new_gal$redshift), 3)}; v1 training median ",
       "{fmt(median(train$v1$redshift), 3)}). KS test against the v1 training set: redshift ",
       "p = {fmt(ks_z$p.value, 2)}, g − r p = {fmt(ks_gr$p.value, 2)}",
       "{if (min(ks_z$p.value, ks_gr$p.value) > 0.05) ', so there is no evidence that they come from a different population' else ''}."),
  glue("- {extends} of the {length(new_ids)} new galaxies lie outside the v1 training range in at ",
       "least one feature, so v2 covers a wider region of colour space. Test galaxies outside ",
       "the training range: {outside(train$v1, test$v1)} in v1, {outside(train$v2, test$v2)} in v2."),
  "",
  "## Test-set change (paired, same 20 galaxies)",
  "",
  glue_collapse(map_chr(LEARNERS, \(id) {
    r <- row(id)
    glue("- {r$label}: RMSE {fmt(r$rmse_v1)} → {fmt(r$rmse_v2)} ",
         "(Δ = {sprintf('%+.4f', r$d_rmse)}, {sprintf('%+.1f', r$pct_change)}%; paired 95% CI ",
         "[{sprintf('%+.4f', r$d_rmse_lo)}, {sprintf('%+.4f', r$d_rmse_hi)}]; ",
         "P(better) = {fmt(r$p_improved, 2)}; {r$galaxies_closer} of {r$n_test} galaxies closer). ",
         "σ_NMAD {fmt(r$sigma_nmad_v1)} → {fmt(r$sigma_nmad_v2)}.")
  }), sep = "\n"),
  glue("- Learners that improve: {n_better} of {nrow(learn)}; with the whole paired CI below ",
       "zero: {n_sig}."),
  glue("- Best learner by test RMSE: {MODEL_LABELS[[best_v1]]} in v1, {MODEL_LABELS[[best_v2]]} in v2."),
  glue("- Cross-validation RMSE (each version's own training set, so not paired): ",
       glue_collapse(map_chr(LEARNERS, \(id) {
         r <- row(id)
         glue("{MODEL_LABELS[[id]]} {fmt(r$cv_rmse_v1)} → {fmt(r$cv_rmse_v2)}")
       }), sep = "; "), "."),
  "",
  "## Hyperparameters (T08)",
  "",
  if (nrow(changed) == 0) "- No tuned hyperparameter changed between v1 and v2." else
    glue("- {changed$label}: {changed$parameter} {changed$selected_v1} → {changed$selected_v2}."),
  "",
  "## Reading the result",
  "",
  glue("- With {length(z)} test galaxies, each version's own RMSE CI is wide (T05). The paired ",
       "CI removes the shared galaxy-to-galaxy scatter, so it is the right test of whether the ",
       "extra training data helped."),
  glue_collapse(map_chr(LEARNERS, \(id) {
    r <- row(id)
    glue("- {r$label}: {verdict(r)}.")
  }), sep = "\n"),
  glue("- Bias–variance reading: k-NN and the random forest predict from *local* averages of ",
       "training galaxies, so with n = {VERSIONS$v1$n_train} their error is dominated by variance ",
       "(how sparsely the colour–redshift relation is sampled). 25% more galaxies samples it more ",
       "densely{if ('M2_knn' %in% changed$model) glue(', and the CV-tuned k rose from {changed$selected_v1[changed$model == \"M2_knn\"]} to {changed$selected_v2[changed$model == \"M2_knn\"]}: with denser data the model can average more neighbours without blurring the relation') else ''}. ",
       "Linear regression has 6 parameters and is limited by bias (a straight line through a curved ",
       "relation), so extra data cannot help it. The tuned SVR kernel is very wide ",
       "(σ = {t03$v2$selected[t03$v2$model == 'M4_svr' & t03$v2$parameter == 'sigma']}), which makes it ",
       "close to linear, so it behaves like the linear model; its test change is within the noise."),
  glue("- Learning curves (F22, v2): from {max(lc_tail$size) - 20} to {max(lc_tail$size)} training ",
       "galaxies the mean test RMSE changes by ",
       glue_collapse(glue("{lc_tail_txt$label} {sprintf('%+.4f', lc_tail_txt$delta)}"), sep = ", "),
       ". {lc_reading}")
)
writeLines(notes, file.path(PATHS$tables, "comparison_notes.md"))
cat(notes, sep = "\n")

# --- site/models/manifest.js: what the web page's version chooser shows ------

manifest <- list(
  latest = LATEST_VERSION,
  generated = format(Sys.Date()),
  versions = map(names(VERSIONS), \(v) {
    info <- VERSIONS[[v]]
    rf <- t05[[v]][t05[[v]]$model == "M3_rf", ]
    list(
      id = v,
      title = if (v == "v1") "Original" else "Extended",
      n_total = info$n_total, n_train = info$n_train, n_test = info$n_test,
      description = if (v == "v1") {
        "The original analysis that follows the course brief (30–100 observations)."
      } else {
        glue("v1 plus {length(new_ids)} new SDSS galaxies from a second pull, added to training only.")
      },
      rf_rmse = rf$rmse
    )
  }),
  comparison = list(
    n_new = length(new_ids),
    rf_delta = rec$d_rmse, rf_delta_lo = rec$d_rmse_lo, rf_delta_hi = rec$d_rmse_hi,
    summary = glue("{n_better} of {nrow(learn)} models improve on the shared test set; ",
                   "for {n_sig} the improvement is clear of zero.")
  )
)
site_models <- here::here("site", "models")
dir.create(site_models, recursive = TRUE, showWarnings = FALSE)
writeLines(c("// Generated by R/09_compare_versions.R. Do not edit by hand.",
             paste0("window.PHOTOZ_MANIFEST = ",
                    jsonlite::toJSON(manifest, auto_unbox = TRUE, digits = I(6)), ";")),
           file.path(site_models, "manifest.js"), useBytes = TRUE)
message("Wrote site/models/manifest.js")
