# =============================================================================
# 01_acquire.R — Workflow step 1: obtain the SDSS galaxy dataset
# Inputs : data/sql/sdss_query.sql (batch 1), data/sql/sdss_query_batch2.sql (batch 2)
# Outputs: data/raw/sdss_raw.csv + ACQUISITION.md               (batch 1, v1 and v2)
#          data/raw/sdss_raw_batch2.csv + ACQUISITION_batch2.md  (batch 2, v2 only)
#          Each file is frozen after its first download (D-015).
# Brief  : TASK.md §4, step 1; decisions D-003, D-004, D-005, D-015, D-018
# =============================================================================
#
# Behaviour (for every raw batch the active version needs, VERSION$batches)
#   * sdss_raw.csv exists  -> never download again. Validate it, check its MD5
#                             against ACQUISITION.md, and write ACQUISITION.md
#                             if the file was downloaded by hand.
#   * sdss_raw.csv missing -> run the query through the SkyServer SqlSearch web
#                             service (DR18, then DR17). If both fail, stop and
#                             point to the manual download in README §5.
#   * Never generates or simulates data (AGENTS.md R3).

source(here::here("R", "00_setup.R"))

# --- Helpers -----------------------------------------------------------------

#' Read the SQL file as one line. Comments ("-- ...") are removed first,
#' because on a single line a comment would swallow the rest of the query.
read_query <- function(path) {
  sql <- readLines(path, warn = FALSE, encoding = "UTF-8")
  sql <- sub("--.*$", "", sql)
  gsub("\\s+", " ", trimws(paste(sql, collapse = " ")))
}

#' Send the query to SkyServer and return the response body as text.
#' SkyServer reports SQL errors as HTTP 500 with a JSON "ErrorMessage".
query_skyserver <- function(sql, release) {
  httr2::request(glue(SKYSERVER_URL)) |>
    httr2::req_url_query(cmd = sql, format = "csv") |>
    httr2::req_user_agent("sdss-photoz-r (university coursework)") |>
    httr2::req_timeout(180) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_error(body = function(resp) {
      tryCatch(httr2::resp_body_json(resp)$ErrorMessage, error = function(e) NULL)
    }) |>
    httr2::req_perform() |>
    httr2::resp_body_string()
}

#' Split the response into CSV lines and drop SkyServer's "#Table1" line
#' (README §5 step 4). Stops if the header is not the expected one.
response_to_csv_lines <- function(body) {
  lines <- strsplit(body, "\r?\n")[[1]]
  lines <- lines[nzchar(lines)]
  if (length(lines) > 0 && startsWith(lines[1], "#")) lines <- lines[-1]

  header <- if (length(lines) > 0) strsplit(lines[1], ",")[[1]] else character()
  if (!identical(header, RAW_COLUMNS)) {
    stop("Unexpected response from SkyServer:\n", substr(body, 1, 300), call. = FALSE)
  }
  if (length(lines) < 2) stop("SkyServer returned no rows.", call. = FALSE)
  lines
}

#' Try each release in turn; return the CSV lines and the release used.
download_raw <- function(sql) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop('Downloading needs the httr2 package: install.packages("httr2")', call. = FALSE)
  }
  for (release in SKYSERVER_RELEASES) {
    message(glue("Querying SkyServer {toupper(release)} (this takes ~15-60 s) ..."))
    lines <- tryCatch(
      response_to_csv_lines(query_skyserver(sql, release)),
      error = function(e) {
        message("  failed: ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(lines)) {
      return(list(lines = lines, release = release, url = glue(SKYSERVER_URL)))
    }
  }
  stop(
    "Could not download the data from SkyServer.\n",
    "Download it by hand (README §5) and save it as data/raw/sdss_raw.csv,\n",
    "then run this script again. Do NOT create the file any other way.",
    call. = FALSE
  )
}

#' Read the raw CSV with explicit column types. comment = "#" tolerates a
#' leftover "#Table1" line from a manual download.
read_raw <- function(path) {
  readr::read_csv(path, col_types = RAW_COL_TYPES, comment = "#", progress = FALSE)
}

#' Check columns, parsing problems and row count (TASK.md C1, D-003).
validate_raw <- function(raw, batch) {
  missing_cols <- setdiff(RAW_COLUMNS, names(raw))
  if (length(missing_cols) > 0) {
    stop("sdss_raw.csv is missing columns: ", paste(missing_cols, collapse = ", "),
      "\nWas the query in data/sql/sdss_query.sql used unchanged?",
      call. = FALSE
    )
  }
  if (nrow(readr::problems(raw)) > 0) {
    print(readr::problems(raw))
    stop("sdss_raw.csv has values that could not be parsed (see above).", call. = FALSE)
  }
  if (nrow(raw) < batch$n_query) {
    warning(glue(
      "{basename(batch$raw)} has {nrow(raw)} rows (query asked for {batch$n_query}). ",
      "Record this in DECISIONS.md."
    ), call. = FALSE)
  }
  invisible(raw)
}

#' MD5 recorded in ACQUISITION.md, or NA if the file has none.
recorded_md5 <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  hit <- regmatches(lines, regexpr("[0-9a-f]{32}", lines))
  if (length(hit) == 0) NA_character_ else hit[1]
}

#' Write data/raw/ACQUISITION.md, the provenance record for the frozen file.
write_acquisition_record <- function(batch, raw, release, url, method, when) {
  md5 <- unname(tools::md5sum(batch$raw))
  sql_lines <- readLines(batch$sql, warn = FALSE, encoding = "UTF-8")
  raw_name <- basename(batch$raw)

  record <- c(
    glue("# {basename(batch$acquisition)} — provenance of data/raw/{raw_name}"),
    "",
    "Written by `R/01_acquire.R`. Do not edit by hand. The raw file is frozen (D-015).",
    "",
    "| Item | Value |",
    "|---|---|",
    glue("| Date (UTC) | {format(when, '%Y-%m-%d %H:%M:%S', tz = 'UTC')} |"),
    glue("| Data release | {release} |"),
    glue("| Method | {method} |"),
    glue("| Endpoint | {url} |"),
    glue("| Rows | {nrow(raw)} |"),
    glue("| Columns | {paste(names(raw), collapse = ', ')} |"),
    glue("| MD5 of {raw_name} | `{md5}` |"),
    glue("| R version | {R.version.string} |"),
    "",
    glue("## Query (`data/sql/{basename(batch$sql)}`)"),
    "",
    "```sql",
    sql_lines,
    "```",
    "",
    "The query uses `ORDER BY NEWID()`, so re-running it returns *different*",
    glue("galaxies. This record and `{raw_name}` are the frozen copy (D-015).")
  )
  writeLines(record, batch$acquisition, useBytes = TRUE)
  message("Wrote ", batch$acquisition)
}

# --- Main --------------------------------------------------------------------

#' Validate a frozen batch, or download it if it does not exist yet.
acquire_batch <- function(batch) {
  raw_name <- basename(batch$raw)
  if (file.exists(batch$raw)) {
    message(glue("data/raw/{raw_name} exists. It is frozen (D-015): not downloading again."))
    raw <- validate_raw(read_raw(batch$raw), batch)

    if (file.exists(batch$acquisition)) {
      # The raw file must be byte-identical to the one recorded at download time
      md5_now <- unname(tools::md5sum(batch$raw))
      md5_then <- recorded_md5(batch$acquisition)
      if (!is.na(md5_then) && md5_now != md5_then) {
        stop(
          raw_name, " has changed since it was acquired (MD5 ", md5_now,
          " vs recorded ", md5_then, ").\nRaw data must never be edited (D-015). ",
          "Restore it from git, or record a new decision before replacing it.",
          call. = FALSE
        )
      }
      message("MD5 matches ", basename(batch$acquisition), ".")
    } else {
      # Manual download (README §5): the release and date are not known here
      write_acquisition_record(
        batch, raw,
        release = "unknown (manual download; fill in by hand if known)",
        url     = "SkyServer SQL Search web form (README §5)",
        method  = "Manual download via the SkyServer web form",
        when    = file.mtime(batch$raw)
      )
    }
  } else {
    result <- download_raw(read_query(batch$sql))

    # Write with "\n" line endings on every OS so the MD5 is reproducible
    con <- file(batch$raw, open = "wb")
    writeLines(result$lines, con, sep = "\n")
    close(con)
    message("Saved ", batch$raw)

    raw <- validate_raw(read_raw(batch$raw), batch)
    write_acquisition_record(
      batch, raw,
      release = toupper(result$release),
      url     = result$url,
      method  = "SkyServer SqlSearch web service via R/01_acquire.R (httr2)",
      when    = Sys.time()
    )
  }

  message(glue(
    "\n{raw_name}: {nrow(raw)} rows x {ncol(raw)} columns\n",
    "  redshift : {round(min(raw$redshift), 4)} to {round(max(raw$redshift), 4)}\n",
    "  r (mag)  : {round(min(raw$r), 2)} to {round(max(raw$r), 2)}\n",
    "  NA cells : {sum(is.na(raw))}\n",
    "  duplicate objid: {sum(duplicated(raw$objid))}",
    .trim = FALSE
  ))
  invisible(raw)
}

message(glue("Dataset version {VERSION$id}: raw batches {paste(VERSION$batches, collapse = ', ')}"))
for (b in VERSION$batches) acquire_batch(RAW_BATCHES[[b]])
