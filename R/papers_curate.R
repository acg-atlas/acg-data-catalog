# Curated papers (catalog/papers.yaml) ----------------------------------------
#
# Same rules as catalog/datasets.yaml: review is pending | approved |
# excluded, only approved papers reach the site, excluded papers are never
# re-queued, and the pipeline only appends, never overwrites.

paper_fields <- c("id", "doi", "openalex_id", "review", "title", "year", "venue",
                  "authors", "type", "language", "is_oa", "oa_url", "found_by",
                  "relevance", "relevance_reason", "sectors", "taxa", "themes",
                  "datasets", "added")

papers_header <- c(
  "# ACG data catalog: curated publications.",
  "# review: pending | approved | excluded   (only 'approved' is published)",
  "# Metadata from OpenAlex (CC0) or Crossref. Web of Science is used only to",
  "# find papers; no WoS records are stored here.",
  "# sectors/taxa/themes/datasets: semicolon-separated.",
  ""
)

conform_papers <- function(df) {
  for (f in setdiff(paper_fields, names(df))) df[[f]] <- NA
  df[paper_fields] |>
    dplyr::mutate(
      dplyr::across(-c(year, is_oa), as.character),
      year = suppressWarnings(as.integer(year)),
      is_oa = as.logical(is_oa) %in% TRUE,
      review = dplyr::coalesce(review, "pending")
    )
}

read_papers <- function(path) {
  if (!file.exists(path)) return(conform_papers(tibble::tibble(id = character())))
  txt <- readLines(path, encoding = "UTF-8", warn = FALSE)
  entries <- yaml::yaml.load(paste(txt, collapse = "\n")) %||% list()
  if (!length(entries)) return(conform_papers(tibble::tibble(id = character())))
  purrr::map(entries, function(e) {
    e <- e[intersect(names(e), paper_fields)]
    tibble::as_tibble(purrr::map(e, ~ if (is.null(.x) || !length(.x)) NA else
      paste(.x, collapse = "; ")))
  }) |> dplyr::bind_rows() |> conform_papers()
}

write_papers <- function(papers, path) {
  entries <- purrr::pmap(papers, function(...) {
    purrr::discard(list(...), ~ length(.x) == 1 && is.na(.x))
  })
  body <- if (length(entries)) yaml::as.yaml(entries, handlers = list(logical = yaml::verbatim_logical)) else "[]\n"
  writeLines(c(papers_header, body), path, useBytes = TRUE)
}

#' Scored papers not already curated (by id or DOI), likely first, newest first.
new_papers <- function(scored, curated) {
  scored |>
    dplyr::filter(!id %in% curated$id,
                  is.na(doi) | !doi %in% stats::na.omit(curated$doi)) |>
    dplyr::arrange(relevance != "likely", dplyr::desc(year))
}

append_pending_papers <- function(path, curated, new, today = Sys.Date()) {
  if (nrow(new)) {
    add <- new |>
      dplyr::mutate(review = "pending", added = as.character(today)) |>
      conform_papers()
    curated <- dplyr::bind_rows(curated, add)
  }
  write_papers(curated, path)
  path
}

#' site/data/papers.json: approved papers only, lightest fields.
build_papers_json <- function(curated, path) {
  out <- curated |>
    dplyr::filter(review == "approved") |>
    dplyr::select(-review, -relevance, -relevance_reason, -found_by) |>
    dplyr::arrange(dplyr::desc(year))
  jsonlite::write_json(out, path, auto_unbox = TRUE, na = "null")
  path
}
