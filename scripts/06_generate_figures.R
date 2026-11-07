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
  data <- county_periods %>% filter(included_county) %>%
    pivot_longer(c(gap, weighted_sd, mad, sd), names_to = 'metric', values_to = 'value') %>%
    mutate(metric = factor(metric, levels = c('gap', 'weighted_sd', 'mad', 'sd'),
      labels = c('Median - P10 gap', 'Enrollment-weighted SD', 'Median absolute deviation', 'Unweighted SD')))
  p <- ggplot(data, aes(period, value, fill = period)) + geom_boxplot(outlier.shape = NA, alpha = .55) +
    geom_line(aes(group = county), alpha = .10, color = '#334155', linewidth = .3) +
    geom_point(position = position_jitter(width = .08, height = 0, seed = 18), alpha = .35, size = .7) +
    facet_wrap(~metric, scales = 'free_y', ncol = 2) + scale_fill_manual(values = period_colors, guide = 'none') +
    labs(title = 'School-to-school disparities within the same counties',
      subtitle = paste(n_distinct(county_periods$county[county_periods$included_county]), 'counties; each county contributes one value per period'),
      x = NULL, y = 'Percentage points',
      caption = 'Lines connect the same county. Period values average annual metrics; counties have equal weight.')
  ggsave(file.path(folder, 'period_boxplots.png'), p, width = 11, height = 7, dpi = 180, bg = 'white')

  histogram <- read.csv('processed_data/coverage_distributions.csv', fileEncoding = 'UTF-8')
  histogram$period <- factor(histogram$period, levels = periods)
  for (type in c('school', 'student')) {
    p <- ggplot(histogram, aes(bin + .25, .data[[paste0(type, '_pct')]], fill = period)) +
      geom_col(width = .47) + facet_wrap(~period, ncol = 1) + scale_fill_manual(values = period_colors, guide = 'none') +
      scale_x_continuous(breaks = seq(0, 100, 10), limits = c(0, 100), expand = c(0, 0)) +
      labs(title = if (type == 'school') 'Distribution of school coverage' else 'Enrollment distribution by school coverage',
        subtitle = '0.5-percentage-point bins', x = 'School measles coverage (%)',
        y = if (type == 'school') 'Schools (%)' else 'Students (%)',
        caption = 'Average annual shares within each period. Final bin includes 100%. Missing enrollment excluded from student distribution.')
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
    filename <- if (variable == 'baseline_group') 'baseline_coverage_declines' else 'school_size_declines'
    ggsave(file.path(folder, paste0(filename, '.png')), p, width = 10, height = 6, dpi = 180, bg = 'white')
  }
cat('Saved county maps, period boxplots and school-change figures in figures/.\n')
