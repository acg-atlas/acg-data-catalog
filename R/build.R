# Site data -------------------------------------------------------------------
#
# Only approved entries leave this repo. Output is plain JSON so the Quarto
# site can read it with Observable JS; no server or database needed.

build_catalog_json <- function(curated, path) {
  approved <- curated |>
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

build_literature_json <- function(literature, gazetteer, path) {
  lit <- literature |>
    dplyr::mutate(sectors = guess_sectors(paste(title, abstract), gazetteer,
                                          rep(NA_character_, dplyr::n()))) |>
    dplyr::select(-abstract)  # keep the site light; abstracts stay in OpenAlex
  jsonlite::write_json(lit, path, auto_unbox = TRUE, na = "null")
  path
}

#' Short markdown summary used as the pull-request body.
review_summary <- function(new, path) {
  lines <- c(
    sprintf("## %d new candidate(s) for review", nrow(new)), "",
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
  writeLines(lines, path)
  path
}
