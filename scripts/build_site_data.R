# Rebuild the site's data files from the curated YAML (no API calls).
# Used by the deploy workflow after a merge.
invisible(lapply(list.files("R", full.names = TRUE), source))
links <- read_links("catalog/links.csv")
build_catalog_json(read_curated("catalog/datasets.yaml"), "site/data/catalog.json", links)
build_papers_json(read_papers("catalog/papers.yaml"), "site/data/papers.json", links)
file.copy("data-raw/acg_boundary.geojson", "site/data/acg_boundary.geojson",
          overwrite = TRUE)
