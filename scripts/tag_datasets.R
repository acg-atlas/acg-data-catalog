# Fill empty `themes` in catalog/datasets.yaml from title + DataCite
# description. Prints a short summary and the datasets left untagged.
#   Rscript scripts/tag_datasets.R
invisible(lapply(list.files("R", full.names = TRUE), source))
cur <- read_curated("catalog/datasets.yaml")
desc <- purrr::map_chr(cur$doi, function(d) {
  if (is.na(d)) return(NA_character_)
  a <- safe_json(paste0("https://api.datacite.org/dois/", utils::URLencode(d, reserved = TRUE)))$data$attributes
  paste(c(purrr::map_chr(a$descriptions %||% list(), ~ .x$description %||% ""),
          purrr::map_chr(a$subjects %||% list(), ~ .x$subject %||% "")), collapse = " ")
})
out <- tag_dataset_themes(cur, desc, read_tag_rules("data-raw/theme_terms.csv"))
write_curated(out, "catalog/datasets.yaml")
ok <- out$review == "approved"
print(sort(table(unlist(strsplit(stats::na.omit(out$themes[ok]), "; "))), decreasing = TRUE))
miss <- which(ok & (is.na(out$themes) | !nzchar(out$themes)))
cat("\nuntagged approved:", length(miss), "of", sum(ok), "\n")
cat(sprintf("%s | %s | %s", out$id[miss], substr(out$title[miss], 1, 90), out$taxa[miss]), sep = "\n")
