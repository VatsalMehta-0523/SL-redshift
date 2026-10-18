# =============================================================================
# utils_data.R — Feature definitions shared by cleaning, training and the app
# =============================================================================

# Model inputs (D-006): four colours + r-band magnitude
FEATURES <- c("u_g", "g_r", "r_i", "i_z", "r")

#' Colours = differences of magnitudes = flux ratios (spectral shape).
derive_colours <- function(df) {
  df |> dplyr::mutate(
    u_g = u - g, # UV slope / Balmer-break region
    g_r = g - r, # 4000 Å break position: the main redshift signal
    r_i = r - i, # red continuum slope
    i_z = i - zmag # near-IR slope
  )
}
