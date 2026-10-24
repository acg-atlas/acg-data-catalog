# Export pending papers to review_papers.csv for bulk review in a spreadsheet.
# Fill `review` with approved / excluded (blank = still pending), optionally
# edit sectors/taxa/themes, save as CSV UTF-8, then run
# scripts/review_papers_import.R.
#
#   Rscript scripts/review_papers_export.R          # all pending papers
#   Rscript scripts/review_papers_export.R sample   # random 40 likely + 40 check,
#                                                   # to estimate precision first
invisible(lapply(list.files("R", full.names = TRUE), source))
args <- commandArgs(trailingOnly = TRUE)
cur <- read_papers("catalog/papers.yaml")
pending <- dplyr::filter(cur, review == "pending")
if ("sample" %in% args) {
  set.seed(20261024)
  pending <- pending |>
    dplyr::group_by(relevance) |>
    dplyr::slice_sample(n = 40) |>
    dplyr::ungroup()
}
out <- pending |>
  dplyr::mutate(review = "",
                link = dplyr::coalesce(paste0("https://doi.org/", doi),
                                       paste0("https://openalex.org/", openalex_id))) |>
  dplyr::arrange(relevance != "likely", dplyr::desc(year)) |>
  dplyr::select(id, review, relevance, title, year, venue, authors, type,
                link, found_by, relevance_reason, sectors, taxa, themes)
# write_excel_csv adds a BOM so Excel keeps accented characters intact
readr::write_excel_csv(out, "review_papers.csv", na = "")
message(nrow(out), " papers written to review_papers.csv")
