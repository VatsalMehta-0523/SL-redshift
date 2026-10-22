# Metric functions (R/utils_metrics.R) checked against values worked out by hand.
#
# Toy example: truth z = (1, 2, 4), prediction = (1, 2, 3)
#   errors          = (0, 0, -1)
#   RMSE            = sqrt(1/3)
#   MAE             = 1/3
#   R²              : mean(truth) = 7/3, SS_tot = 16/9 + 1/9 + 25/9 = 42/9,
#                     SS_res = 1  ->  R² = 1 - 9/42
#   dz = err/(1+z)  = (0, 0, -1/5)
#   bias            = mean(dz) = -1/15
#   sigma_NMAD      = 1.4826 * median(|dz - median(dz)|) = 1.4826 * median(0, 0, 0.2) = 0
#   eta (|dz|>0.15) = 1/3

truth <- c(1, 2, 4)
pred <- c(1, 2, 3)

test_that("dz is the error normalised by (1 + z_spec)", {
  expect_equal(dz(pred, truth), c(0, 0, -0.2))
})

test_that("RMSE, MAE and R² match hand-computed values", {
  expect_equal(rmse(pred, truth), sqrt(1 / 3))
  expect_equal(mae(pred, truth), 1 / 3)
  expect_equal(r2(pred, truth), 1 - 9 / 42)
})

test_that("photo-z metrics match hand-computed values", {
  expect_equal(bias(pred, truth), -1 / 15)
  expect_equal(sigma_nmad(pred, truth), 0)
  expect_equal(eta(pred, truth), 1 / 3)
})

test_that("perfect predictions give zero error and R² = 1", {
  z <- c(0.05, 0.10, 0.20)
  expect_equal(rmse(z, z), 0)
  expect_equal(mae(z, z), 0)
  expect_equal(r2(z, z), 1)
  expect_equal(bias(z, z), 0)
  expect_equal(eta(z, z), 0)
})

test_that("predicting the mean gives R² = 0, and worse than the mean gives R² < 0", {
  z <- c(0.05, 0.10, 0.15)
  expect_equal(r2(rep(mean(z), 3), z), 0)
  expect_lt(r2(rev(z), z), 0)
})

test_that("sigma_NMAD equals the SD for a symmetric two-point spread", {
  # dz = (-a, +a) around 0 -> median |dz| = a -> sigma_NMAD = 1.4826 a
  z <- c(0, 0)
  p <- c(-0.01, 0.01)
  expect_equal(sigma_nmad(p, z), 1.4826 * 0.01)
})

test_that("eta uses a strict > 0.15 threshold", {
  z <- c(0, 0)
  expect_equal(eta(c(0.15, 0.16), z), 0.5)
})

test_that("all_metrics returns one row with every metric", {
  m <- all_metrics(pred, truth)
  expect_equal(nrow(m), 1)
  expect_named(m, c("rmse", "mae", "r2", "bias", "sigma_nmad", "eta"))
})
