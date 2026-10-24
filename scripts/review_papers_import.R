# Apply decisions from review_papers.csv back to catalog/papers.yaml.
# Only `review`, `sectors`, `taxa` and `themes` are read back.
invisible(lapply(list.files("R", full.names = TRUE), source))
cur <- read_papers("catalog/papers.yaml")
dec <- readr::read_csv("review_papers.csv", show_col_types = FALSE,
                       col_types = readr::cols(.default = "c")) |>
  dplyr::mutate(review = tolower(trimws(review)))
bad <- setdiff(stats::na.omit(dec$review), c("", "approved", "excluded", "pending"))
if (length(bad)) stop("Unknown review values: ", paste(bad, collapse = ", "))

j <- match(dec$id, cur$id)
for (i in which(!is.na(j))) {
  if (!is.na(dec$review[i]) && nzchar(dec$review[i])) cur$review[j[i]] <- dec$review[i]
  for (f in c("sectors", "taxa", "themes")) {
    if (!is.na(dec[[f]][i])) cur[[f]][j[i]] <- dec[[f]][i]
  }
}
write_papers(cur, "catalog/papers.yaml")
print(table(cur$review))
