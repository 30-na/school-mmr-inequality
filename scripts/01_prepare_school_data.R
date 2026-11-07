# Run scripts 01-06 in order from the project root.
# Existing cleaning rules only. Original state workbooks are never changed.
if (.Platform$OS.type == 'windows') invisible(Sys.setlocale('LC_CTYPE', 'English_United States.utf8'))
library(readxl)
library(dplyr)
library(sf)

out <- 'processed_data'
dir.create(out, recursive = TRUE, showWarnings = FALSE)
files <- c('Immunization-14-15.xlsx', 'Immunization-15-16.xlsx',
  'Immunization-16-17.xlsx', 'Immunization-17-18.xlsx', 'Immunization-18-19.xlsx',
  'Immunization-19-20.xlsx', 'Immunization_20-21.xlsx', 'Immunization-2022.xlsx',
  'Immunization-2023.xlsx', '2024-Immunization-Comp-Report.xlsx',
  '2025-Immunization-Comp-Report.xlsx', '2026-Immunization-Comp-Report.xlsx')
paths <- file.path('raw_data', files)
source_hashes <- tools::md5sum(paths)

# ISBE county-code order differs from Census alphabetical order for Mc counties.
county_names <- c('Adams','Alexander','Bond','Boone','Brown','Bureau','Calhoun','Carroll','Cass',
  'Champaign','Christian','Clark','Clay','Clinton','Coles','Cook','Crawford','Cumberland','DeKalb',
  'De Witt','Douglas','DuPage','Edgar','Edwards','Effingham','Fayette','Ford','Franklin','Fulton',
  'Gallatin','Greene','Grundy','Hamilton','Hancock','Hardin','Henderson','Henry','Iroquois','Jackson',
  'Jasper','Jefferson','Jersey','Jo Daviess','Johnson','Kane','Kankakee','Kendall','Knox','Lake',
  'LaSalle','Lawrence','Lee','Livingston','Logan','Macon','Macoupin','Madison','Marion','Marshall',
  'Mason','Massac','McDonough','McHenry','McLean','Menard','Mercer','Monroe','Montgomery','Morgan',
  'Moultrie','Ogle','Peoria','Perry','Piatt','Pike','Pope','Pulaski','Putnam','Randolph','Richland',
  'Rock Island','St. Clair','Saline','Sangamon','Schuyler','Scott','Shelby','Stark','Stephenson',
  'Tazewell','Union','Vermilion','Wabash','Warren','Washington','Wayne','White','Whiteside','Will',
  'Williamson','Winnebago','Woodford')

school_tables <- list()
for (i in seq_along(paths)) {
  sheets <- excel_sheets(paths[i])
  sheets <- c('Measles', sheets[grepl('Chicago', sheets)])
  year <- paste0(2013 + i, '-', substr(2014 + i, 3, 4))
  for (sheet in sheets) {
    top <- suppressMessages(read_excel(paths[i], sheet = sheet, n_max = 6,
      col_names = FALSE, col_types = 'text'))
    header <- NA_integer_
    for (row in seq_len(nrow(top))) {
      if (any(grepl('^Enrollment', unlist(top[row, ])))) header <- row
    }
    stopifnot(is.finite(header))
    z <- suppressMessages(read_excel(paths[i], sheet = sheet,
      skip = header - 1, col_types = 'text'))
    if (grepl('Chicago', sheet)) {
      z <- z[grepl('Measles', z[[grep('^Vaccine', names(z))[1]]], ignore.case = TRUE), ]
    }
    p <- suppressWarnings(as.numeric(z[[grep('^Protection', names(z))[1]]]))
    multiplier <- if (max(p, na.rm = TRUE) <= 1) 100 else 1
    school_tables[[length(school_tables) + 1]] <- data.frame(year,
      id = trimws(z[[1]]), district = z[[2]], school_name = z[[grep('^Facil', names(z))[1]]],
      enrollment_original = z[[grep('^Enrollment', names(z))[1]]],
      protected_original = z[[grep('^Protected', names(z))[1]]],
      reported = p * multiplier, source_file = files[i], source_sheet = sheet,
      source_multiplier = multiplier)
  }
}
school <- bind_rows(school_tables) %>%
  filter(!is.na(id), !grepl('^totals?$', id, ignore.case = TRUE)) %>%
  mutate(id = ifelse(nchar(id) == 14, paste0('0', id), id), original_id = id,
    enrollment = suppressWarnings(as.numeric(enrollment_original)),
    protected = suppressWarnings(as.numeric(protected_original)), estimated = FALSE)

# Preserve the existing exclusion of ambiguous duplicate IDs.
duplicate <- duplicated(paste(school$year, school$id)) |
  duplicated(paste(school$year, school$id), fromLast = TRUE)
school$duplicate_id <- duplicate
school$id[duplicate] <- NA_character_

# Existing reconstruction: 458 Chicago records with suppressed enrollment in 2021-22.
affected <- which(school$year == '2021-22' &
  substr(school$original_id, 1, 9) == '150162990' &
  school$enrollment_original == '<10' & !is.na(school$protected) & school$protected >= 10)
implied <- 100 * school$protected[affected] / school$reported[affected]
stopifnot(all(is.finite(implied)), all(abs(implied - round(implied)) < .001))
school$enrollment[affected] <- round(implied)
school$estimated[affected] <- TRUE

code <- suppressWarnings(as.integer(substr(school$original_id, 3, 5)))
code[is.na(code) | code < 1 | code > 102] <- NA_integer_
school$county <- county_names[code]
boundaries <- st_read('raw_data/il_counties.gpkg', quiet = TRUE)
school$county <- boundaries$county[match(toupper(gsub('[^A-Za-z]', '', school$county)),
  toupper(gsub('[^A-Za-z]', '', boundaries$county)))]
school <- school %>% mutate(year_start = as.integer(substr(year, 1, 4)),
  period = factor(ifelse(year_start <= 2019, 'Pre',
    ifelse(year_start <= 2022, 'Pandemic', 'Post')), levels = c('Pre', 'Pandemic', 'Post')),
  # Same denominator adjustments as the accepted state-only analysis.
  coverage = ifelse(year %in% c('2014-15', '2020-21'), 100 * protected / enrollment, reported),
  valid_coverage = is.finite(coverage) & coverage >= 0 & coverage <= 100,
  valid_enrollment = is.finite(enrollment) & enrollment > 0,
  exclusion = case_when(is.na(county) ~ 'County unavailable',
    !valid_coverage ~ 'Coverage unavailable/outside 0-100', TRUE ~ 'Included'),
  coverage_band = cut(coverage, c(-Inf, 95, 97, Inf), right = FALSE,
    labels = c('<95%', '95-<97%', '>=97%')))

# Keep preparation flags in the school table, without separate audit files.
school <- school %>% mutate(count_percentage_conflict = !year %in% c('2014-15', '2020-21') &
  valid_enrollment & is.finite(protected) & is.finite(reported) &
  abs(reported - 100 * protected / enrollment) > .01)
stopifnot(identical(unname(source_hashes), unname(tools::md5sum(paths))))

# Seventeen significant digits preserve numeric precision between CSV stages.
export <- school
for (column in names(export)) {
  if (is.double(export[[column]])) export[[column]] <- sprintf('%.17g', export[[column]])
}
write.csv(export, file.path(out, 'school_year_data.csv'), row.names = FALSE,
  na = '', fileEncoding = 'UTF-8')
cat('Saved school data:', nrow(school), 'records; reconstructed enrollment:', length(affected), '\n')
