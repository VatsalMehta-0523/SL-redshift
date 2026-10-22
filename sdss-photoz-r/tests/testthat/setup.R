# Runs once before the tests: load the project setup (paths, constants, helpers).
# Run all tests from the sdss-photoz-r/ folder with:
#   Rscript -e "testthat::test_dir('tests/testthat')"
source(here::here("R", "00_setup.R"))

read_processed <- function(path) {
  readr::read_csv(path, col_types = RAW_COL_TYPES, progress = FALSE)
}
