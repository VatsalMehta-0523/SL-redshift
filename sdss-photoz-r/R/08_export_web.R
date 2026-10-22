# =============================================================================
# 08_export_web.R — Export the trained models for the static web demo
# Inputs : outputs/models/M1_lm, M2_knn, M3_rf, M4_svr (.rds),
#          data/processed/train.csv, test.csv, outputs/tables/T05_test_metrics.csv
# Outputs: site/model.js  (window.PHOTOZ = { models, reference data })
# Brief  : presentation only; the analysis stays in R (D-002, D-017)
# =============================================================================
#
# The web page (site/) runs in the browser without R. This script writes out
# every number the browser needs to reproduce each model's prediction
# exactly: scaling statistics, linear coefficients, k-NN training points,
# the 500 random-forest trees and the SVR support vectors. The prediction code
# in site/predict.js is checked against R's own predictions by
# tests/testthat/test-web.R.

source(here::here("R", "00_setup.R"))
suppressPackageStartupMessages({
  library(caret)
  library(randomForest)
  library(kernlab)
})

SITE <- here::here("site")
dir.create(SITE, showWarnings = FALSE)

load_model <- function(id) readRDS(file.path(PATHS$models, paste0(id, ".rds")))
lm_fit <- load_model("M1_lm")
knn_fit <- load_model("M2_knn")
rf_fit <- load_model("M3_rf")
svr_fit <- load_model("M4_svr")

train <- read_csv(PATHS$train, col_types = RAW_COL_TYPES, progress = FALSE)
test <- read_csv(PATHS$test, col_types = RAW_COL_TYPES, progress = FALSE)
t05 <- read_csv(file.path(PATHS$tables, "T05_test_metrics.csv"), show_col_types = FALSE)

# Every model must use the same feature order as FEATURES
stopifnot(identical(rf_fit$finalModel$xNames, FEATURES),
          identical(knn_fit$finalModel$xNames, FEATURES),
          identical(colnames(xmatrix(svr_fit$finalModel)), FEATURES))

#' caret's centring/scaling (fitted on the training data) as plain vectors
caret_scaling <- function(fit) {
  list(mean = unname(fit$preProcess$mean[FEATURES]),
       std = unname(fit$preProcess$std[FEATURES]))
}

# --- M1 linear regression: z = b0 + sum(b_j * standardised x_j) --------------
lm_coef <- coef(lm_fit$finalModel)
m1 <- list(scale = caret_scaling(lm_fit),
           intercept = unname(lm_coef["(Intercept)"]),
           coef = unname(lm_coef[FEATURES]))

# --- M2 k-NN: mean redshift of the k nearest standardised training points ---
m2 <- list(scale = caret_scaling(knn_fit),
           k = knn_fit$finalModel$k,
           x = unname(as.matrix(knn_fit$finalModel$learn$X)[, FEATURES]),
           y = unname(knn_fit$finalModel$learn$y))

# --- M3 random forest: average of 500 regression trees -----------------------
# Each tree is stored column-wise. A node is terminal when left == 0;
# otherwise go left if x[var] <= split (randomForest's rule).
rf <- rf_fit$finalModel
trees <- map(seq_len(rf$ntree), \(k) {
  t <- getTree(rf, k, labelVar = FALSE)
  list(l = as.integer(t[, "left daughter"]),
       r = as.integer(t[, "right daughter"]),
       v = as.integer(t[, "split var"]),
       s = unname(t[, "split point"]),
       p = unname(t[, "prediction"]))
})
m3 <- list(trees = trees)

# --- M4 SVR (RBF kernel, kernlab ksvm) ----------------------------------------
# f(x) = sum_i coef_i * exp(-sigma * |sv_i - x|^2) - b, on inputs scaled by
# caret and then by ksvm itself; the output is un-scaled with ksvm's y scaling.
svr <- svr_fit$finalModel
sc <- kernlab::scaling(svr)
m4 <- list(scale = caret_scaling(svr_fit),
           x_center = unname(sc$x.scale$`scaled:center`[FEATURES]),
           x_scale = unname(sc$x.scale$`scaled:scale`[FEATURES]),
           y_center = unname(sc$y.scale$`scaled:center`),
           y_scale = unname(sc$y.scale$`scaled:scale`),
           sigma = unname(kpar(kernelf(svr))$sigma),
           b = b(svr),
           coef = as.numeric(unlist(coef(svr))),
           sv = unname(as.matrix(xmatrix(svr))))
stopifnot("one SVR coefficient per support vector" =
            length(m4$coef) == nrow(m4$sv) && ncol(m4$sv) == length(FEATURES))

# --- Reference data for the page ---------------------------------------------
ranges <- map(set_names(c(FEATURES, "redshift")), \(f) range(train[[f]]))

metrics <- t05 |>
  filter(model %in% c("M1_lm", "M2_knn", "M3_rf", "M4_svr")) |>
  select(model, label, rmse, sigma_nmad, eta)

presets <- test |>
  arrange(redshift) |>
  transmute(objid, u, g, r, i, zmag, z_spec = redshift)

photoz <- list(
  generated = format(Sys.Date()),
  features = FEATURES,
  n_train = nrow(train),
  recommended = "M3_rf",
  labels = as.list(MODEL_LABELS[c("M1_lm", "M2_knn", "M3_rf", "M4_svr")]),
  colours = as.list(MODEL_COLOURS[c("M1_lm", "M2_knn", "M3_rf", "M4_svr")]),
  models = list(M1_lm = m1, M2_knn = m2, M3_rf = m3, M4_svr = m4),
  ranges = ranges,
  metrics = metrics,
  train_points = select(train, g_r, redshift),
  presets = presets,
  filters = SDSS_FILTERS,
  break_rest = BREAK_REST
)

# 15 significant digits keeps predictions identical to R to ~1e-12
json <- jsonlite::toJSON(photoz, auto_unbox = TRUE, digits = I(15),
                         dataframe = "rows", matrix = "rowmajor")
writeLines(c("// Generated by R/08_export_web.R. Do not edit by hand.",
             paste0("window.PHOTOZ = ", json, ";")),
           file.path(SITE, "model.js"), useBytes = TRUE)

message(glue("Wrote site/model.js ({round(file.size(file.path(SITE, 'model.js')) / 1024)} KB)"))
