# The raw and cleaned data satisfy the brief, the data contract and D-018.

for (b in RAW_BATCHES) {
  test_that(glue("raw {b$id} is unchanged since acquisition (D-015)"), {
    skip_if_not(file.exists(b$acquisition), glue("{basename(b$acquisition)} not found"))
    record <- readLines(b$acquisition, warn = FALSE, encoding = "UTF-8")
    recorded <- regmatches(record, regexpr("[0-9a-f]{32}", record))
    expect_length(recorded, 1)
    expect_equal(unname(tools::md5sum(b$raw)), recorded)
  })
}

raw_all <- dplyr::bind_rows(lapply(RAW_BATCHES, \(b) read_processed(b$raw)))

test_that("the two raw batches do not overlap", {
  expect_false(anyDuplicated(raw_all$objid) > 0)
})

for (v in names(VERSIONS)) {
  clean <- read_processed(version_paths(v)$clean)

  test_that(glue("{v}: analysis dataset has the planned size (TASK.md C1, D-003, D-018)"), {
    expect_gte(nrow(clean), N_MIN)
    expect_equal(nrow(clean), VERSIONS[[v]]$n_total)
    # v1 is the brief-compliant analysis; only the D-018 extension may exceed 100
    if (v == "v1") expect_lte(nrow(clean), N_MAX_BRIEF)
  })

  test_that(glue("{v}: clean data has the expected columns and no missing values"), {
    expected <- c("objid", "u", "g", "r", "i", "zmag", "u_g", "g_r", "r_i", "i_z",
                  "err_u", "err_g", "err_r", "err_i", "err_z",
                  "redshift", "redshift_err", "ra", "dec")
    expect_named(clean, expected)
    expect_false(anyNA(clean))
  })

  test_that(glue("{v}: objid is stored as intact 19-digit text and is unique"), {
    expect_type(clean$objid, "character")
    expect_true(all(nchar(clean$objid) == 19))
    expect_false(anyDuplicated(clean$objid) > 0)
  })

  test_that(glue("{v}: colours equal the magnitude differences (D-006)"), {
    expect_equal(clean$u_g, clean$u - clean$g)
    expect_equal(clean$g_r, clean$g - clean$r)
    expect_equal(clean$r_i, clean$r - clean$i)
    expect_equal(clean$i_z, clean$i - clean$zmag)
    recomputed <- derive_colours(dplyr::select(clean, u, g, r, i, zmag))
    expect_equal(recomputed[c("u_g", "g_r", "r_i", "i_z")], clean[c("u_g", "g_r", "r_i", "i_z")])
  })

  test_that(glue("{v}: values respect the query cuts and physical ranges (D-005)"), {
    expect_true(all(clean$redshift > 0.01 & clean$redshift < 0.5))
    expect_true(all(clean$r >= 14 & clean$r <= 17.77))
    for (m in c("u", "g", "r", "i", "zmag")) {
      expect_true(all(clean[[m]] >= 10 & clean[[m]] <= 30), info = m)
    }
    for (e in c("err_u", "err_g", "err_r", "err_i", "err_z")) {
      expect_true(all(clean[[e]] < 0.2), info = e)
    }
  })

  test_that(glue("{v}: every clean galaxy comes from a raw batch with unchanged values"), {
    matched <- dplyr::inner_join(clean, raw_all, by = "objid", suffix = c("", "_raw"))
    expect_equal(nrow(matched), nrow(clean))
    expect_equal(matched$redshift, matched$redshift_raw)
    expect_equal(matched$u, matched$u_raw)
    expect_equal(matched$zmag, matched$zmag_raw)
  })
}

test_that("v2 = all 100 v1 galaxies + exactly 20 new galaxies from batch 2 (D-018)", {
  v1 <- read_processed(version_paths("v1")$clean)
  v2 <- read_processed(version_paths("v2")$clean)
  new <- readr::read_csv(file.path(version_paths("v2")$processed, "new_galaxies.csv"),
                         col_types = "c")$objid
  batch2 <- read_processed(RAW_BATCHES$batch2$raw)
  expect_true(all(v1$objid %in% v2$objid))
  expect_setequal(setdiff(v2$objid, v1$objid), new)
  expect_length(new, VERSIONS$v2$n_new)
  expect_true(all(new %in% batch2$objid))
  # The v1 galaxies are carried over unchanged
  expect_equal(dplyr::filter(v2, objid %in% v1$objid), v1)
})
