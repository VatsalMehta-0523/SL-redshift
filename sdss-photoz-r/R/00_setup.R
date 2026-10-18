# =============================================================================
# 00_setup.R — Shared setup: packages, constants, paths, helpers
# Inputs : none
# Outputs: project output directories; SEED, PATHS and SDSS constants
# Brief  : TASK.md §4 (supports every step); decisions D-013, D-014
# =============================================================================

# Packages every script needs. Modelling packages (caret, randomForest, ...)
# are loaded by the scripts that use them, so data collection works with a
# smaller install.
CORE_PACKAGES <- c(
  "readr", "dplyr", "tidyr", "ggplot2", "purrr",
  "here", "glue", "janitor", "knitr"
)

missing_pkgs <- CORE_PACKAGES[
  !vapply(CORE_PACKAGES, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_pkgs) > 0) {
  stop(
    "Missing R packages: ", paste(missing_pkgs, collapse = ", "), "\n",
    "Install them with renv::restore() or:\n  install.packages(c(",
    paste0('"', missing_pkgs, '"', collapse = ", "), "))",
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(purrr)
  library(glue)
})

# --- Constants ---------------------------------------------------------------

SEED <- 42L # D-014: use before every random operation

N_TARGET <- 100L # D-003: analysis dataset size
N_MIN <- 30L # TASK.md C1 lower limit
N_MAX <- 100L # TASK.md C1 upper limit

# --- Paths (always via here::here(); the .here file marks the project root) ---

PATHS <- list(
  sql         = here::here("data", "sql", "sdss_query.sql"),
  raw_dir     = here::here("data", "raw"),
  raw         = here::here("data", "raw", "sdss_raw.csv"),
  acquisition = here::here("data", "raw", "ACQUISITION.md"),
  processed   = here::here("data", "processed"),
  clean       = here::here("data", "processed", "sdss_clean.csv"),
  train       = here::here("data", "processed", "train.csv"),
  test        = here::here("data", "processed", "test.csv"),
  figures     = here::here("outputs", "figures"),
  tables      = here::here("outputs", "tables"),
  models      = here::here("outputs", "models"),
  logs        = here::here("outputs", "logs")
)

for (dir in PATHS[c("raw_dir", "processed", "figures", "tables", "models", "logs")]) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
}

# --- SDSS data contract (D-004, AGENTS.md §5) --------------------------------

# SqlSearch web service; DR18 first, DR17 as the fallback (D-004)
SKYSERVER_RELEASES <- c("dr18", "dr17")
SKYSERVER_URL <- "https://skyserver.sdss.org/{release}/SkyServerWS/SearchTools/SqlSearch"

# Columns of data/raw/sdss_raw.csv, in query order.
# zmag is the z-BAND magnitude; redshift is the target.
RAW_COLUMNS <- c(
  "objid", "u", "g", "r", "i", "zmag",
  "err_u", "err_g", "err_r", "err_i", "err_z",
  "redshift", "redshift_err", "ra", "dec"
)

# objid is a 64-bit integer: as a double it loses its last digits, so it is
# always read as text.
RAW_COL_TYPES <- readr::cols(
  objid = readr::col_character(),
  .default = readr::col_double()
)

# --- Shared helpers ----------------------------------------------------------

source(here::here("R", "utils_metrics.R"))
source(here::here("R", "utils_plot.R"))
