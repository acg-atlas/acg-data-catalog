# Rebuild site/data/catalog.json from the curated YAML (no API calls).
# Used by the deploy workflow after a merge.
invisible(lapply(list.files("R", full.names = TRUE), source))
build_catalog_json(read_curated("catalog/datasets.yaml"), "site/data/catalog.json")
