# =============================================================================
# 00_setup.R — Shared setup: packages, constants, paths, helpers
# Inputs : none
# Outputs: project output directories; SEED, VERSION, PATHS and SDSS constants
# Brief  : TASK.md §4 (supports every step); decisions D-013, D-014, D-018
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

N_MIN <- 30L # TASK.md C1 lower limit
N_MAX_BRIEF <- 100L # TASK.md C1 upper limit (v1 respects it; v2 is the D-018 extension)

# --- Dataset versions (D-018) ------------------------------------------------
#
# v1: the original, brief-compliant analysis (100 galaxies, 80 train / 20 test).
# v2: v1 plus 20 new galaxies from a second frozen SkyServer pull (batch 2).
#     The 20 new galaxies are added to the TRAINING set only; the 20 test
#     galaxies are exactly v1's, so v1 and v2 are compared on the same galaxies.
#
# Choose the version with the environment variable PHOTOZ_VERSION
# (PowerShell: $env:PHOTOZ_VERSION = "v1"). Default: the latest, v2.
# run_all.R runs both.

VERSIONS <- list(
  v1 = list(
    id = "v1", label = "v1 · 100 galaxies", n_total = 100L, n_train = 80L, n_test = 20L,
    batches = "batch1"
  ),
  v2 = list(
    id = "v2", label = "v2 · 120 galaxies", n_total = 120L, n_train = 100L, n_test = 20L,
    batches = c("batch1", "batch2"), n_new = 20L, base = "v1"
  )
)
LATEST_VERSION <- "v2"

PHOTOZ_VERSION <- Sys.getenv("PHOTOZ_VERSION", LATEST_VERSION)
if (!PHOTOZ_VERSION %in% names(VERSIONS)) {
  stop("PHOTOZ_VERSION must be one of: ", paste(names(VERSIONS), collapse = ", "),
       call. = FALSE)
}
VERSION <- VERSIONS[[PHOTOZ_VERSION]]
N_TARGET <- VERSION$n_total # analysis dataset size of the active version

# --- Raw batches (each one frozen after its first download, D-015) ----------

RAW_BATCHES <- list(
  batch1 = list(
    id = "batch1", n_query = 120L,
    sql = here::here("data", "sql", "sdss_query.sql"),
    raw = here::here("data", "raw", "sdss_raw.csv"),
    acquisition = here::here("data", "raw", "ACQUISITION.md")
  ),
  batch2 = list(
    id = "batch2", n_query = 30L,
    sql = here::here("data", "sql", "sdss_query_batch2.sql"),
    raw = here::here("data", "raw", "sdss_raw_batch2.csv"),
    acquisition = here::here("data", "raw", "ACQUISITION_batch2.md")
  )
)

# --- Paths (always via here::here(); the .here file marks the project root) ---

#' All paths of one dataset version. Raw data is shared by every version.
version_paths <- function(version = PHOTOZ_VERSION) {
  out <- here::here("outputs", version)
  processed <- here::here("data", "processed", version)
  list(
    sql         = RAW_BATCHES$batch1$sql,
    raw_dir     = here::here("data", "raw"),
    raw         = RAW_BATCHES$batch1$raw,
    acquisition = RAW_BATCHES$batch1$acquisition,
    processed   = processed,
    clean       = file.path(processed, "sdss_clean.csv"),
    train       = file.path(processed, "train.csv"),
    test        = file.path(processed, "test.csv"),
    figures     = file.path(out, "figures"),
    tables      = file.path(out, "tables"),
    models      = file.path(out, "models"),
    logs        = file.path(out, "logs"),
    run_logs    = here::here("outputs", "logs"),
    comparison  = here::here("outputs", "comparison")
  )
}

PATHS <- version_paths(PHOTOZ_VERSION)

for (dir in PATHS[c("raw_dir", "processed", "figures", "tables", "models", "logs", "run_logs")]) {
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
# always read as text. Used for the processed CSVs as well.
RAW_COL_TYPES <- readr::cols(
  objid = readr::col_character(),
  .default = readr::col_double()
)

# --- SDSS filters (README §3.3) ----------------------------------------------

# Effective wavelengths (Å) and approximate FWHM (Å, Fukugita et al. 1996)
SDSS_FILTERS <- tibble::tibble(
  band   = c("u", "g", "r", "i", "z"),
  lambda = c(3551, 4686, 6166, 7480, 8932),
  fwhm   = c(599, 1379, 1382, 1535, 1370)
)

BREAK_REST <- 4000 # rest-frame wavelength of the 4000 Å break (Å)

# --- Shared helpers ----------------------------------------------------------

source(here::here("R", "utils_data.R"))
source(here::here("R", "utils_metrics.R"))
source(here::here("R", "utils_plot.R"))
