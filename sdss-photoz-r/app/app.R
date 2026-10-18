# =============================================================================
# app/app.R — Interactive photometric-redshift predictor (Shiny)
# Run from the sdss-photoz-r/ folder:
#   Rscript -e "shiny::runApp('app', launch.browser = TRUE)"
# Needs the trained models from R/05_train.R (outputs/models/*.rds).
# =============================================================================
#
# The user enters five de-reddened SDSS magnitudes. The app derives the same
# colours used in training, predicts z with every trained model and checks
# whether the galaxy lies inside the range the models were trained on.

library(shiny)
source(here::here("R", "00_setup.R"))
source(here::here("R", "utils_predict.R"))

train <- read_csv(PATHS$train, col_types = RAW_COL_TYPES, progress = FALSE)
test <- read_csv(PATHS$test, col_types = RAW_COL_TYPES, progress = FALSE)
models <- load_models()
ranges <- training_ranges(train)

MAG_INPUTS <- c(u = "u", g = "g", r = "r", i = "i", z = "zmag")
G_BAND <- SDSS_FILTERS[SDSS_FILTERS$band == "g", ]
G_EDGES <- G_BAND$lambda + c(-1, 1) * G_BAND$fwhm / 2

# Real test-set galaxies as presets, so a prediction can be compared with the
# measured spectroscopic redshift
presets <- test |> arrange(redshift)
preset_choices <- c(
  "Custom (type your own values)" = "custom",
  set_names(presets$objid, sprintf("Test galaxy, z_spec = %.4f", presets$redshift))
)
defaults <- map_dbl(MAG_INPUTS, \(m) round(median(train[[m]]), 3))

COLOUR_LABELS_ALL <- c(COLOUR_LABELS, r = "r magnitude")

mag_input <- function(band) {
  numericInput(paste0("mag_", band), label = glue("{band} magnitude"),
               value = defaults[[band]], step = 0.01, min = 10, max = 30)
}

# --- UI ----------------------------------------------------------------------

ui <- fluidPage(
  tags$head(tags$style(HTML("
    .result-box { background:#f4f8fb; border-left:5px solid #009E73;
                  padding:12px 16px; margin-bottom:14px; }
    .result-z   { font-size:2.2em; font-weight:700; color:#009E73; }
    .warn-box   { background:#fff4e5; border-left:5px solid #D55E00;
                  padding:10px 14px; margin-bottom:14px; }
    .ok-box     { background:#eef7ee; border-left:5px solid #009E73;
                  padding:10px 14px; margin-bottom:14px; }
  "))),
  titlePanel("Galaxy redshift predictor (SDSS photometry)"),
  sidebarLayout(
    sidebarPanel(
      width = 4,
      p("Enter the five ", strong("de-reddened"), " SDSS magnitudes of a galaxy",
        " (", code("dered_u"), " … ", code("dered_z"), ") and press ",
        strong("Predict"), "."),
      selectInput("preset", "Start from", choices = preset_choices),
      mag_input("u"), mag_input("g"), mag_input("r"), mag_input("i"), mag_input("z"),
      actionButton("predict", "Predict redshift", class = "btn-success btn-lg",
                   width = "100%"),
      hr(),
      helpText(glue(
        "Models trained on {nrow(train)} SDSS DR18 galaxies with ",
        "{sprintf('%.3f', ranges$min[ranges$feature == 'redshift'])} ≤ z ≤ ",
        "{sprintf('%.3f', ranges$max[ranges$feature == 'redshift'])} and r ≤ 17.77. ",
        "Predictions outside this range are not reliable."
      ))
    ),
    mainPanel(
      width = 8,
      uiOutput("result"),
      uiOutput("validity"),
      fluidRow(
        column(6, h4("All models"), tableOutput("model_table")),
        column(6, h4("Derived colours"), tableOutput("colour_table"))
      ),
      h4("Where this galaxy sits among the training galaxies"),
      plotOutput("context_plot", height = "380px")
    )
  )
)

# --- Server ------------------------------------------------------------------

server <- function(input, output, session) {

  # Fill the inputs from a test-set galaxy
  observeEvent(input$preset, {
    if (input$preset == "custom") return()
    gal <- filter(presets, objid == input$preset)
    for (band in names(MAG_INPUTS)) {
      updateNumericInput(session, paste0("mag_", band), value = round(gal[[MAG_INPUTS[[band]]]], 3))
    }
  })

  # Predict only when the button is pressed
  prediction <- eventReactive(input$predict, {
    mags <- map_dbl(names(MAG_INPUTS), \(b) input[[paste0("mag_", b)]])
    validate(need(all(!is.na(mags)), "Please fill in all five magnitudes."))
    validate(need(all(mags >= 10 & mags <= 30),
                  "Magnitudes must be between 10 and 30 (physically plausible range)."))
    new <- as_tibble(as.list(set_names(mags, MAG_INPUTS)))
    res <- predict_redshift(new, models, ranges)
    # A preset is only "known" while its magnitudes are unchanged
    res$z_spec <- NA_real_
    if (input$preset != "custom") {
      gal <- filter(presets, objid == input$preset)
      same <- all(abs(unlist(gal[MAG_INPUTS]) - mags) < 0.0006)
      if (same) res$z_spec <- gal$redshift
    }
    res
  }, ignoreNULL = FALSE)

  output$result <- renderUI({
    res <- prediction()
    z <- res[[paste0("z_phot_", RECOMMENDED_MODEL)]]
    lambda_break <- BREAK_REST * (1 + z)
    in_g <- lambda_break >= G_EDGES[1] && lambda_break <= G_EDGES[2]
    div(class = "result-box",
      div(glue("Predicted redshift ({MODEL_LABELS[[RECOMMENDED_MODEL]]}, recommended)")),
      div(class = "result-z", sprintf("z = %.4f", z)),
      if (!is.na(res$z_spec)) {
        div(sprintf("Measured (spectroscopic) z = %.4f · error Δz/(1+z) = %+.4f",
                    res$z_spec, (z - res$z_spec) / (1 + res$z_spec)))
      },
      div(style = "margin-top:6px; color:#444;",
        sprintf("At this redshift the 4000 Å break is observed at %.0f Å, %s.",
                lambda_break,
                if (in_g) "inside the g band, so the galaxy's g − r colour carries the redshift signal"
                else "outside the g band covered by the training data"))
    )
  })

  output$validity <- renderUI({
    res <- prediction()
    if (res$in_training_range) {
      div(class = "ok-box", "✔ All colours and the r magnitude lie inside the training range.")
    } else {
      bad <- strsplit(res$outside_features, ", ")[[1]]
      div(class = "warn-box",
        strong("⚠ Outside the training range: "),
        paste0(paste(COLOUR_LABELS_ALL[bad], collapse = ", "), ". "),
        "The models are extrapolating, so treat the prediction with caution. ",
        "Linear regression and SVR can even return negative (unphysical) redshifts; ",
        "the random forest cannot leave the training range.")
    }
  })

  output$model_table <- renderTable({
    res <- prediction()
    tibble::tibble(
      Model = unname(MODEL_LABELS[PREDICT_MODELS]),
      `Predicted z` = map_dbl(PREDICT_MODELS, \(id) res[[paste0("z_phot_", id)]]),
      Note = ifelse(PREDICT_MODELS == RECOMMENDED_MODEL, "recommended",
                    ifelse(map_dbl(PREDICT_MODELS, \(id) res[[paste0("z_phot_", id)]]) < 0,
                           "unphysical (z < 0)", ""))
    )
  }, digits = 4, striped = TRUE)

  output$colour_table <- renderTable({
    res <- prediction()
    feature_ranges <- filter(ranges, feature %in% FEATURES)
    tibble::tibble(
      Feature = unname(COLOUR_LABELS_ALL[feature_ranges$feature]),
      Value = map_dbl(feature_ranges$feature, \(f) res[[f]]),
      `Training range` = sprintf("%.3f – %.3f", feature_ranges$min, feature_ranges$max),
      OK = ifelse(Value < feature_ranges$min | Value > feature_ranges$max, "✘", "✔")
    )
  }, digits = 3, striped = TRUE)

  output$context_plot <- renderPlot({
    res <- prediction()
    preds <- tibble::tibble(
      model = PREDICT_MODELS,
      z = map_dbl(PREDICT_MODELS, \(id) res[[paste0("z_phot_", id)]])
    )
    p <- ggplot(train, aes(redshift, g_r))
    if (any(preds$z < 0)) {
      # Redshifts below zero are unphysical for these receding galaxies
      p <- p + annotate("rect", xmin = -Inf, xmax = 0, ymin = -Inf, ymax = Inf,
                        fill = OKABE_ITO["vermillion"], alpha = 0.08) +
        annotate("text", x = min(preds$z), y = max(train$g_r), label = "z < 0\nunphysical",
                 hjust = 0, vjust = 1, size = 3.8, colour = OKABE_ITO["vermillion"])
    }
    p <- p +
      geom_point(colour = "grey65", size = 2) +
      geom_hline(yintercept = res$g_r, linetype = "dashed", colour = "grey30") +
      geom_point(data = preds, aes(z, res$g_r, colour = model), size = 5) +
      scale_colour_manual(values = MODEL_COLOURS, labels = MODEL_LABELS, name = "Prediction") +
      labs(x = "Redshift  z", y = "Colour  g − r  (mag)",
           subtitle = "Grey: training galaxies (spectroscopic z). Dashed line: this galaxy's g − r.") +
      theme_report(base_size = 13) +
      theme(legend.position = "right")
    if (!is.na(res$z_spec)) {
      p <- p + annotate("point", x = res$z_spec, y = res$g_r, shape = 4, size = 6,
                        stroke = 1.5, colour = "black") +
        labs(caption = "×  measured spectroscopic redshift")
    }
    p
  })
}

shinyApp(ui, server)
