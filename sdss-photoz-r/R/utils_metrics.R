# =============================================================================
# utils_metrics.R — Regression and photo-z metrics (D-011)
# Every function takes (pred, truth): pred = z_phot, truth = z_spec.
# =============================================================================

#' Normalised redshift error: dz = (z_phot - z_spec) / (1 + z_spec)
#' Redshift errors grow with z, so photo-z work divides by (1 + z).
dz <- function(pred, truth) (pred - truth) / (1 + truth)

#' Root mean squared error: sqrt(mean((z_phot - z_spec)^2))
rmse <- function(pred, truth) sqrt(mean((pred - truth)^2))

#' Mean absolute error: mean(|z_phot - z_spec|)
mae <- function(pred, truth) mean(abs(pred - truth))

#' Coefficient of determination: 1 - SS_res / SS_tot
r2 <- function(pred, truth) {
  1 - sum((truth - pred)^2) / sum((truth - mean(truth))^2)
}

#' Bias: mean(dz). Positive means redshifts are over-predicted.
bias <- function(pred, truth) mean(dz(pred, truth))

#' Robust scatter: sigma_NMAD = 1.4826 * median(|dz - median(dz)|)
#' 1.4826 makes it equal to the SD for Gaussian errors.
sigma_nmad <- function(pred, truth) {
  d <- dz(pred, truth)
  1.4826 * stats::median(abs(d - stats::median(d)))
}

#' Catastrophic outlier fraction: eta = mean(|dz| > 0.15)
eta <- function(pred, truth, threshold = 0.15) {
  mean(abs(dz(pred, truth)) > threshold)
}

#' All metrics as a one-row tibble
all_metrics <- function(pred, truth) {
  tibble::tibble(
    rmse       = rmse(pred, truth),
    mae        = mae(pred, truth),
    r2         = r2(pred, truth),
    bias       = bias(pred, truth),
    sigma_nmad = sigma_nmad(pred, truth),
    eta        = eta(pred, truth)
  )
}
