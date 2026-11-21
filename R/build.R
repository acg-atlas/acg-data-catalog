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

#' Suggested themes for new dataset candidates (title + harvested text).
tag_queue <- function(queue, theme_rules) {
  if (!nrow(queue)) return(queue)
  tag_dataset_themes(queue, queue$text, theme_rules)
}

#' Short markdown summary used as the pull-request body.
review_summary <- function(new, path, papers = NULL, skipped = NULL) {
  # Sources that were down this week (see try_source()); listed first so they
  # aren't missed. They are searched again on the next run.
  warn <- if (length(skipped)) c(
    "> ⚠️ **Skipped this week** (the service did not respond after retries;",
    "> it will be searched again next week):",
    paste0("> - ", skipped), "") else character()
  lines <- c(warn,
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
    review <- if ("review" %in% names(papers)) papers$review else rep("pending", nrow(papers))
    todo <- papers[review == "pending", ]
    lines <- c(lines, "",
      sprintf("## %d new paper(s) to review in `catalog/papers.yaml`", nrow(todo)), "",
      sprintf("%d likely, %d check. Review with `source(\"scripts/start_review.R\")`.",
              sum(todo$relevance == "likely"), sum(todo$relevance == "check")))
    n_auto <- sum(review == "excluded")
    if (n_auto > 0) lines <- c(lines, "",
      sprintf(paste("%d more were auto-excluded (duplicates, or no ACG place, region",
                    "or author in title or abstract); see `relevance_reason`."), n_auto))
  }
  writeLines(lines, path)
  path
}
