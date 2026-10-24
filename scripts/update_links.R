# Rebuild catalog/links.csv: which approved papers cite or describe which
# approved datasets (DataCite, ScholeXplorer, GBIF literature tracking).
# Run locally or from the weekly workflow; changes show up in the PR diff.
invisible(lapply(list.files("R", full.names = TRUE), source))
links <- find_links(read_curated("catalog/datasets.yaml"), read_papers("catalog/papers.yaml"))
readr::write_csv(links, "catalog/links.csv", na = "")
message(nrow(links), " links between ", length(unique(links$paper_doi)), " papers and ",
        length(unique(links$dataset_id)), " datasets")
