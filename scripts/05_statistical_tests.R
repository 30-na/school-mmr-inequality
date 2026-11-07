# All period tests and school-change confidence intervals in one flat table.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(dplyr)
library(tidyr)
out <- 'processed_data'
county_periods <- read.csv(file.path(out, 'county_period_measures.csv'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8') %>% filter(included_county)
county_periods$period <- factor(county_periods$period, levels = c('Pre', 'Pandemic', 'Post'))
metrics <- c('gap', 'weighted_sd', 'mad', 'sd', 'average', 'below95', 'between95_97', 'atleast97')
periods <- c('Pre', 'Pandemic', 'Post')
set.seed(20261105)
paired <- list()
overall <- list()
for (metric in metrics) {
  wide <- county_periods %>% select(county, period, all_of(metric)) %>%
    pivot_wider(names_from = period, values_from = all_of(metric)) %>%
    filter(if_all(all_of(periods), is.finite)) %>% arrange(county)
  values <- as.matrix(wide[, periods])
  test <- friedman.test(values)
  overall[[metric]] <- data.frame(analysis = 'period_changes', method = 'Friedman', metric,
    comparison = 'All periods', n_counties = nrow(values), statistic = unname(test$statistic), p = test$p.value)
  for (pair in list(c('Pre', 'Pandemic'), c('Pre', 'Post'), c('Pandemic', 'Post'))) {
    change <- values[, pair[2]] - values[, pair[1]]
    p <- if (all(abs(change) < 1e-12)) 1 else
      suppressWarnings(wilcox.test(change, exact = FALSE, correct = TRUE)$p.value)
    bootstrap <- replicate(4000, median(sample(change, length(change), replace = TRUE)))
    ci <- as.numeric(quantile(bootstrap, c(.025, .975)))
    paired[[length(paired) + 1]] <- data.frame(analysis = 'period_changes',
      method = 'Paired Wilcoxon and bootstrap', metric, comparison = paste(pair[2], '-', pair[1]),
      n_counties = length(change), estimate = median(change), low = ci[1], high = ci[2], p,
      bootstrap_repetitions = 4000L, valid_repetitions = 4000L)
  }
}
paired <- bind_rows(paired) %>% group_by(metric) %>% mutate(p_holm = p.adjust(p, 'holm')) %>% ungroup()
overall <- bind_rows(overall) %>% mutate(p_holm_across_metrics = p.adjust(p, 'holm'))
results <- list(overall, paired)

# Keep each sampled county's schools and both follow-up changes together.
cohort <- read.csv(file.path(out, 'school_changes.csv'), colClasses = c(id = 'character'),
  na.strings = c('', 'NA'), fileEncoding = 'UTF-8')
counties <- sort(unique(cohort$county))
set.seed(20261106)
repetitions <- 4000L
draws <- replicate(repetitions, sample.int(length(counties), length(counties), replace = TRUE))
for (variable in c('baseline_group', 'size_group')) {
  groups <- if (variable == 'baseline_group') c('<90%', '90-<95%', '95-<97%', '>=97%') else
    c('<250', '250-499', '500-999', '>=1,000')
  rows <- list()
  for (group in groups) {
    schools <- cohort[!is.na(cohort[[variable]]) & cohort[[variable]] == group, ]
    for (change in c('pandemic_decline', 'post_decline')) {
      county_values <- split(schools[[change]], factor(schools$county, levels = counties), drop = FALSE)
      bootstrap <- rep(NA_real_, repetitions)
      for (b in seq_len(repetitions)) {
        selected <- unlist(county_values[draws[, b]], use.names = FALSE)
        if (length(selected)) bootstrap[b] <- median(selected)
      }
      valid <- bootstrap[is.finite(bootstrap)]
      stopifnot(length(valid) >= .99 * repetitions)
      ci <- as.numeric(quantile(valid, c(.025, .975)))
      rows[[length(rows) + 1]] <- data.frame(
        analysis = if (variable == 'baseline_group') 'baseline_coverage' else 'school_size',
        method = 'County-cluster bootstrap', metric = 'coverage_decline', group,
        comparison = if (change == 'pandemic_decline') 'Pandemic vs Pre' else 'Post vs Pre',
        n_schools = nrow(schools), n_counties = n_distinct(schools$county),
        estimate = median(schools[[change]]), low = ci[1], high = ci[2],
        bootstrap_repetitions = repetitions, valid_repetitions = length(valid),
        evidence = if (ci[1] > 0) 'Decline' else if (ci[2] < 0) 'Improvement' else 'Unclear')
    }
  }
  results[[length(results) + 1]] <- bind_rows(rows)
}
results <- bind_rows(results) %>% select(analysis, method, metric, group, comparison,
  n_counties, n_schools, estimate, low, high, statistic, p, p_holm,
  p_holm_across_metrics, bootstrap_repetitions, valid_repetitions, evidence)
export <- results
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'statistical_results.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')
cat('Saved all tests and confidence intervals in statistical_results.csv.\n')
