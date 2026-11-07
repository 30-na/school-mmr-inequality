# County-period measures, changes from baseline and map categories in one table.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(dplyr)
out <- 'processed_data'
county <- read.csv(file.path(out, 'county_year_measures.csv'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
county$period <- factor(county$period, levels = c('Pre', 'Pandemic', 'Post'))
metrics <- c('gap', 'weighted_sd', 'mad', 'sd', 'average', 'below95', 'between95_97', 'atleast97')
eligible <- county %>% group_by(county) %>% summarise(county_years = n_distinct(year), .groups = 'drop')
periods <- county %>% group_by(county, period) %>% summarise(years = n(),
  across(all_of(metrics), ~ mean(.x[is.finite(.x)])), .groups = 'drop') %>%
  left_join(eligible, by = 'county') %>% mutate(included_county = county_years == 12,
    coverage_class = as.integer(cut(average, c(-Inf, 95, 97, Inf), right = FALSE)))

# Same measure-specific pre-pandemic thirds, held fixed across all three periods.
for (metric in c('gap', 'weighted_sd', 'mad', 'sd')) {
  cuts <- as.numeric(quantile(periods[[metric]][periods$period == 'Pre'], c(1/3, 2/3), type = 7))
  periods[[paste0(metric, '_lower_cutoff')]] <- cuts[1]
  periods[[paste0(metric, '_upper_cutoff')]] <- cuts[2]
  periods[[paste0(metric, '_class')]] <- as.integer(cut(periods[[metric]], c(-Inf, cuts, Inf), right = FALSE))
  periods[[paste0(metric, '_map_code')]] <- paste(periods$coverage_class,
    periods[[paste0(metric, '_class')]], sep = '_')
}
for (metric in metrics) {
  baseline <- periods %>% filter(period == 'Pre') %>% select(county, all_of(metric))
  periods[[paste0(metric, '_change_from_pre')]] <- periods[[metric]] -
    baseline[[metric]][match(periods$county, baseline$county)]
}
export <- periods
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'county_period_measures.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')
cat('Saved county-period measures, changes and map categories.\n')
