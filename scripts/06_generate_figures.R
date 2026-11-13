# Figures only: read saved analysis results; do not calculate tests or write data.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(dplyr)
library(tidyr)
library(ggplot2)
library(sf)
library(grid)

periods <- c('Pre', 'Pandemic', 'Post')
period_colors <- c(Pre = '#3478A4', Pandemic = '#D78A32', Post = '#8754A0')
period_names <- c(Pre = 'Pre-pandemic\n2014-15 to 2019-20',
  Pandemic = 'Pandemic\n2020-21 to 2022-23', Post = 'Post-pandemic\n2023-24 to 2025-26')
theme_set(theme_minimal(base_size = 12) + theme(panel.grid.minor = element_blank(),
  plot.title = element_text(face = 'bold', size = 15), strip.text = element_text(face = 'bold'),
  legend.position = 'bottom', plot.caption = element_text(hjust = 0, size = 9),
  plot.margin = margin(10, 18, 10, 10)))

# Four combined county-map figures, each showing all three periods.
folder <- 'figures'
dir.create(folder, recursive = TRUE, showWarnings = FALSE)
shapes <- st_read('raw_data/il_counties.gpkg', quiet = TRUE)
county_periods <- read.csv('processed_data/county_period_measures.csv',
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
county_periods$period <- factor(county_periods$period, levels = periods)
metric_labels <- c(gap = 'Median-P10 gap', weighted_sd = 'Enrollment-weighted SD',
  mad = 'Median absolute deviation (MAD)', sd = 'Unweighted standard deviation (SD)')
colors <- c('1_1' = '#F7D6C4', '2_1' = '#D7C9E2', '3_1' = '#8DC7E2',
  '1_2' = '#F2A271', '2_2' = '#AD8CC4', '3_2' = '#438CC2',
  '1_3' = '#BB302D', '2_3' = '#7950A6', '3_3' = '#145A91')
for (metric in names(metric_labels)) {
  data <- county_periods %>% transmute(county, period, code = .data[[paste0(metric, '_map_code')]])
  cuts <- c(county_periods[[paste0(metric, '_lower_cutoff')]][1],
    county_periods[[paste0(metric, '_upper_cutoff')]][1])
  map_tables <- list()
  for (period in periods) {
    map_tables[[period]] <- shapes %>% left_join(data %>%
      filter(.data$period == .env$period) %>% select(county, code), by = 'county') %>%
      mutate(period = factor(period, levels = periods))
  }
  maps <- bind_rows(map_tables)
  legend_data <- expand.grid(coverage = 1:3, disparity = 1:3) %>%
    mutate(code = paste(coverage, disparity, sep = '_'))
  legend <- ggplot(legend_data, aes(coverage, disparity, fill = code)) +
    geom_tile(color = 'white', linewidth = .5) + scale_fill_manual(values = colors, guide = 'none') +
    scale_x_continuous(breaks = 1:3, labels = c('Low\n<95%', 'Medium\n95-<97%', 'High\n>=97%'),
      position = 'top', expand = c(0, 0)) +
    scale_y_continuous(breaks = 1:3, labels = c(paste0('Low\n<', sprintf('%.3f', cuts[1]), ' pp'),
      paste0('Medium\n', sprintf('%.3f', cuts[1]), '-<', sprintf('%.3f', cuts[2]), ' pp'),
      paste0('High\n>=', sprintf('%.3f', cuts[2]), ' pp')), expand = c(0, 0)) +
    coord_fixed() + labs(x = 'County-average coverage', y = 'School-to-school disparity') +
    theme_minimal(base_size = 10) + theme(panel.grid = element_blank(),
      axis.text = element_text(color = '#172536'), axis.title = element_text(face = 'bold'),
      axis.title.x = element_text(margin = margin(b = 10)), plot.margin = margin(14, 8, 14, 16))
  p <- ggplot(maps) + geom_sf(aes(fill = code), color = 'white', linewidth = .13) +
    facet_wrap(~period, nrow = 1, labeller = as_labeller(period_names)) +
    scale_fill_manual(values = colors, guide = 'none', na.value = '#D1D5DB') + theme_void(base_size = 12) +
    theme(strip.text = element_text(face = 'bold', size = 11), plot.margin = margin(10, 8, 8, 8))
  if (metric == 'gap') { gap_legend <- legend; gap_maps <- p }  # reused in the summary figure
  file <- file.path(folder, paste0(metric, '_three_periods.png'))
  png(file, width = 14, height = 7.5, units = 'in', res = 180, bg = 'white')
  grid.newpage()
  grid.text(metric_labels[metric], x = .5, y = .96, gp = gpar(fontsize = 17, fontface = 'bold', col = '#172536'))
  print(legend, vp = viewport(x = .18, y = .49, width = .35, height = .72))
  print(p, vp = viewport(x = .675, y = .49, width = .64, height = .80))
  grid.text('Disparity cutoffs: pre-pandemic thirds, fixed across periods. pp = percentage points. Grey = incomplete county data.',
    x = .5, y = .035, gp = gpar(fontsize = 9, col = '#475569'))
  dev.off()
}

cohort <- read.csv('processed_data/school_changes.csv', colClasses = c(id = 'character'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
cohort$baseline_group <- factor(cohort$baseline_group, levels = c('<90%', '90-<95%', '95-<97%', '>=97%'))
cohort$size_group <- factor(cohort$size_group, levels = c('<250', '250-499', '500-999', '>=1,000'))
  # Test results from script 05: Friedman p (Holm across metrics) in panel titles,
  # paired Wilcoxon p (Holm within metric) on brackets.
  stats <- read.csv('processed_data/statistical_results.csv', na.strings = c('', 'NA'), fileEncoding = 'UTF-8') %>%
    filter(analysis == 'period_changes', metric %in% c('gap', 'weighted_sd', 'mad', 'sd'))
  format_p <- function(p) ifelse(p < .001, 'p < 0.001', paste('p =', sprintf('%.3f', p)))
  friedman <- stats %>% filter(method == 'Friedman')
  metric_names <- c(gap = 'Median - P10 gap', weighted_sd = 'Enrollment-weighted SD',
    mad = 'Median absolute deviation', sd = 'Unweighted SD')
  panel_names <- setNames(paste0(metric_names[friedman$metric], '\nFriedman ', format_p(friedman$p_holm_across_metrics)),
    friedman$metric)[names(metric_names)]
  data <- county_periods %>% filter(included_county) %>%
    pivot_longer(c(gap, weighted_sd, mad, sd), names_to = 'metric', values_to = 'value') %>%
    mutate(metric = factor(metric, levels = names(metric_names), labels = panel_names))
  top <- data %>% group_by(metric) %>% summarise(top = max(value, na.rm = TRUE), .groups = 'drop')
  brackets <- stats %>% filter(method != 'Friedman') %>%
    mutate(x = c('Pandemic - Pre' = 1, 'Post - Pre' = 1, 'Post - Pandemic' = 2)[comparison],
      xend = c('Pandemic - Pre' = 2, 'Post - Pre' = 3, 'Post - Pandemic' = 3)[comparison],
      level = c('Pandemic - Pre' = 1, 'Post - Pandemic' = 2, 'Post - Pre' = 3)[comparison],
      metric = factor(panel_names[metric], levels = panel_names), label = format_p(p_holm)) %>%
    left_join(top, by = 'metric') %>% mutate(y = top * (1 + .09 * level), tick = top * .02)
  p <- ggplot(data, aes(period, value, fill = period)) + geom_boxplot(outlier.shape = NA, alpha = .55) +
    geom_point(position = position_jitter(width = .08, height = 0, seed = 18), alpha = .35, size = .7) +
    geom_segment(data = brackets, aes(x = x, xend = xend, y = y, yend = y), inherit.aes = FALSE) +
    geom_segment(data = brackets, aes(x = x, xend = x, y = y, yend = y - tick), inherit.aes = FALSE) +
    geom_segment(data = brackets, aes(x = xend, xend = xend, y = y, yend = y - tick), inherit.aes = FALSE) +
    geom_text(data = brackets, aes(x = (x + xend) / 2, y = y, label = label), vjust = -.4, size = 3, inherit.aes = FALSE) +
    facet_wrap(~metric, scales = 'free_y', ncol = 2) + scale_fill_manual(values = period_colors, guide = 'none') +
    labs(title = 'School-to-school disparities within the same counties',
      subtitle = paste(n_distinct(county_periods$county[county_periods$included_county]), 'counties; each county contributes one value per period'),
      x = NULL, y = 'Percentage points',
      caption = 'Period values average annual metrics; counties have equal weight. Brackets: paired Wilcoxon, Holm-adjusted within metric. Friedman: Holm-adjusted across metrics.') +
    scale_y_continuous(expand = expansion(mult = c(.03, .08)))
  ggsave(file.path(folder, 'period_boxplots.png'), p, width = 11, height = 8, dpi = 180, bg = 'white')
  # Gap panel only, reused in the summary figure: keep gap rows in every layer.
  gap_box <- p
  gap_box$data <- filter(gap_box$data, metric == panel_names['gap'])
  for (i in seq_along(gap_box$layers)) {
    if (is.data.frame(gap_box$layers[[i]]$data))
      gap_box$layers[[i]]$data <- filter(gap_box$layers[[i]]$data, metric == panel_names['gap'])
  }

  # Kernel density of school coverage; same schools as the distribution table in script 04.
  # Weights give each year equal weight within a period (students: enrollment share of that year).
  schools <- read.csv('processed_data/school_year_data.csv', na.strings = c('', 'NA'), fileEncoding = 'UTF-8') %>%
    filter(exclusion == 'Included', county %in% county_periods$county[county_periods$included_county]) %>%
    mutate(period = factor(period, levels = periods)) %>% group_by(year) %>%
    mutate(school_w = 1 / n(), student_w = ifelse(valid_enrollment, enrollment, 0) /
      sum(enrollment[valid_enrollment])) %>%
    group_by(period) %>% mutate(school_w = school_w / sum(school_w), student_w = student_w / sum(student_w)) %>%
    ungroup()
  for (type in c('school', 'student')) {
    # Overlapping kernel densities, bounded at 0-100%, zoomed to 70-100%.
    p <- ggplot(schools, aes(coverage, after_stat(density * 100), weight = .data[[paste0(type, '_w')]],
        fill = period, color = period)) +
      geom_density(bounds = c(0, 100), adjust = 4, alpha = .25, linewidth = .8) +
      scale_fill_manual(values = period_colors, labels = gsub('\n', ' ', period_names), name = NULL) +
      scale_color_manual(values = period_colors, labels = gsub('\n', ' ', period_names), name = NULL) +
      scale_x_continuous(breaks = seq(70, 100, 5), expand = c(0, 0)) +
      coord_cartesian(xlim = c(70, 100)) +
      labs(title = if (type == 'school') 'Distribution of school coverage' else 'Enrollment distribution by school coverage',
        x = 'School measles coverage (%)',
        y = if (type == 'school') 'Schools (%)' else 'Students (%)')
    if (type == 'student') student_density <- p  # reused in the summary figure
    ggsave(file.path(folder, paste0(type, '_coverage_distribution.png')), p, width = 10, height = 7, dpi = 180, bg = 'white')
  }
  changes <- cohort %>% pivot_longer(c(pandemic_decline, post_decline),
    names_to = 'followup', values_to = 'decline') %>%
    mutate(followup = factor(followup, levels = c('pandemic_decline', 'post_decline'),
      labels = c('Pandemic vs Pre', 'Post vs Pre')))
  for (variable in c('baseline_group', 'size_group')) {
    data <- changes %>% filter(!is.na(.data[[variable]]))
    p <- ggplot(data, aes(.data[[variable]], decline, fill = followup)) +
      geom_hline(yintercept = 0, lty = 2, color = 'grey40') + geom_boxplot(outlier.alpha = .15, outlier.size = .6) +
      scale_fill_manual(values = c('#D78A32', '#8754A0')) +
      labs(title = if (variable == 'baseline_group') 'Decline by pre-pandemic coverage' else 'Decline by pre-pandemic school size',
        subtitle = paste(nrow(cohort), 'matched schools; >=3 pre years and all 3 years in each follow-up period'),
        x = if (variable == 'baseline_group') 'Fixed baseline coverage group' else 'Fixed baseline enrollment group',
        y = 'Decline from baseline (percentage points)', fill = NULL,
        caption = 'Positive = lower coverage; negative = improvement. Baseline = available pre-pandemic years, not a single year.')
    if (variable == 'baseline_group') baseline_box <- p  # reused in the summary figure
    filename <- if (variable == 'baseline_group') 'baseline_coverage_declines' else 'school_size_declines'
    ggsave(file.path(folder, paste0(filename, '.png')), p, width = 10, height = 6, dpi = 180, bg = 'white')
  }

# Stacked bars: share of students in each school coverage category, by year.
student_shares <- read.csv('processed_data/student_percentages.csv', fileEncoding = 'UTF-8') %>%
  pivot_longer(c(below95, between95_97, atleast97), names_to = 'category', values_to = 'pct') %>%
  mutate(category = factor(category, levels = c('atleast97', 'between95_97', 'below95'),
    labels = c('>=97%', '95-<97%', '<95%')))
p <- ggplot(student_shares, aes(year, pct, fill = category)) +
  geom_col(width = .75) +
  geom_text(aes(label = sprintf('%.1f', pct)), position = position_stack(vjust = .5), size = 3, color = 'white') +
  scale_fill_manual(values = c('>=97%' = '#3478A4', '95-<97%' = '#D78A32', '<95%' = '#BB302D'),
    name = 'School coverage') +
  geom_vline(xintercept = c(6.5, 9.5), linetype = 2, color = 'grey30') +
  annotate('text', x = c(3.5, 8, 11), y = 104, label = c('Pre-pandemic', 'Pandemic', 'Post-pandemic'),
    fontface = 'bold', size = 3.8, color = '#172536') +
  scale_y_continuous(breaks = seq(0, 100, 25), expand = c(0, 0)) +
  coord_cartesian(ylim = c(0, 108)) +
  labs(title = 'Students attending schools in each coverage category', x = 'School year', y = 'Students (%)') +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
stacked <- p  # reused in the summary figure
ggsave(file.path(folder, 'student_coverage_categories.png'), p, width = 10, height = 6, dpi = 180, bg = 'white')

# Paper summary figure: existing plots combined (map -> county test -> students).
# Print styling: larger text, one palette per meaning.
#   Periods (time): slate ramp, light -> dark.
#   Coverage (A and D): red = low, purple = medium, blue = high, as in the bivariate map.
library(cowplot)
paper_periods <- c(Pre = '#2A9D8F', Pandemic = '#E9A23B', Post = '#8C510A')  # teal, amber, brown: distinct from coverage colors
period_short <- c(Pre = 'Pre-pandemic', Pandemic = 'Pandemic', Post = 'Post-pandemic')
paper_coverage <- c('>=97%' = '#145A91', '95-<97%' = '#7950A6', '<95%' = '#BB302D')
ink <- '#1F2933'
paper <- theme(text = element_text(size = 11, color = ink), axis.text = element_text(size = 10, color = '#3E4C59'),
  axis.title = element_text(size = 11),
  plot.title = element_text(face = 'bold', size = 12.5, color = ink, margin = margin(b = 8)),
  plot.title.position = 'panel', plot.subtitle = element_blank(), plot.caption = element_blank(),
  legend.text = element_text(size = 10), legend.title = element_text(size = 10.5),
  plot.margin = margin(8, 12, 8, 8))
text_size <- function(plot, size) {
  for (i in seq_along(plot$layers)) {
    if (inherits(plot$layers[[i]]$geom, 'GeomText')) plot$layers[[i]]$aes_params$size <- size
  }
  plot
}
fig_a <- plot_grid(gap_legend + theme(axis.text = element_text(size = 9, color = ink),
    axis.text.x.top = element_text(size = 8.5, color = ink, lineheight = .9),
    axis.title = element_text(size = 10.5, face = 'bold', color = ink)),
  gap_maps + theme(strip.text = element_text(size = 11.5, face = 'bold', color = ink)),
  nrow = 1, rel_widths = c(.42, 1))
middle <- theme(text = element_text(size = 12.5), axis.text = element_text(size = 11.5),
  axis.title = element_text(size = 12.5), plot.title = element_text(size = 13.5), legend.text = element_text(size = 11.5))
fig_b <- text_size(gap_box, 4.2) + scale_fill_manual(values = paper_periods, guide = 'none') +
  scale_x_discrete(labels = period_short) +
  labs(title = paste0('Median - P10 gap by period (Friedman ',
    format_p(friedman$p_holm_across_metrics[friedman$metric == 'gap']), ')'), y = 'Median - P10 gap (pp)') +
  paper + middle + theme(strip.text = element_blank())
fig_b$layers[[1]]$aes_params$alpha <- .75
fig_c <- student_density
fig_c$layers[[1]]$aes_params$linewidth <- 1.2
fig_c$layers[[1]]$aes_params$alpha <- .18
fig_c <- fig_c +
  scale_fill_manual(values = paper_periods, labels = period_short, name = NULL) +
  scale_color_manual(values = paper_periods, labels = period_short, name = NULL) +
  labs(title = 'Distribution of students by school coverage') + paper + middle +
  theme(legend.position = c(.03, .97), legend.justification = c(0, 1), legend.direction = 'vertical',
    legend.background = element_rect(fill = 'white', color = NA))
# Bottom row: narrower stacked bars (D) + school decline by baseline coverage (E).
# E reuses the period colors: Pandemic vs Pre = amber, Post vs Pre = brown.
fig_d2 <- text_size(stacked, 2.9) + scale_fill_manual(values = paper_coverage, name = 'School coverage') +
  labs(title = 'Students by school coverage category') + paper + middle +
  theme(axis.text.x = element_text(size = 9.5), legend.text = element_text(size = 10.5))
fig_e <- baseline_box + scale_fill_manual(values = unname(paper_periods[c('Pandemic', 'Post')])) +
  labs(title = 'School decline by pre-pandemic coverage', x = 'Pre-pandemic school coverage',
    y = 'Decline from baseline (pp)') + paper + middle
fig_e$layers[[2]]$aes_params$alpha <- .85
summary_figure <- plot_grid(fig_a,
  plot_grid(fig_b, fig_c, nrow = 1, labels = c('B', 'C'), label_size = 18, label_colour = ink),
  plot_grid(fig_d2, fig_e, nrow = 1, rel_widths = c(1.15, 1), labels = c('D', 'E'), label_size = 18, label_colour = ink),
  ncol = 1, labels = c('A', '', ''), label_size = 18, label_colour = ink, rel_heights = c(.95, 1.05, 1.05))
ggsave(file.path(folder, 'gap_summary_figure.png'), summary_figure, width = 11, height = 13.5, dpi = 300, bg = 'white')


cat('Saved county maps, period boxplots and school-change figures in figures/.\n')
