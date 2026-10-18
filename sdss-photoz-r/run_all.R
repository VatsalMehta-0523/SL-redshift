# =============================================================================
# run_all.R — Run the whole pipeline, workflow steps 1–7, in order
# Usage  : Rscript run_all.R   (from the sdss-photoz-r/ folder)
# Outputs: everything the scripts write, plus outputs/logs/run_log.txt and
#          outputs/logs/sessionInfo.txt (R and package versions)
# Brief  : TASK.md §5 (Definition of Done)
# =============================================================================
#
# Each script runs in its own fresh R process, exactly as if you had typed
# `Rscript R/0x_....R`, so no script can depend on objects left over from an
# earlier one. The run stops at the first script that fails.

source(here::here("R", "00_setup.R"))

SCRIPTS <- c(
  "01_acquire.R", "02_inspect_clean.R", "03_eda.R", "04_split.R",
  "05_train.R", "06_evaluate.R", "07_interpret.R"
)
rscript <- file.path(R.home("bin"), "Rscript")

log_lines <- c(glue("Pipeline run started {format(Sys.time(), '%Y-%m-%d %H:%M:%S')}"), "")
for (script in SCRIPTS) {
  message(glue("\n=== {script} ==="))
  start <- Sys.time()
  status <- system2(rscript, here::here("R", script))
  secs <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  log_lines <- c(log_lines, sprintf("%-20s %6.1f s  %s", script, secs,
                                    if (status == 0) "ok" else "FAILED"))
  if (status != 0) {
    writeLines(log_lines, file.path(PATHS$logs, "run_log.txt"))
    stop(glue("{script} failed (exit status {status}). See the messages above."),
         call. = FALSE)
  }
}

writeLines(c(log_lines, "", "All steps completed."), file.path(PATHS$logs, "run_log.txt"))
writeLines(capture.output(sessionInfo()), file.path(PATHS$logs, "sessionInfo.txt"))
message("\nAll steps completed. Timings: outputs/logs/run_log.txt")
