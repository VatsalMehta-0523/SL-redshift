# =============================================================================
# utils_plot.R — Report theme, model colours, figure/table/caption savers
# Spec: docs/REPORT_GUIDE.md (conventions), AGENTS.md §6–7
# =============================================================================

# Okabe-Ito colour-blind-safe palette
OKABE_ITO <- c(
  orange = "#E69F00", sky_blue = "#56B4E9", bluish_green = "#009E73",
  yellow = "#F0E442", blue = "#0072B2", vermillion = "#D55E00",
  reddish_purple = "#CC79A7", black = "#000000"
)

# Model IDs, labels and colours: defined once, used by every figure
MODEL_IDS <- c("M0_baseline", "M1_lm", "M2_knn", "M3_rf", "M4_svr", "M5_xgb")

MODEL_LABELS <- c(
  M0_baseline = "M0 Baseline",
  M1_lm       = "M1 Linear",
  M2_knn      = "M2 k-NN",
  M3_rf       = "M3 Random Forest",
  M4_svr      = "M4 SVR",
  M5_xgb      = "M5 XGBoost"
)

MODEL_COLOURS <- c(
  M0_baseline = unname(OKABE_ITO["black"]),
  M1_lm       = unname(OKABE_ITO["blue"]),
  M2_knn      = unname(OKABE_ITO["orange"]),
  M3_rf       = unname(OKABE_ITO["bluish_green"]),
  M4_svr      = unname(OKABE_ITO["vermillion"]),
  M5_xgb      = unname(OKABE_ITO["reddish_purple"])
)

# Filter colours, ordered blue -> red like the wavelengths (u -> z)
BAND_COLOURS <- c(
  u = unname(OKABE_ITO["reddish_purple"]),
  g = unname(OKABE_ITO["blue"]),
  r = unname(OKABE_ITO["bluish_green"]),
  i = unname(OKABE_ITO["orange"]),
  z = unname(OKABE_ITO["vermillion"])
)

# Display labels with a true minus sign
COLOUR_LABELS <- c(u_g = "u − g", g_r = "g − r", r_i = "r − i", i_z = "i − z")

#' ggplot theme for every report figure
theme_report <- function(base_size = 11) {
  ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey95"),
      plot.title       = ggplot2::element_text(face = "bold"),
      legend.position  = "bottom"
    )
}

#' Save a figure as outputs/figures/{id}_{name}.png (300 dpi) and .pdf
save_fig <- function(plot, id, name, width = 6.5, height = 4.5) {
  stem <- file.path(PATHS$figures, glue::glue("{id}_{name}"))
  ggplot2::ggsave(paste0(stem, ".png"), plot,
    width = width, height = height, dpi = 300
  )
  # cairo_pdf embeds Unicode symbols used in labels (Δ, Å, −)
  pdf_device <- if (capabilities("cairo")) grDevices::cairo_pdf else "pdf"
  ggplot2::ggsave(paste0(stem, ".pdf"), plot,
    width = width, height = height, device = pdf_device
  )
  invisible(stem)
}

#' Save a table as outputs/tables/{id}_{name}.csv and .md
save_table <- function(df, id, name, digits = 4) {
  stem <- file.path(PATHS$tables, glue::glue("{id}_{name}"))
  readr::write_csv(df, paste0(stem, ".csv"))
  md <- knitr::kable(df, format = "pipe", digits = digits)
  writeLines(md, paste0(stem, ".md"))
  invisible(stem)
}

#' Add or replace the draft caption for a figure in captions.md.
#' Replacing (not appending) keeps re-runs idempotent.
add_caption <- function(id, text) {
  path <- file.path(PATHS$figures, "captions.md")
  lines <- if (file.exists(path)) readLines(path, warn = FALSE) else "# Figure captions (drafts)"
  prefix <- glue::glue("- **{id}:**")
  lines <- lines[!startsWith(lines, prefix)]
  writeLines(c(lines, glue::glue("{prefix} {text}")), path)
}
