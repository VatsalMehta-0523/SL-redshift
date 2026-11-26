# The inference helpers used by the Shiny app (R/utils_predict.R) give the
# same predictions as the evaluation script and flag out-of-range inputs,
# for every dataset version.

source(here::here("R", "utils_predict.R"))

for (v in names(VERSIONS)) {
  p <- version_paths(v)
  models_present <- all(file.exists(file.path(p$models, paste0(MODEL_IDS[2:5], ".rds"))))

  test_that(glue("{v}: predict_redshift() reproduces the evaluated test predictions"), {
    skip_if_not(models_present, "models not trained yet: run Rscript run_all.R")
    train <- read_processed(p$train)
    test <- read_processed(p$test)
    saved <- read_processed(file.path(p$tables, "test_predictions.csv"))

    out <- predict_redshift(dplyr::select(test, u, g, r, i, zmag),
                            load_models(version = v), training_ranges(train))
    for (id in PREDICT_MODELS) {
      expect_equal(unname(out[[paste0("z_phot_", id)]]), saved[[id]], tolerance = 1e-12, info = id)
    }
  })

  test_that(glue("{v}: galaxies inside the training range are not flagged; extreme ones are"), {
    skip_if_not(models_present, "models not trained yet: run Rscript run_all.R")
    train <- read_processed(p$train)
    ranges <- training_ranges(train)
    models <- load_models(version = v)

    # A real training galaxy is inside the range by definition
    inside <- predict_redshift(dplyr::select(train[1, ], u, g, r, i, zmag), models, ranges)
    expect_true(inside$in_training_range)

    # Make g - r far redder than anything in training
    extreme <- dplyr::mutate(dplyr::select(train[1, ], u, g, r, i, zmag), g = g + 2)
    out <- predict_redshift(extreme, models, ranges)
    expect_false(out$in_training_range)
    expect_match(out$outside_features, "g_r")
  })
}

test_that("v1 and v2 models are different fits (v2 really was retrained)", {
  skip_if_not(all(file.exists(file.path(version_paths("v2")$models, "M3_rf.rds"))))
  p1 <- read_processed(file.path(version_paths("v1")$tables, "test_predictions.csv"))
  p2 <- read_processed(file.path(version_paths("v2")$tables, "test_predictions.csv"))
  expect_false(isTRUE(all.equal(p1$M3_rf, p2$M3_rf)))
})

test_that("load_models() fails with a clear message when models are missing", {
  expect_error(load_models("M9_not_a_model"), "Run `Rscript R/05_train.R` first")
})
