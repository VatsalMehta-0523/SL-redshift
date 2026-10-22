# The raw and cleaned data satisfy the brief and the data contract.

test_that("raw data is unchanged since acquisition (D-015)", {
  skip_if_not(file.exists(PATHS$acquisition), "ACQUISITION.md not found")
  record <- readLines(PATHS$acquisition, warn = FALSE, encoding = "UTF-8")
  recorded <- regmatches(record, regexpr("[0-9a-f]{32}", record))
  expect_length(recorded, 1)
  expect_equal(unname(tools::md5sum(PATHS$raw)), recorded)
})

clean <- read_processed(PATHS$clean)

test_that("analysis dataset has 30-100 rows, exactly 100 here (TASK.md C1, D-003)", {
  expect_gte(nrow(clean), N_MIN)
  expect_lte(nrow(clean), N_MAX)
  expect_equal(nrow(clean), N_TARGET)
})

test_that("clean data has the expected columns and no missing values", {
  expected <- c("objid", "u", "g", "r", "i", "zmag", "u_g", "g_r", "r_i", "i_z",
                "err_u", "err_g", "err_r", "err_i", "err_z",
                "redshift", "redshift_err", "ra", "dec")
  expect_named(clean, expected)
  expect_false(anyNA(clean))
})

test_that("objid is stored as intact 19-digit text and is unique", {
  expect_type(clean$objid, "character")
  expect_true(all(nchar(clean$objid) == 19))
  expect_false(anyDuplicated(clean$objid) > 0)
})

test_that("colours equal the magnitude differences (D-006)", {
  expect_equal(clean$u_g, clean$u - clean$g)
  expect_equal(clean$g_r, clean$g - clean$r)
  expect_equal(clean$r_i, clean$r - clean$i)
  expect_equal(clean$i_z, clean$i - clean$zmag)
})

test_that("derive_colours() computes the same colours as the cleaned file", {
  recomputed <- derive_colours(dplyr::select(clean, u, g, r, i, zmag))
  expect_equal(recomputed[c("u_g", "g_r", "r_i", "i_z")], clean[c("u_g", "g_r", "r_i", "i_z")])
})

test_that("values respect the query cuts and physical ranges (D-005)", {
  expect_true(all(clean$redshift > 0.01 & clean$redshift < 0.5))
  expect_true(all(clean$r >= 14 & clean$r <= 17.77))
  for (m in c("u", "g", "r", "i", "zmag")) {
    expect_true(all(clean[[m]] >= 10 & clean[[m]] <= 30), info = m)
  }
  for (e in c("err_u", "err_g", "err_r", "err_i", "err_z")) {
    expect_true(all(clean[[e]] < 0.2), info = e)
  }
})

test_that("every clean galaxy comes from the raw file with unchanged values", {
  raw <- read_processed(PATHS$raw)
  matched <- dplyr::inner_join(clean, raw, by = "objid", suffix = c("", "_raw"))
  expect_equal(nrow(matched), nrow(clean))
  expect_equal(matched$redshift, matched$redshift_raw)
  expect_equal(matched$u, matched$u_raw)
})
