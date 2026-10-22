# The inference helpers used by the Shiny app (R/utils_predict.R) give the
# same predictions as the evaluation script and flag out-of-range inputs.

models_present <- all(file.exists(file.path(PATHS$models, paste0(MODEL_IDS[2:5], ".rds"))))

test_that("predict_redshift() reproduces the evaluated test predictions", {
  skip_if_not(models_present, "models not trained yet: run Rscript R/05_train.R")
  source(here::here("R", "utils_predict.R"))
  train <- read_processed(PATHS$train)
  test <- read_processed(PATHS$test)
  saved <- read_processed(file.path(PATHS$tables, "test_predictions.csv"))

  out <- predict_redshift(dplyr::select(test, u, g, r, i, zmag),
                          load_models(), training_ranges(train))
  for (id in PREDICT_MODELS) {
    expect_equal(unname(out[[paste0("z_phot_", id)]]), saved[[id]], tolerance = 1e-12, info = id)
  }
})

test_that("galaxies inside the training range are not flagged; extreme ones are", {
  skip_if_not(models_present, "models not trained yet: run Rscript R/05_train.R")
  source(here::here("R", "utils_predict.R"))
  train <- read_processed(PATHS$train)
  ranges <- training_ranges(train)
  models <- load_models()

  # A real training galaxy is inside the range by definition
  inside <- predict_redshift(dplyr::select(train[1, ], u, g, r, i, zmag), models, ranges)
  expect_true(inside$in_training_range)

  # Make g - r far redder than anything in training
  extreme <- dplyr::mutate(dplyr::select(train[1, ], u, g, r, i, zmag), g = g + 2)
  out <- predict_redshift(extreme, models, ranges)
  expect_false(out$in_training_range)
  expect_match(out$outside_features, "g_r")
})

test_that("load_models() fails with a clear message when models are missing", {
  source(here::here("R", "utils_predict.R"))
  expect_error(load_models("M9_not_a_model"), "Run `Rscript R/05_train.R` first")
})
