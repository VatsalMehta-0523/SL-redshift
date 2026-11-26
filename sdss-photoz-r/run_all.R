# =============================================================================
# run_all.R — Run the whole pipeline (workflow steps 1–7) for both dataset
#             versions, compare them, and export the web demo
# Usage  : Rscript run_all.R            (from the sdss-photoz-r/ folder)
#          Rscript run_all.R v2         (only one version; v2 needs v1's outputs)
# Outputs: everything the scripts write, plus outputs/logs/run_log.txt and
#          outputs/logs/sessionInfo.txt (R and package versions)
# Brief  : TASK.md §5 (Definition of Done); decision D-018 (versions)
# =============================================================================
#
# Each script runs in its own fresh R process, exactly as if you had typed
# `Rscript R/0x_....R`, so no script can depend on objects left over from an
# earlier one. The dataset version is passed to the child process through the
# PHOTOZ_VERSION environment variable. The run stops at the first failure.
#
#   v1 (100 galaxies): 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
#   v2 (120 galaxies): 01 → 02b → 03 → 04 → 05 → 06 → 07 → 08
#   then 09_compare_versions.R (v1 vs v2 on the same 20 test galaxies)

source(here::here("R", "00_setup.R"))

COMMON <- c("03_eda.R", "04_split.R", "05_train.R", "06_evaluate.R",
            "07_interpret.R", "08_export_web.R")
SCRIPTS <- list(
  v1 = c("01_acquire.R", "02_inspect_clean.R", COMMON),
  v2 = c("01_acquire.R", "02b_extend_v2.R", COMMON)
)

args <- commandArgs(trailingOnly = TRUE)
run_versions <- if (length(args) > 0) args else names(SCRIPTS)
stopifnot("Unknown version" = all(run_versions %in% names(SCRIPTS)))

rscript <- file.path(R.home("bin"), "Rscript")
log_path <- file.path(PATHS$run_logs, "run_log.txt")
log_lines <- c(glue("Pipeline run started {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}"), "")

run_script <- function(script, version) {
  message(glue("\n=== [{version}] {script} ==="))
  Sys.setenv(PHOTOZ_VERSION = version) # inherited by the child process
  start <- Sys.time()
  status <- system2(rscript, here::here("R", script))
  secs <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  log_lines <<- c(log_lines, sprintf("%-4s %-24s %6.1f s  %s", version, script, secs,
                                     if (status == 0) "ok" else "FAILED"))
  if (status != 0) {
    writeLines(log_lines, log_path)
    stop(glue("[{version}] {script} failed (exit status {status}). See the messages above."),
         call. = FALSE)
  }
}

for (version in run_versions) {
  for (script in SCRIPTS[[version]]) run_script(script, version)
}
run_script("09_compare_versions.R", LATEST_VERSION)
Sys.unsetenv("PHOTOZ_VERSION")

writeLines(c(log_lines, "", "All steps completed."), log_path)
writeLines(capture.output(sessionInfo()), file.path(PATHS$run_logs, "sessionInfo.txt"))
message("\nAll steps completed. Timings: outputs/logs/run_log.txt")
