# County-year measures and statewide student percentages.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(dplyr)
out <- 'processed_data'
school <- read.csv(file.path(out, 'school_year_data.csv'),
  colClasses = c(id = 'character', original_id = 'character'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
school$period <- factor(school$period, levels = c('Pre', 'Pandemic', 'Post'))
included <- school %>% filter(exclusion == 'Included')
county <- included %>% group_by(county, year, year_start, period) %>% summarise(
  n_schools = n(), n_weighted = sum(valid_enrollment),
  total_enrollment = sum(enrollment[valid_enrollment]),
  average = sum(enrollment[valid_enrollment] * coverage[valid_enrollment]) / total_enrollment,
  gap = median(coverage) - as.numeric(quantile(coverage, .10, type = 7)),
  weighted_sd = sqrt(sum(enrollment[valid_enrollment] *
    (coverage[valid_enrollment] - average)^2) / total_enrollment),
  mad = mad(coverage, constant = 1), sd = if (n() > 1) sd(coverage) else NA_real_,
  below95 = 100 * sum(enrollment[valid_enrollment] * (coverage[valid_enrollment] < 95)) / total_enrollment,
  between95_97 = 100 * sum(enrollment[valid_enrollment] *
    (coverage[valid_enrollment] >= 95 & coverage[valid_enrollment] < 97)) / total_enrollment,
  atleast97 = 100 * sum(enrollment[valid_enrollment] * (coverage[valid_enrollment] >= 97)) / total_enrollment,
  .groups = 'drop')
stopifnot(all(abs(county$below95 + county$between95_97 + county$atleast97 - 100) < 1e-8))
export <- county
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'county_year_measures.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')

# County assignment is not required for the statewide student percentages.
students <- school %>% filter(valid_coverage, valid_enrollment) %>% group_by(year) %>%
  summarise(schools = n(), students = sum(enrollment),
    below95 = 100 * sum(enrollment[coverage < 95]) / sum(enrollment),
    between95_97 = 100 * sum(enrollment[coverage >= 95 & coverage < 97]) / sum(enrollment),
    atleast97 = 100 * sum(enrollment[coverage >= 97]) / sum(enrollment), .groups = 'drop') %>% arrange(year)
stopifnot(nrow(students) == 12,
  all(abs(students$below95 + students$between95_97 + students$atleast97 - 100) < 1e-8))
export <- students
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'student_percentages.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')
cat('Saved county-year measures and student percentages.\n')
