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
  # Contribute page: datasets and paper suggestions arrive together
  tar_target(submissions, fetch_submissions(), cue = tar_cue("always")),
  tar_target(from_form, dataset_submissions(submissions)),

  # Publications (OpenAlex only; Web of Science is added locally with
  # scripts/import_wos.R because its export cannot leave VCU's licence)
  tar_target(papers_file, "catalog/papers.yaml", format = "file"),
  tar_target(papers_curated, read_papers(papers_file)),
  tar_target(papers_core, search_openalex_papers(gazetteer, "core"),
             cue = tar_cue("always")),
  tar_target(papers_fulltext, search_openalex_papers(gazetteer, "fulltext"),
             cue = tar_cue("always")),
  tar_target(papers_form, paper_submissions(submissions)),
  tar_target(papers_scored,
             combine_papers(papers_core, papers_fulltext, papers_form) |>
               score_papers(gazetteer)),
  # Suggested taxa/themes for new papers (rules in data-raw/*_terms.csv)
  tar_target(taxon_terms_file, "data-raw/taxon_terms.csv", format = "file"),
  tar_target(theme_terms_file, "data-raw/theme_terms.csv", format = "file"),
  tar_target(papers_tagged,
             tag_papers(papers_scored, papers_scored, read_tag_rules(taxon_terms_file),
                        read_tag_rules(theme_terms_file))),
  tar_target(papers_queue, new_papers(papers_tagged, papers_curated)),

  # Combine, score, queue
  tar_target(candidates,
             dplyr::bind_rows(from_datacite, from_gbif, from_form) |>
               dedupe_candidates() |>
               collapse_versions()),
  tar_target(scored, score_relevance(candidates, gazetteer)),
  tar_target(queue, new_candidates(scored, curated) |>
               tag_queue(read_tag_rules(theme_terms_file))),
  tar_target(queue_summary,
             review_summary(queue, "review_summary.md", papers = papers_queue),
             format = "file"),

  # Site data (approved entries only). Paper-dataset links are rebuilt by
  # scripts/update_links.R into catalog/links.csv.
  tar_target(links_file, "catalog/links.csv", format = "file"),
  tar_target(links, read_links(links_file)),
  tar_target(catalog_json, build_catalog_json(curated, "site/data/catalog.json", links),
             format = "file"),
  tar_target(papers_json, build_papers_json(papers_curated, "site/data/papers.json", links),
             format = "file")
)

# Appending the queues to catalog/datasets.yaml and catalog/papers.yaml is
# done by scripts/update_queue.R after tar_make(), not inside the pipeline, so
# the pipeline never rewrites one of its own tracked inputs.
