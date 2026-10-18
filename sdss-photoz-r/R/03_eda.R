# =============================================================================
# 03_eda.R — Workflow step 3: explore the imported dataset (EDA)
# Inputs : data/processed/sdss_clean.csv
# Outputs: outputs/tables/T01_dataset_summary.csv/.md,
#          outputs/figures/F01–F06, F20 (.png + .pdf), captions.md
# Brief  : TASK.md §4, step 3; spec docs/REPORT_GUIDE.md §2A
# =============================================================================
#
# Descriptive only: no model is fitted and nothing is chosen from these plots.
# They describe the full 100-galaxy sample before the split, as is standard
# for a data section.

source(here::here("R", "00_setup.R"))

clean <- read_csv(PATHS$clean, col_types = RAW_COL_TYPES, progress = FALSE)
stopifnot(nrow(clean) >= N_MIN, nrow(clean) <= N_MAX)
n <- nrow(clean)

COLOURS <- names(COLOUR_LABELS)
FEATURES <- c(COLOURS, "r") # D-006

z_lab <- "Spectroscopic redshift  z_spec"
z_min <- min(clean$redshift)
z_max <- max(clean$redshift)

# --- T01: dataset summary ----------------------------------------------------

t01 <- clean |>
  select(u, g, r, i, zmag, all_of(COLOURS), redshift) |>
  pivot_longer(everything(), names_to = "variable") |>
  mutate(variable = factor(variable, levels = unique(variable))) |>
  group_by(variable) |>
  summarise(
    n = n(), mean = mean(value), sd = sd(value), min = min(value),
    median = median(value), max = max(value), .groups = "drop"
  ) |>
  mutate(variable = as.character(variable))
save_table(t01, "T01", "dataset_summary")

# --- F01: redshift distribution ----------------------------------------------

f01 <- ggplot(clean, aes(redshift)) +
  geom_histogram(aes(y = after_stat(density)), bins = 20,
                 fill = "grey80", colour = "grey40") +
  geom_density(colour = OKABE_ITO["blue"], linewidth = 1) +
  geom_rug(alpha = 0.5) +
  labs(x = z_lab, y = "Density",
       title = glue("Redshift distribution of the sample (n = {n})")) +
  theme_report()
save_fig(f01, "F01", "redshift_hist", 6.5, 4.5)
add_caption("F01", glue(
  "Spectroscopic redshifts of the {n} SDSS galaxies: histogram, kernel ",
  "density and rug. Range {round(z_min, 3)}–{round(z_max, 3)}, median ",
  "{round(median(clean$redshift), 3)}."
))

# --- F02: magnitude distributions --------------------------------------------

mags <- clean |>
  select(u, g, r, i, z = zmag) |>
  pivot_longer(everything(), names_to = "band", values_to = "mag") |>
  mutate(band = factor(band, levels = SDSS_FILTERS$band))

f02 <- ggplot(mags, aes(mag, colour = band, fill = band)) +
  geom_density(alpha = 0.15, linewidth = 0.9) +
  geom_vline(xintercept = 17.77, linetype = "dashed") +
  annotate("text", x = 17.77, y = Inf, label = "r = 17.77 limit",
           hjust = -0.05, vjust = 1.5, size = 3.2) +
  scale_colour_manual(values = BAND_COLOURS, name = "Filter") +
  scale_fill_manual(values = BAND_COLOURS, name = "Filter") +
  labs(x = "De-reddened magnitude (mag)", y = "Density",
       title = "Magnitude distributions in the five SDSS filters") +
  theme_report()
save_fig(f02, "F02", "magnitude_dists", 7, 5)
add_caption("F02", glue(
  "Distributions of de-reddened u, g, r, i, z magnitudes for the {n} galaxies. ",
  "Galaxies are fainter in u (larger magnitude) and brighter towards the red. ",
  "The dashed line marks the Main Galaxy Sample limit r = 17.77 used in the query."
))

# --- F03: colour–colour diagram ----------------------------------------------

f03 <- ggplot(clean, aes(g_r, u_g, colour = redshift)) +
  geom_point(size = 2.3, alpha = 0.9) +
  scale_colour_viridis_c(name = "z_spec") +
  labs(x = "Colour  g − r  (mag)", y = "Colour  u − g  (mag)",
       title = "Colour–colour diagram coloured by redshift") +
  theme_report() +
  theme(legend.position = "right")
save_fig(f03, "F03", "colour_colour", 6.5, 5)
add_caption("F03", glue(
  "u − g versus g − r for the {n} galaxies, coloured by spectroscopic ",
  "redshift. Higher-redshift galaxies sit at redder g − r."
))

# --- F04: colours vs redshift (key physics figure) ---------------------------

colour_long <- clean |>
  select(redshift, all_of(COLOURS)) |>
  pivot_longer(-redshift, names_to = "colour", values_to = "value") |>
  mutate(colour = factor(colour, levels = COLOURS, labels = COLOUR_LABELS))

colour_cor <- map_dbl(COLOURS, \(v) cor(clean[[v]], clean$redshift))
names(colour_cor) <- COLOURS
cor_text <- tibble::tibble(
  colour = factor(COLOUR_LABELS, levels = COLOUR_LABELS),
  label = sprintf("r = %.2f", colour_cor)
)

f04 <- ggplot(colour_long, aes(redshift, value)) +
  geom_point(alpha = 0.6, size = 1.6) +
  geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
              colour = OKABE_ITO["vermillion"], fill = "grey75") +
  geom_text(data = cor_text, aes(x = -Inf, y = Inf, label = label),
            hjust = -0.15, vjust = 1.5, size = 3.4) +
  facet_wrap(~colour, scales = "free_y") +
  labs(x = z_lab, y = "Colour (mag)",
       title = "Galaxy colours versus redshift (LOESS fits, Pearson r)") +
  theme_report()
save_fig(f04, "F04", "colour_vs_redshift", 7, 5)
# The caption states which colour leads, read from the data (AGENTS.md R7)
top_colour <- names(which.max(colour_cor))
physics_note <- if (top_colour == "g_r") {
  ": it reddens as the 4000 Å break moves through the g band"
} else {
  ""
}
add_caption("F04", glue(
  "Colours of {n} SDSS galaxies versus spectroscopic redshift. Solid lines ",
  "are LOESS fits with 95% bands; r is the Pearson correlation. ",
  "{COLOUR_LABELS[top_colour]} has the strongest correlation ",
  "(r = {sprintf('%.2f', colour_cor[top_colour])}){physics_note}."
))

# --- F05: correlation heatmap ------------------------------------------------

cor_vars <- c(FEATURES, "redshift")
cor_labels <- c(COLOUR_LABELS, r = "r", redshift = "z_spec")
cor_mat <- cor(clean[cor_vars])
cor_long <- as.data.frame(as.table(cor_mat)) |>
  rename(x = Var1, y = Var2, rho = Freq) |>
  mutate(
    x = factor(x, levels = cor_vars, labels = cor_labels[cor_vars]),
    y = factor(y, levels = rev(cor_vars), labels = cor_labels[rev(cor_vars)])
  )

f05 <- ggplot(cor_long, aes(x, y, fill = rho)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", rho),
                colour = abs(rho) > 0.6), size = 3.6, show.legend = FALSE) +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "black")) +
  scale_fill_gradient2(low = OKABE_ITO["blue"], mid = "white",
                       high = OKABE_ITO["vermillion"],
                       limits = c(-1, 1), name = "Pearson r") +
  coord_equal() +
  labs(x = NULL, y = NULL, title = "Correlations among features and redshift") +
  theme_report() +
  theme(panel.grid = element_blank(), legend.position = "right")
save_fig(f05, "F05", "correlation_heatmap", 6, 5)

z_cor <- cor_mat[FEATURES, "redshift"]
top <- names(which.max(abs(z_cor)))
add_caption("F05", glue(
  "Pearson correlations among the five features and z_spec. The feature most ",
  "correlated with redshift is {cor_labels[top]} (r = {round(z_cor[top], 2)})."
))

# --- F06: r magnitude vs redshift --------------------------------------------

r_cor <- cor(clean$r, clean$redshift)
f06 <- ggplot(clean, aes(redshift, r)) +
  geom_hline(yintercept = 17.77, linetype = "dashed") +
  geom_point(alpha = 0.7, size = 2) +
  geom_smooth(method = "loess", formula = y ~ x, se = TRUE,
              colour = OKABE_ITO["vermillion"], fill = "grey75") +
  annotate("text", x = -Inf, y = 17.77, label = "flux limit r = 17.77",
           hjust = -0.1, vjust = 1.5, size = 3.2) +
  scale_y_reverse() +
  labs(x = z_lab, y = "r magnitude (mag; brighter is up)",
       title = sprintf("Apparent brightness versus redshift (Pearson r = %.2f)", r_cor)) +
  theme_report()
save_fig(f06, "F06", "r_mag_vs_redshift", 6.5, 4.5)
add_caption("F06", glue(
  "r-band magnitude versus spectroscopic redshift with a LOESS fit. More ",
  "distant galaxies are fainter on average (inverse-square law); the dashed ",
  "line is the r = 17.77 flux limit of the sample. Pearson r = {sprintf('%.2f', r_cor)}."
))

# --- F20: the 4000 Å break moving through the SDSS filters -------------------

bands <- SDSS_FILTERS |>
  mutate(lo = lambda - fwhm / 2, hi = lambda + fwhm / 2,
         band = factor(band, levels = band))
break_line <- tibble::tibble(z = seq(0, 0.5, by = 0.005),
                             lambda_obs = BREAK_REST * (1 + z))

# Redshift at which the break leaves the g band (upper FWHM edge)
g_hi <- bands$hi[bands$band == "g"]
z_leave_g <- g_hi / BREAK_REST - 1

f20 <- ggplot() +
  geom_rect(data = bands, aes(xmin = -Inf, xmax = Inf, ymin = lo, ymax = hi,
                              fill = band), alpha = 0.25) +
  geom_text(data = bands, aes(x = 0.012, y = lambda, label = band),
            fontface = "bold", size = 4.5) +
  annotate("rect", xmin = z_min, xmax = z_max, ymin = -Inf, ymax = Inf,
           alpha = 0.15, fill = "black") +
  annotate("text", x = (z_min + z_max) / 2, y = 9900,
           label = "this sample", size = 3.4) +
  geom_line(data = break_line, aes(z, lambda_obs), linewidth = 1.2) +
  scale_fill_manual(values = BAND_COLOURS, guide = "none") +
  scale_x_continuous(limits = c(0, 0.5), expand = c(0, 0)) +
  scale_y_continuous(limits = c(3000, 10000)) +
  labs(x = "Redshift  z",
       y = "Observed wavelength (Å)",
       title = "Observed 4000 Å break, 4000(1 + z), across the SDSS filters") +
  theme_report()
save_fig(f20, "F20", "break_vs_filters", 6.5, 4.5)
add_caption("F20", glue(
  "Observed wavelength of the 4000 Å break, 4000(1 + z) Å (black line), over ",
  "the SDSS filter bands (shaded: effective wavelength ± FWHM/2, approximate). ",
  "The grey band marks this sample (z = {round(z_min, 3)}–{round(z_max, 3)}), ",
  "where the break lies at {round(BREAK_REST * (1 + z_min))}–",
  "{round(BREAK_REST * (1 + z_max))} Å, inside the g band. It would leave g ",
  "only at z ≈ {round(z_leave_g, 2)}."
))

message(glue("EDA done: T01 + 7 figures for n = {n} galaxies."))
