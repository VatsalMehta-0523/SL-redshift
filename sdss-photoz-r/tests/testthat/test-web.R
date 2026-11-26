# The static web demo (site/) must give the SAME predictions as the models in
# R, for every dataset version. site/predict.js runs inside R's V8 JavaScript
# engine on every test galaxy and is compared with test_predictions.csv from
# 06_evaluate.R.

js_file <- \(v) here::here("site", "models", paste0(v, ".js"))
site_ready <- \(v) file.exists(js_file(v)) &&
  file.exists(here::here("site", "predict.js")) &&
  requireNamespace("V8", quietly = TRUE)

# ctx$assign() rounds numbers to 4 decimals; send full-precision JSON instead
assign_exact <- function(ctx, name, df) {
  ctx$assign(name, V8::JS(jsonlite::toJSON(df, digits = NA, dataframe = "rows")))
}

new_js <- function(v) {
  ctx <- V8::v8()
  ctx$eval("var window = this;")
  ctx$source(js_file(v))
  ctx$source(here::here("site", "predict.js"))
  ctx$eval(sprintf("var PHOTOZ = window.PHOTOZ_MODELS['%s'];", v))
  ctx
}

for (v in names(VERSIONS)) {
  p <- version_paths(v)

  test_that(glue("{v}: browser predictions equal R predictions for all test galaxies"), {
    skip_if_not(site_ready(v), "run Rscript R/08_export_web.R first")
    ctx <- new_js(v)
    expect_equal(ctx$get("PHOTOZ.version"), v)
    expect_equal(ctx$get("PHOTOZ.n_train"), VERSIONS[[v]]$n_train)
    test <- read_processed(p$test)
    saved <- read_processed(file.path(p$tables, "test_predictions.csv"))

    assign_exact(ctx, "mags", dplyr::select(test, u, g, r, i, zmag))
    js <- ctx$get("mags.map(function (m) { return PhotoZ.predictAll(m, PHOTOZ).preds; })")
    for (id in c("M1_lm", "M2_knn", "M3_rf", "M4_svr")) {
      expect_equal(js[[id]], saved[[id]], tolerance = 1e-9, info = id)
    }
  })

  test_that(glue("{v}: browser range check flags the same galaxies as R"), {
    skip_if_not(site_ready(v), "run Rscript R/08_export_web.R first")
    ctx <- new_js(v)
    train <- read_processed(p$train)
    test <- read_processed(p$test)
    assign_exact(ctx, "mags", dplyr::select(test, u, g, r, i, zmag))
    n_js <- ctx$get("mags.filter(function (m) { return PhotoZ.predictAll(m, PHOTOZ).outside.length > 0; }).length")
    outside <- Reduce(`|`, lapply(FEATURES, \(f) test[[f]] < min(train[[f]]) | test[[f]] > max(train[[f]])))
    expect_equal(n_js, sum(outside))
  })
}

test_that("the site manifest lists both versions with the numbers in T05", {
  path <- here::here("site", "models", "manifest.js")
  skip_if_not(file.exists(path) && requireNamespace("V8", quietly = TRUE))
  ctx <- V8::v8()
  ctx$eval("var window = this;")
  ctx$source(path)
  m <- ctx$get("PHOTOZ_MANIFEST")
  expect_setequal(m$versions$id, names(VERSIONS))
  expect_equal(m$latest, LATEST_VERSION)
  for (v in names(VERSIONS)) {
    t05 <- readr::read_csv(file.path(version_paths(v)$tables, "T05_test_metrics.csv"),
                           show_col_types = FALSE)
    expect_equal(m$versions$rf_rmse[m$versions$id == v], t05$rmse[t05$model == "M3_rf"],
                 tolerance = 1e-5, info = v)
  }
})

test_that("browser cosmology agrees with R's numerical integration (flat ΛCDM)", {
  skip_if_not(site_ready(LATEST_VERSION), "run Rscript R/08_export_web.R first")
  ctx <- new_js(LATEST_VERSION)
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
