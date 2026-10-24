# Apply decisions from review_pending.csv back to catalog/datasets.yaml.
# Only `review`, `featured`, `sectors`, `themes` and `taxa` are read back.
invisible(lapply(list.files("R", full.names = TRUE), source))
cur <- read_curated("catalog/datasets.yaml")
dec <- readr::read_csv("review_pending.csv", show_col_types = FALSE,
                       col_types = readr::cols(.default = "c")) |>
  dplyr::mutate(review = tolower(trimws(review)))
bad <- setdiff(stats::na.omit(dec$review), c("", "approved", "excluded", "pending"))
if (length(bad)) stop("Unknown review values: ", paste(bad, collapse = ", "))

for (i in seq_len(nrow(dec))) {
  j <- match(dec$id[i], cur$id)
  if (is.na(j)) next
  if (!is.na(dec$review[i]) && nzchar(dec$review[i])) cur$review[j] <- dec$review[i]
  for (f in c("sectors", "themes", "taxa")) {
    if (!is.na(dec[[f]][i])) cur[[f]][j] <- dec[[f]][i]
  }
  if (!is.na(dec$featured[i])) cur$featured[j] <- toupper(dec$featured[i]) == "TRUE"
}
write_curated(cur, "catalog/datasets.yaml")
print(table(cur$review))
