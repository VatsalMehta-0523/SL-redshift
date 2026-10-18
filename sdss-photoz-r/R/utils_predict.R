# =============================================================================
# utils_predict.R — Inference: predict redshift for new galaxies
# Used by app/app.R. Needs the trained models from R/05_train.R.
# =============================================================================
#
# A prediction is trustworthy only inside the range the models were trained
# on (README §14). Every prediction therefore comes with a validity check.

suppressPackageStartupMessages({
  library(caret) # predict() for caret train objects
  library(randomForest)
  library(kernlab)
})

# The baseline always predicts the training mean, so it is not offered here
PREDICT_MODELS <- c("M1_lm", "M2_knn", "M3_rf", "M4_svr")

# Best on the held-out test set and cannot extrapolate to unphysical z (T05)
RECOMMENDED_MODEL <- "M3_rf"

#' Load the saved models. Stops with a clear message if training has not run.
load_models <- function(ids = PREDICT_MODELS) {
  paths <- file.path(PATHS$models, paste0(ids, ".rds"))
  missing <- ids[!file.exists(paths)]
  if (length(missing) > 0) {
    stop("Trained models not found: ", paste(missing, collapse = ", "),
         ". Run `Rscript R/05_train.R` first.", call. = FALSE)
  }
  set_names(map(paths, readRDS), ids)
}

#' Min/max of every feature (and of z) in the training set.
training_ranges <- function(train) {
  tibble::tibble(
    feature = c(FEATURES, "redshift"),
    min = map_dbl(c(FEATURES, "redshift"), \(f) min(train[[f]])),
    max = map_dbl(c(FEATURES, "redshift"), \(f) max(train[[f]]))
  )
}

#' Predict z for one or more galaxies given their de-reddened magnitudes.
#' `mags` needs columns u, g, r, i, zmag. Returns the colours, one z_phot
#' column per model and the features that fall outside the training range.
predict_redshift <- function(mags, models, ranges) {
  stopifnot(all(c("u", "g", "r", "i", "zmag") %in% names(mags)))
  galaxies <- derive_colours(mags)

  preds <- map_dfc(models, \(m) predict(m, newdata = galaxies))
  names(preds) <- paste0("z_phot_", names(models))

  feature_ranges <- filter(ranges, feature %in% FEATURES)
  outside <- map_chr(seq_len(nrow(galaxies)), \(k) {
    bad <- feature_ranges$feature[
      galaxies[k, feature_ranges$feature] < feature_ranges$min |
        galaxies[k, feature_ranges$feature] > feature_ranges$max
    ]
    paste(bad, collapse = ", ")
  })

  bind_cols(galaxies, preds) |>
    mutate(outside_features = outside, in_training_range = outside == "")
}
