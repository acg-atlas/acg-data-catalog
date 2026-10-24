# Export pending entries to a CSV for bulk review in a spreadsheet.
# Fill the `review` column with approved / excluded (leave blank = still
# pending), optionally edit sectors/themes/taxa/featured, then run
# scripts/review_import.R.
invisible(lapply(list.files("R", full.names = TRUE), source))
cur <- read_curated("catalog/datasets.yaml")
pending <- dplyr::filter(cur, review == "pending") |>
  dplyr::mutate(review = "") |>
  dplyr::select(id, review, featured, category, relevance, title, creators,
                year, publisher, url, relevance_reason, sectors, themes, taxa)
readr::write_csv(pending, "review_pending.csv", na = "")
message(nrow(pending), " pending entries written to review_pending.csv")
