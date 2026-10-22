# The static web demo (site/) must give the SAME predictions as the models in
# R. site/predict.js runs inside R's V8 JavaScript engine on every test galaxy
# and is compared with test_predictions.csv from 06_evaluate.R.

site_ready <- file.exists(here::here("site", "model.js")) &&
  file.exists(here::here("site", "predict.js")) &&
  requireNamespace("V8", quietly = TRUE)

# ctx$assign() rounds numbers to 4 decimals; send full-precision JSON instead
assign_exact <- function(ctx, name, df) {
  ctx$assign(name, V8::JS(jsonlite::toJSON(df, digits = NA, dataframe = "rows")))
}

new_js <- function() {
  ctx <- V8::v8()
  ctx$eval("var window = this;")
  ctx$source(here::here("site", "model.js"))
  ctx$source(here::here("site", "predict.js"))
  ctx
}

test_that("browser predictions equal R predictions for all test galaxies", {
  skip_if_not(site_ready, "run Rscript R/08_export_web.R first")
  ctx <- new_js()
  test <- read_processed(PATHS$test)
  saved <- read_processed(file.path(PATHS$tables, "test_predictions.csv"))

  mags <- dplyr::select(test, u, g, r, i, zmag)
  assign_exact(ctx, "mags", mags) # data frame -> array of row objects
  js <- ctx$get("mags.map(function (m) { return PhotoZ.predictAll(m, PHOTOZ).preds; })")

  for (id in c("M1_lm", "M2_knn", "M3_rf", "M4_svr")) {
    expect_equal(js[[id]], saved[[id]], tolerance = 1e-9, info = id)
  }
})

test_that("browser range check flags the same galaxies as R", {
  skip_if_not(site_ready, "run Rscript R/08_export_web.R first")
  ctx <- new_js()
  train <- read_processed(PATHS$train)
  test <- read_processed(PATHS$test)
  assign_exact(ctx, "mags", dplyr::select(test, u, g, r, i, zmag))
  n_js <- ctx$get("mags.filter(function (m) { return PhotoZ.predictAll(m, PHOTOZ).outside.length > 0; }).length")

  outside <- Reduce(`|`, lapply(FEATURES, \(f) test[[f]] < min(train[[f]]) | test[[f]] > max(train[[f]])))
  expect_equal(n_js, sum(outside))
})

test_that("browser cosmology agrees with R's numerical integration (flat ΛCDM)", {
  skip_if_not(site_ready, "run Rscript R/08_export_web.R first")
  ctx <- new_js()
  # Same model as predict.js: H0 = 70 km/s/Mpc, Ωm = 0.3, ΩΛ = 0.7
  E <- function(z) sqrt(0.3 * (1 + z)^3 + 0.7)
  for (z in c(0.025, 0.1, 0.22)) {
    dc_r <- (299792.458 / 70) * integrate(\(t) 1 / E(t), 0, z)$value
    tl_r <- (977.792 / 70) * integrate(\(t) 1 / ((1 + t) * E(t)), 0, z)$value
    cosmo <- ctx$get(sprintf("PhotoZ.cosmology(%s)", z))
    expect_equal(cosmo$comoving_mpc, dc_r, tolerance = 1e-8, info = z)
    expect_equal(cosmo$lookback_gyr, tl_r, tolerance = 1e-8, info = z)
  }
  # Sanity check against the widely quoted comoving distance at z = 0.1
  expect_equal(ctx$get("PhotoZ.cosmology(0.1).comoving_mpc"), 418.4, tolerance = 0.005)
  expect_equal(ctx$get("PhotoZ.cosmology(0).comoving_mpc"), 0)
})
