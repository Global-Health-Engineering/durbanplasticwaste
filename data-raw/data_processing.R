# description -------------------------------------------------------------

# R script to process uploaded raw data into a tidy dataframe

# R packages --------------------------------------------------------------

library(tidyverse)
library(here)
library(readxl)
library(janitor)

# read data ---------------------------------------------------------------

litterboom <- read_excel("data-raw/Data for R_Raúl.xlsx", skip = 2)
locations <- read_csv("data-raw/litterboom-sample-locations.csv")
plastic_types <- read_excel("data-raw/Data for R_Chiara.xlsx",
           range = "B9:N28",
           col_types = c("date", "text", rep("numeric", 11)))

# tidy data ---------------------------------------------------------------

litterboom_df <- litterboom |>
  select(-...1) |>
  clean_names() |>
  mutate(year = "2022") |>
  unite(col = "date", c("date", "year"), sep = ".") |>
  mutate(date = lubridate::dmy(date)) |>
  relocate(date) |>
  mutate(amount = case_when(
    is.na(amount) == TRUE ~ 0,
    TRUE ~ amount
  ))

## store weights data as separate table

litterboom_weights <- litterboom_df |>
  select(date, location, pet = weight_pet, hdpe_pp = weight_hdpe_pp) |>
  distinct()

## import tidy brand names after exporting excel
## Issue 2: https://github.com/Global-Health-Engineering/durbanplasticwaste22/issues/2

litterboom_df |>
  count(brand, name = "count") |>
  mutate(new_name = NA_character_) |>
  openxlsx::write.xlsx("data-raw/tidy-brand.names.xlsx")

brand_names <- read_excel("data-raw/tidy-brand.names-rb.xlsx") |>
  select(brand, new_name) |>
  mutate(new_name = case_when(
    is.na(new_name) == TRUE ~ brand,
    TRUE ~ new_name
  ))

litterboom_counts <- litterboom_df |>
  select(-weight_pet, -weight_hdpe_pp) |>
  rename(count = amount) |>
  left_join(brand_names) |>
  relocate(new_name, .before = brand) |>
  select(-brand) |>
  relocate(location, .after = date) |>
  rename(brand = new_name) |>
  mutate(group = case_when(
    group == "OTHER GROUPS" ~ "OTHER",
    group == "The Coca-Cola Company" ~ "Coca Cola Beverages South Africa",
    group == "Coca Cola Company" ~ "Coca Cola Beverages South Africa",
    str_detect(group, "UnID") == TRUE ~ "unidentifiable",
    TRUE ~ group
  )) |>
  mutate(category = case_when(
    category == "skiin" ~ "Skin/Hair Products",
    TRUE ~ category
  ))

## locations data - convert locations from degress, minutes, seconds to
## decimal degrees

locations <- locations |>
  pivot_longer(cols = latitude:longitude) |>
  mutate(value = str_replace(value, pattern = "˚", replacement = "")) |>
  mutate(value = str_replace(value, pattern = "'", replacement = "")) |>
  mutate(value = str_replace(value, pattern = "''", replacement = "")) |>
  separate(value, into = c("degree", "minutes", "seconds", "direction"), sep = " ") |>
  mutate(across(c(degree:seconds), as.numeric)) |>
  mutate(dd = degree + minutes/60 + seconds/3600) |>
  mutate(dd = case_when(
    direction == "S" ~ -dd,
    TRUE ~ dd
  )) |>
  select(location, name, dd) |>
  pivot_wider(names_from = name,
              values_from = dd)

## characterization data - separate "Place" and add additional
## columns for categorization
plastic_types <- plastic_types |>
  drop_na(Total) |>
  mutate(
    Place = ifelse(is.na(Place), "Beach Total", Place), # Name Beach Total row
    beach = !(str_detect(Place, "Litterboom")), # add variable to see if
    details = case_when(
      str_detect(Place, "^Litterboom") ~ "Litterboom",
      str_detect(Place, "Beach Total") ~ "Beach Total"),
    details = ifelse(is.na(details),
                        str_remove_all(str_extract(Place, "\\[.*\\]"), "[\\[\\]]"),
                        details),
    # Place = str_remove(Place, " \\[.*\\]"),
    Place = str_replace(Place, "\r\n", " "),
    Place = case_when(
      str_detect(Place, "ove Beachfront$") ~ "Beachfront Mangrove",
      str_detect(Place, "^Beachwood Mangrove") ~ "Beachwood Mangrove",
      TRUE ~ Place
      )
    ) |>
  rename(shoes_quantity = "# of shoes",
         bag_quantity = "# of bags",
         other_plastics = "Other Plastics",
         other_waste = "Other Waste") |>
  rename_all(.funs = tolower) |>
  mutate(hdpe_pp = if_else(place == "Litterboom Beachwood Mangroves",
                           true = pe, false = NA), .after = pp,
         pe = if_else(place == "Litterboom Beachwood Mangroves",
                      true = NA, false = pe))

# write data --------------------------------------------------------------

usethis::use_data(litterboom_weights, litterboom_counts, locations, overwrite = TRUE)
usethis::use_data(plastic_types, overwrite = TRUE)

write_csv(litterboom_counts, here::here("inst", "extdata", "litterboom_counts.csv"))
write_csv(litterboom_weights, here::here("inst", "extdata", "litterboom_weights.csv"))
write_csv(locations, here::here("inst", "extdata", "locations.csv"))
write_csv(plastic_types, here::here("inst", "extdata", "plastic_types.csv"))

openxlsx::write.xlsx(litterboom_counts, here::here("inst", "extdata", "litterboom_counts.xlsx"))
openxlsx::write.xlsx(litterboom_weights, here::here("inst", "extdata", "litterboom_weights.xlsx"))
openxlsx::write.xlsx(locations, here::here("inst", "extdata", "locations.xlsx"))
openxlsx::write.xlsx(plastic_types, here::here("inst", "extdata", "plastic_types.xlsx"))
