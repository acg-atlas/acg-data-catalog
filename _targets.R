# ACG data catalog pipeline ---------------------------------------------------
# Run with targets::tar_make(). Visualize with targets::tar_visnetwork().

library(targets)

tar_option_set(packages = c("dplyr", "purrr", "tibble"))
tar_source("R")

# Keyword terms sent to DataCite and OpenAlex. Spatial matching (GBIF,
# DataCite geolocations) catches what these miss.
search_terms <- c(
  "Area de Conservacion Guanacaste", "Área de Conservación Guanacaste",
  "Guanacaste Conservation Area", "Santa Rosa National Park",
  "Parque Nacional Santa Rosa", "Guanacaste National Park",
  "Rincon de la Vieja", "Pitilla", "Estacion Biologica Maritza"
)

list(
  # Inputs (tracked as files: edits trigger reruns)
  tar_target(boundary_file, "data-raw/acg_boundary.geojson", format = "file"),
  tar_target(gazetteer_file, "data-raw/gazetteer.csv", format = "file"),
  tar_target(curated_file, "catalog/datasets.yaml", format = "file"),

  tar_target(boundary, read_boundary(boundary_file)),
  tar_target(gazetteer, read_gazetteer(gazetteer_file)),
  tar_target(curated, read_curated(curated_file)),

  # Harvest. `cue = tar_cue("always")` re-queries the APIs on every run.
  tar_target(from_datacite, harvest_datacite(search_terms, boundary),
             cue = tar_cue("always")),
  tar_target(from_gbif, harvest_gbif(boundary_wkt(boundary)),
             cue = tar_cue("always")),
  tar_target(from_form, fetch_submissions(), cue = tar_cue("always")),
  tar_target(literature, harvest_openalex(search_terms),
             cue = tar_cue("always")),

  # Combine, score, queue
  tar_target(candidates,
             dplyr::bind_rows(from_datacite, from_gbif, from_form) |>
               dedupe_candidates() |>
               collapse_versions()),
  tar_target(scored, score_relevance(candidates, gazetteer)),
  tar_target(queue, new_candidates(scored, curated)),
  tar_target(queue_summary, review_summary(queue, "review_summary.md"),
             format = "file"),

  # Site data (approved entries only)
  tar_target(catalog_json, build_catalog_json(curated, "site/data/catalog.json"),
             format = "file"),
  tar_target(literature_json,
             build_literature_json(literature, gazetteer,
                                   "site/data/literature.json"),
             format = "file")
)

# Appending the queue to catalog/datasets.yaml is done by
# scripts/update_queue.R after tar_make(), not inside the pipeline, so the
# pipeline never rewrites one of its own tracked inputs.
