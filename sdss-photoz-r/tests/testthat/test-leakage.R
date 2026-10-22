# The test set is held out (AGENTS.md R5, D-009): no galaxy is in both sets,
# and the saved models were fitted on the 80 training galaxies only.

clean <- read_processed(PATHS$clean)
train <- read_processed(PATHS$train)
test <- read_processed(PATHS$test)

test_that("split is 80 train / 20 test (D-009)", {
  expect_equal(nrow(train), 80)
  expect_equal(nrow(test), 20)
})

test_that("no galaxy appears in both train and test", {
  expect_length(intersect(train$objid, test$objid), 0)
})

test_that("train and test together are exactly the clean dataset", {
  expect_setequal(c(train$objid, test$objid), clean$objid)
  rebuilt <- dplyr::arrange(dplyr::bind_rows(train, test), objid)
  expect_equal(rebuilt, dplyr::arrange(clean, objid))
})

models_present <- all(file.exists(file.path(PATHS$models, paste0(MODEL_IDS[1:5], ".rds"))))

test_that("every saved model was trained on the 80 training galaxies only", {
  skip_if_not(models_present, "models not trained yet: run Rscript R/05_train.R")
  for (id in MODEL_IDS[1:5]) {
    m <- readRDS(file.path(PATHS$models, paste0(id, ".rds")))
    used <- m$trainingData
    expect_equal(nrow(used), nrow(train), info = id)
    # caret stores the target as .outcome: it must be the training redshifts
    expect_equal(sort(used$.outcome), sort(train$redshift), info = id)
    expect_false(any(test$redshift %in% used$.outcome), info = id)
  }
})

test_that("cross-validation folds contain training rows only", {
  skip_if_not(models_present, "models not trained yet: run Rscript R/05_train.R")
  m <- readRDS(file.path(PATHS$models, "M1_lm.rds"))
  expect_length(m$control$index, 25)
  expect_true(all(unlist(m$control$index) <= nrow(train)))
})
