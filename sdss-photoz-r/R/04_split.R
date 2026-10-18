# =============================================================================
# 04_split.R — Workflow step 4: split into training and testing sets
# Inputs : data/processed/sdss_clean.csv
# Outputs: data/processed/train.csv (80), data/processed/test.csv (20),
#          outputs/figures/F07_train_test_split (.png + .pdf), captions.md
# Brief  : TASK.md §4, step 4; decisions D-009, D-014
# =============================================================================
#
# From here on the test set is held out (AGENTS.md R5): it is read again only
# in 06_evaluate.R, 07_interpret.R and the frozen-hyperparameter learning
# curves in 05_train.R.

source(here::here("R", "00_setup.R"))

clean <- read_csv(PATHS$clean, col_types = RAW_COL_TYPES, progress = FALSE)

# --- Stratified 80/20 split (D-009) ------------------------------------------

# createDataPartition() bins a numeric target into quantile groups and samples
# 80% within each group, so train and test both cover the full redshift range.
set.seed(SEED)
train_idx <- caret::createDataPartition(clean$redshift, p = 0.8, list = FALSE)[, 1]

train <- clean[train_idx, ]
test <- clean[-train_idx, ]

stopifnot(
  "Split must be 80 train / 20 test (D-009)" = nrow(train) == 80 && nrow(test) == 20,
  "No galaxy may be in both sets" = length(intersect(train$objid, test$objid)) == 0,
  "Every galaxy must be in one set" = nrow(train) + nrow(test) == nrow(clean)
)

write_csv(train, PATHS$train)
write_csv(test, PATHS$test)

# --- F07: do train and test have the same redshift distribution? ------------

# Two-sample Kolmogorov–Smirnov test. A large p-value means no evidence that
# the two redshift distributions differ.
ks <- ks.test(train$redshift, test$redshift)

split_long <- bind_rows(
  train |> mutate(set = glue("Train (n = {nrow(train)})")),
  test |> mutate(set = glue("Test (n = {nrow(test)})"))
) |>
  mutate(set = factor(set, levels = unique(set)))

set_colours <- setNames(unname(OKABE_ITO[c("blue", "orange")]), levels(split_long$set))

f07 <- ggplot(split_long, aes(redshift, colour = set, fill = set)) +
  geom_histogram(aes(y = after_stat(density)), bins = 15, alpha = 0.3,
                 position = "identity", colour = NA) +
  geom_density(fill = NA, linewidth = 1) +
  geom_rug(alpha = 0.7) +
  scale_colour_manual(values = set_colours, name = NULL) +
  scale_fill_manual(values = set_colours, name = NULL) +
  labs(
    x = "Spectroscopic redshift  z_spec", y = "Density",
    title = "Redshift distributions of the training and test sets",
    subtitle = sprintf("Two-sample KS test: D = %.3f, p = %.3f", ks$statistic, ks$p.value)
  ) +
  theme_report()
save_fig(f07, "F07", "train_test_split", 6.5, 4.5)

add_caption("F07", glue(
  "Spectroscopic redshift of the {nrow(train)} training and {nrow(test)} test ",
  "galaxies (histograms, kernel densities and rugs) after a stratified 80/20 ",
  "split (seed {SEED}). Two-sample KS test: D = {sprintf('%.3f', ks$statistic)}, ",
  "p = {sprintf('%.3f', ks$p.value)}",
  "{if (ks$p.value > 0.05) ', so there is no evidence that the two distributions differ' else ''}."
))

message(glue(
  "Split: {nrow(train)} train / {nrow(test)} test (seed {SEED})\n",
  "  train z: {round(min(train$redshift), 3)} to {round(max(train$redshift), 3)}\n",
  "  test  z: {round(min(test$redshift), 3)} to {round(max(test$redshift), 3)}\n",
  "  KS test: D = {sprintf('%.3f', ks$statistic)}, p = {sprintf('%.3f', ks$p.value)}",
  .trim = FALSE
))
