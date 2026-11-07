# Matched-school changes and coverage distributions: two flat tables.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(dplyr)
library(tidyr)
out <- 'processed_data'
school <- read.csv(file.path(out, 'school_year_data.csv'),
  colClasses = c(id = 'character', original_id = 'character'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
school$period <- factor(school$period, levels = c('Pre', 'Pandemic', 'Post'))
periods <- read.csv(file.path(out, 'county_period_measures.csv'), fileEncoding = 'UTF-8')
eligible <- unique(periods$county[periods$included_county])
schools <- school %>% filter(exclusion == 'Included', county %in% eligible)
with_ids <- schools %>% filter(!is.na(id))
stable <- with_ids %>% group_by(id) %>% summarise(counties = n_distinct(county), .groups = 'drop') %>%
  filter(counties == 1)
school_periods <- with_ids %>% filter(id %in% stable$id) %>% group_by(id, county, period) %>%
  summarise(coverage = mean(coverage),
    enrollment = if (any(valid_enrollment)) mean(enrollment[valid_enrollment]) else NA_real_,
    years = n_distinct(year), .groups = 'drop')
cohort <- school_periods %>% pivot_wider(names_from = period,
  values_from = c(coverage, enrollment, years)) %>%
  filter(years_Pre >= 3, years_Pandemic == 3, years_Post == 3,
    is.finite(coverage_Pre), is.finite(coverage_Pandemic), is.finite(coverage_Post)) %>%
  mutate(baseline_group = cut(coverage_Pre, c(-Inf, 90, 95, 97, Inf), right = FALSE,
    labels = c('<90%', '90-<95%', '95-<97%', '>=97%')),
    size_group = cut(enrollment_Pre, c(0, 250, 500, 1000, Inf), right = FALSE,
      labels = c('<250', '250-499', '500-999', '>=1,000')),
    pandemic_decline = coverage_Pre - coverage_Pandemic, post_decline = coverage_Pre - coverage_Post)
export <- cohort
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'school_changes.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')

# Average annual shares in 0.5-percentage-point bins, as in the accepted analysis.
annual_hist <- schools %>% mutate(bin = pmin(floor(coverage / .5) * .5, 99.5)) %>%
  group_by(year, period, bin) %>% summarise(schools = n(),
    students = sum(enrollment[valid_enrollment]), .groups = 'drop') %>%
  complete(nesting(year, period), bin = seq(0, 99.5, .5), fill = list(schools = 0, students = 0)) %>%
  group_by(year, period) %>% mutate(school_pct = 100 * schools / sum(schools),
    student_pct = 100 * students / sum(students))
histogram <- annual_hist %>% group_by(period, bin) %>%
  summarise(school_pct = mean(school_pct), student_pct = mean(student_pct), .groups = 'drop')
export <- histogram
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'coverage_distributions.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')
cat('Saved matched-school changes and coverage distributions.\n')
