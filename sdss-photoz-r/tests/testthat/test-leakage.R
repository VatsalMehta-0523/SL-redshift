# The test set is held out (AGENTS.md R5, D-009): no galaxy is in both sets,
# and the saved models were fitted on the training galaxies only. v2 keeps
# v1's test set (D-018), so the 20 new galaxies can only ever be training data.

for (v in names(VERSIONS)) {
  p <- version_paths(v)
  clean <- read_processed(p$clean)
  train <- read_processed(p$train)
  test <- read_processed(p$test)

  test_that(glue("{v}: split is {VERSIONS[[v]]$n_train} train / {VERSIONS[[v]]$n_test} test"), {
    expect_equal(nrow(train), VERSIONS[[v]]$n_train)
    expect_equal(nrow(test), VERSIONS[[v]]$n_test)
  })

  test_that(glue("{v}: no galaxy appears in both train and test"), {
    expect_length(intersect(train$objid, test$objid), 0)
  })

  test_that(glue("{v}: train and test together are exactly the clean dataset"), {
    expect_setequal(c(train$objid, test$objid), clean$objid)
    rebuilt <- dplyr::arrange(dplyr::bind_rows(train, test), objid)
    expect_equal(rebuilt, dplyr::arrange(clean, objid))
  })

  models_present <- all(file.exists(file.path(p$models, paste0(MODEL_IDS[1:5], ".rds"))))

  test_that(glue("{v}: every saved model was trained on its training galaxies only"), {
    skip_if_not(models_present, "models not trained yet: run Rscript run_all.R")
    for (id in MODEL_IDS[1:5]) {
      m <- readRDS(file.path(p$models, paste0(id, ".rds")))
      used <- m$trainingData
      expect_equal(nrow(used), nrow(train), info = id)
      # caret stores the target as .outcome: it must be the training redshifts
      expect_equal(sort(used$.outcome), sort(train$redshift), info = id)
      expect_false(any(test$redshift %in% used$.outcome), info = id)
    }
  })

  test_that(glue("{v}: cross-validation folds contain training rows only"), {
    skip_if_not(models_present, "models not trained yet: run Rscript run_all.R")
    m <- readRDS(file.path(p$models, "M1_lm.rds"))
    expect_length(m$control$index, 25)
    expect_true(all(unlist(m$control$index) <= nrow(train)))
  })
}

test_that("v2 uses exactly v1's test galaxies, and v2's training set contains v1's (D-018)", {
  v1_test <- read_processed(version_paths("v1")$test)
  v2_test <- read_processed(version_paths("v2")$test)
  v1_train <- read_processed(version_paths("v1")$train)
  v2_train <- read_processed(version_paths("v2")$train)
  expect_equal(dplyr::arrange(v2_test, objid), dplyr::arrange(v1_test, objid))
  expect_true(all(v1_train$objid %in% v2_train$objid))
  expect_equal(nrow(v2_train) - nrow(v1_train), VERSIONS$v2$n_new)
})
