# Site data -------------------------------------------------------------------
#
# Only approved entries leave this repo. Output is plain JSON so the Quarto
# site can read it with Observable JS; no server or database needed.

build_catalog_json <- function(curated, path, links = empty_links()) {
  papers <- links |>
    dplyr::group_by(dataset_id) |>
    dplyr::summarise(papers = paste(paper_doi, collapse = "; "), .groups = "drop")
  approved <- curated |>
    dplyr::left_join(papers, by = c("id" = "dataset_id")) |>
    dplyr::filter(review == "approved") |>
    # some repositories put HTML (<em>Genus</em>) in titles
    dplyr::mutate(title = gsub("<[^>]+>", "", title)) |>
    dplyr::select(-review, -relevance, -relevance_reason) |>
    # GBIF dataset key, used by the map page for GBIF's density tiles
    dplyr::mutate(gbif_key = ifelse(source == "gbif",
                                    sub("^.*/dataset/", "", url), NA_character_)) |>
    dplyr::arrange(dplyr::desc(featured), dplyr::desc(year))
  jsonlite::write_json(approved, path, auto_unbox = TRUE, na = "null",
                       pretty = FALSE)
  path
}

#' Short markdown summary used as the pull-request body.
review_summary <- function(new, path, papers = NULL) {
  lines <- c(
    sprintf("## %d new dataset candidate(s) for review", nrow(new)), "",
    "Set `review: approved` or `review: excluded` in `catalog/datasets.yaml`,",
    "then merge. Pending entries can stay pending across PRs.", ""
  )
  if (nrow(new) > 0) {
    tbl <- sprintf("| %s | %s | %s | %s |",
                   new$relevance, substr(new$title, 1, 80),
                   new$source, new$relevance_reason)
    lines <- c(lines, "| relevance | title | source | why |",
               "|---|---|---|---|", tbl)
  }
  if (!is.null(papers) && nrow(papers) > 0) {
    lines <- c(lines, "",
      sprintf("## %d new paper(s) in `catalog/papers.yaml`", nrow(papers)), "",
      sprintf("%d likely, %d check. Review in bulk with `scripts/review_papers_export.R`.",
              sum(papers$relevance == "likely"), sum(papers$relevance == "check")))
  }
  writeLines(lines, path)
  path
}
