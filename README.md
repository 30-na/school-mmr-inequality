# school-mmr-inequality

Illinois school vaccination coverage, 2014-15 through 2025-26. Vaccination data
come only from the original ISBE school workbooks in `raw_data/`.
The measured outcome is measles protection across PreK-12.

## Dataset sources

All raw inputs are stored directly in `raw_data/`.

**School vaccination data:** Illinois State Board of Education (ISBE),
[Data Analysis Reports](https://www.isbe.net/Pages/Data-Analysis-Reports.aspx).
Open **Student Health Data**, select the school year, and download
**Immunization School Survey Results: Complete Submission**. The 2014-15
file is under the expandable **1998-2015** section.

| School year | Local file in `raw_data/` |
|---|---|
| 2014-15 | `Immunization-14-15.xlsx` |
| 2015-16 | `Immunization-15-16.xlsx` |
| 2016-17 | `Immunization-16-17.xlsx` |
| 2017-18 | `Immunization-17-18.xlsx` |
| 2018-19 | `Immunization-18-19.xlsx` |
| 2019-20 | `Immunization-19-20.xlsx` |
| 2020-21 | `Immunization_20-21.xlsx` |
| 2021-22 | `Immunization-2022.xlsx` |
| 2022-23 | `Immunization-2023.xlsx` |
| 2023-24 | `2024-Immunization-Comp-Report.xlsx` |
| 2024-25 | `2025-Immunization-Comp-Report.xlsx` |
| 2025-26 | `2026-Immunization-Comp-Report.xlsx` |

The scripts read the **Measles** sheets and the separate Chicago sheet where
present. School IDs are RCDTS codes; enrollment and coverage cover PreK-12.

**County boundaries:** U.S. Census Bureau,
[Cartographic Boundary Files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html).
`il_counties.gpkg` is the Illinois subset of the **2020 county boundaries at
1:500,000 scale**, originally `cb_2020_us_county_500k`. It contains 102 county
geometries and their IDs. This file is used for county naming and maps, not
as a source of vaccination data.

This root README contains the source documentation and instructions for the
current project; no separate dataset README is needed.

## Running the analysis

Run these six scripts in order from the project root:

| Script | Purpose | Output |
|---|---|---|
| `scripts/01_prepare_school_data.R` | Read, clean and combine the state files | `school_year_data.csv` |
| `scripts/02_county_coverage_and_student_burden.R` | County-year measures and statewide student shares | `county_year_measures.csv`, `student_percentages.csv` |
| `scripts/03_period_changes.R` | County-period measures, changes and map categories | `county_period_measures.csv` |
| `scripts/04_baseline_coverage_and_school_size.R` | Matched-school changes and histogram values | `school_changes.csv`, `coverage_distributions.csv` |
| `scripts/05_statistical_tests.R` | Period tests and bootstrap confidence intervals | `statistical_results.csv` |
| `scripts/06_generate_figures.R` | Read saved results and generate primary-analysis plots | `figures/` (all PNGs directly in this folder) |

In R, run all six with:

```r
for (file in sort(list.files("scripts", pattern = "^[0-9]{2}_.*\\.R$", full.names = TRUE))) {
  source(file)
}
```

Required packages: `readxl`, `dplyr`, `tidyr`, `ggplot2`, and `sf` (`grid` comes
with R). Tested with R 4.3.2. Put the county boundaries at
`raw_data/il_counties.gpkg` before running; no personal cache path is used.

`raw_data/`, `processed_data/` and `figures/Archive/` (also lowercase `archive`)
are excluded from Git. After cloning, add the raw inputs described above and
run scripts 01-06 to regenerate the processed tables and current figures.

The workflow does not read older processed data, previous reports, the authors'
datasets, downloaded county vaccination data, or other states' data. No reports
are generated. Existing historical reports are separate reference artifacts.

## Analysis definitions

- Pre: 2014-15 to 2019-20; Pandemic: 2020-21 to 2022-23; Post: 2023-24 to 2025-26.
- Coverage in 2014-15 and 2020-21 is protected students divided by enrollment;
  other years use reported coverage. Original values are preserved.
- The existing enrollment reconstruction for 458 Chicago records in 2021-22
  is retained and flagged. Suppressed values are otherwise not imputed.
- County measures include median-P10 gap, enrollment-weighted SD, raw MAD and
  unweighted sample SD. Chicago and suburban Cook are combined.
- Maps are saved only as four combined figures (gap, weighted SD, MAD and
  unweighted SD), each showing all three periods. Individual period maps are
  not saved. Each measure uses its own fixed pre-pandemic disparity cutoffs.
- School tracking uses original RCDTS IDs, at least three pre-period years,
  all three years in each follow-up period, and a stable assigned county.
- Period comparisons use Friedman and paired Wilcoxon tests; paired p-values
  have Holm correction. Both sets of bootstrap intervals use 4,000 repetitions
  and the existing seeds. School-change intervals resample whole counties.
- Only the primary analysis is generated. County-size and data-definition
  sensitivity analyses and their figures are not included.

## Seven processed tables

All seven files are directly inside `processed_data/`, with no subfolders,
RDS copies or separate audit files:

| File | One row represents |
|---|---|
| `school_year_data.csv` | One school in one year, including original fields and preparation flags |
| `county_year_measures.csv` | One county in one year |
| `county_period_measures.csv` | One county in one period, including changes and map categories/cutoffs |
| `student_percentages.csv` | Statewide student percentages for one year |
| `school_changes.csv` | One tracked school's baseline, follow-up coverage, groups and declines |
| `coverage_distributions.csv` | One coverage bin in one period, with school and student percentages |
| `statistical_results.csv` | One statistical comparison or confidence interval |

In `statistical_results.csv`, `analysis`, `method`, `metric`, `group` and
`comparison` identify each result. `estimate`, `low` and `high` give changes and
confidence intervals in percentage points; `p` and adjusted p-value columns
apply to the period tests. Fields that do not apply to a method are missing.

CSV files use UTF-8 and retain full numeric precision and original school IDs. Preparation
flags and original values stay in `school_year_data.csv`; script 01 verifies
that raw files have not changed during reading. All figures are PNG only and
are saved directly inside `figures/`.
