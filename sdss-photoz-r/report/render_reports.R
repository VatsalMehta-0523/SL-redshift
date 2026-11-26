# =============================================================================
# render_reports.R — Build the report for each dataset version (HTML + Word)
# Usage  : Rscript report/render_reports.R        (from the sdss-photoz-r/ folder)
# Outputs: report/report_v1_n100.html/.docx  (original, brief-compliant)
#          report/report_v2_n120.html/.docx  (v1 + 20 galaxies, with the v1-vs-v2 section)
# Brief  : TASK.md §5 (report renders to HTML and DOCX); decision D-018
# =============================================================================

OUT <- c(v1 = "report_v1_n100", v2 = "report_v2_n120")

for (v in names(OUT)) {
  message("Rendering ", v, " ...")
  rmarkdown::render(
    here::here("report", "report.Rmd"),
    params = list(version = v),
    output_format = "all",
    output_file = OUT[[v]],
    output_dir = here::here("report"),
    envir = new.env(),
    quiet = TRUE
  )
}
message("Wrote ", paste0("report/", OUT, ".{html,docx}", collapse = ", "))
