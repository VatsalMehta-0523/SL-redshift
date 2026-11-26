# =============================================================================
# utils_clean.R — Cleaning rules shared by 02_inspect_clean.R (batch 1 -> v1)
#                 and 02b_extend_v2.R (batch 2 -> the 20 new v2 galaxies)
# =============================================================================
#
# The rules were proposed with an AI assistant and approved by the owner
# (docs/AI_USAGE.md AI-003, AI-004). Defining them once guarantees that the
# 20 galaxies added in v2 pass exactly the same checks as the original 100.

MAGNITUDES <- c("u", "g", "r", "i", "zmag")
ERRORS <- c("err_u", "err_g", "err_r", "err_i", "err_z")
COLOURS <- c("u_g", "g_r", "r_i", "i_z")

MAG_RANGE <- c(10, 30) # physically plausible apparent magnitudes
SENTINEL <- 9999 # SDSS marks missing photometry with -9999
MAD_K <- 5 # colour-outlier threshold: median ± 5·MAD

#' Append one rule to the cleaning log.
add_log <- function(log, step, rule, rows_before, rows_after, reason, details = "") {
  dplyr::bind_rows(log, tibble::tibble(
    step = step, rule = rule,
    rows_before = rows_before, rows_after = rows_after,
    rows_removed = rows_before - rows_after,
    reason = reason, details = details
  ))
}

#' TRUE where x lies outside centre ± k·scale. By default centre and scale are
#' the median and MAD of x itself. R's mad() is scaled by 1.4826, so 5·MAD is
#' about 5σ for Gaussian data but is not pulled by outliers. 02b passes the
#' frozen batch-1 centre and scale instead, so the threshold does not move.
mad_outlier <- function(x, k = MAD_K, centre = stats::median(x), scale = stats::mad(x)) {
  abs(x - centre) > k * scale
}

#' Median and MAD of each colour: the reference for the outlier rule.
colour_reference <- function(df) {
  cols <- derive_colours(df)
  tibble::tibble(
    colour = COLOURS,
    median = purrr::map_dbl(COLOURS, \(v) stats::median(cols[[v]])),
    mad = purrr::map_dbl(COLOURS, \(v) stats::mad(cols[[v]]))
  )
}

#' objids of rows with an NA or sentinel value in any numeric column.
bad_value_ids <- function(df) {
  numeric_cols <- setdiff(names(df), "objid")
  df |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(numeric_cols), \(x) is.na(x) | abs(x) >= SENTINEL)) |>
    dplyr::pull(objid)
}

#' objids of rows with an impossible magnitude or redshift.
out_of_range_ids <- function(df) {
  df |>
    dplyr::filter(
      dplyr::if_any(dplyr::all_of(MAGNITUDES), \(m) m < MAG_RANGE[1] | m > MAG_RANGE[2]) |
        redshift <= 0 | redshift >= 1
    ) |>
    dplyr::pull(objid)
}

#' Rows (with colours) flagged as colour outliers against a reference table
#' from colour_reference().
colour_outliers <- function(df, reference) {
  cols <- derive_colours(df)
  flag <- Reduce(`|`, purrr::map(COLOURS, \(v) {
    ref <- reference[reference$colour == v, ]
    mad_outlier(cols[[v]], centre = ref$median, scale = ref$mad)
  }))
  cols[flag, ]
}

#' Column order of every processed CSV.
order_clean_columns <- function(df) {
  df |>
    dplyr::arrange(objid) |>
    dplyr::select(objid, dplyr::all_of(MAGNITUDES), dplyr::all_of(COLOURS),
                  dplyr::all_of(ERRORS), redshift, redshift_err, ra, dec)
}
