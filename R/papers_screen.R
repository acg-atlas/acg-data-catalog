# Automatic first pass on new papers -------------------------------------------
#
# The full-text search finds many papers that only cite ACG work, or that
# match a place name by accident. Before new papers are queued, three rules
# mark the clearest of these as `excluded` (with the reason in
# relevance_reason), so the weekly review holds fewer of them. They are kept
# in catalog/papers.yaml, so they are never re-queued and can be looked at
# again with: Rscript scripts/review_papers_export.R excluded
#
#   1. duplicate:      same title (and year +-1) as a paper already listed,
#                      under another DOI or OpenAlex id
#   2. not a paper:    found by full text only, and an opinion piece, book
#                      review, editorial or similar ("other" types), unless an
#                      ACG name is in its title or abstract
#   3. no ACG signal:  found by full text only, and the title and abstract
#                      name no ACG place or region (Costa Rica, Guanacaste,
#                      Central America, Neotropics, ...), and no author has
#                      a record of ACG papers in the catalog
#
# Checked against the hand review of the 2026-11-16 queue: these rules
# excluded 112 of 224 papers. 105 had been excluded by hand; 1 was a second
# record of a paper already listed; 6 were undecided (no full text to check
# the study site). No paper approved by hand was lost.

# Words in a title or abstract that keep a full-text-only paper in the queue
region_terms <- c("costa rica", "guanacaste", "central america", "mesoamerica",
                  "neotropic", "nicaragua", "panama", "tropical dry forest",
                  "bosque seco")

# OpenAlex types that are rarely research papers
non_paper_types <- c("other", "book-review", "editorial", "letter", "paratext")

#' Authors with a record of ACG work: at least 3 approved papers, and at least
#' twice as many approved as excluded. Rebuilt from the catalog every run.
acg_authors <- function(curated, min_approved = 3) {
  ok  <- count_authors(curated$authors[curated$review == "approved"])
  bad <- count_authors(curated$authors[curated$review == "excluded"])
  dplyr::left_join(ok, bad, by = "author", suffix = c("_ok", "_bad")) |>
    dplyr::mutate(n_bad = dplyr::coalesce(n_bad, 0L)) |>
    dplyr::filter(n_ok >= min_approved, n_ok >= 2 * n_bad) |>
    dplyr::pull(author)
}

#' Number of papers per author (names folded: no accents, lower case).
count_authors <- function(authors) {
  per_paper <- lapply(strsplit(stats::na.omit(authors), ";\\s*"),
                      function(x) unique(fold(trimws(x))))
  tab <- table(unlist(per_paper))
  tab <- tab[nzchar(names(tab))]
  tibble::tibble(author = names(tab), n = as.integer(tab))
}

#' Mark the clearest non-ACG papers in a queue as excluded.
#' Adds `review` ("pending" or "excluded") and prefixes relevance_reason
#' with "auto-excluded: <rule>" for excluded papers.
auto_screen_papers <- function(queue, curated, gazetteer) {
  if (!nrow(queue)) return(dplyr::mutate(queue, review = character()))
  text <- fold(paste(queue$title, dplyr::coalesce(queue$abstract, "")))
  place_terms <- fold(gazetteer$term[gazetteer$type != "context"])
  has_place  <- lengths(match_terms(text, place_terms)) > 0
  has_region <- grepl(paste(region_terms, collapse = "|"), text)
  authors <- acg_authors(curated)
  has_author <- purrr::map_lgl(strsplit(dplyr::coalesce(queue$authors, ""), ";\\s*"),
                               ~ any(fold(trimws(.x)) %in% authors))
  fulltext_only <- queue$found_by == "openalex_fulltext"

  rule <- dplyr::case_when(
    is_duplicate_title(queue, curated) ~ "duplicate of a listed paper",
    fulltext_only & queue$type %in% non_paper_types & !has_place ~ "not a research paper",
    fulltext_only & !has_place & !has_region & !has_author ~ "no ACG place, region or author",
    TRUE ~ NA_character_
  )
  queue |>
    dplyr::mutate(
      review = ifelse(is.na(rule), "pending", "excluded"),
      relevance_reason = ifelse(is.na(rule), relevance_reason,
                                paste0("auto-excluded: ", rule, "; ", relevance_reason))
    )
}

#' TRUE where a queued paper has the same title as a listed one (year +-1).
is_duplicate_title <- function(queue, curated) {
  listed <- tibble::tibble(key = title_key(curated$title), year = curated$year) |>
    dplyr::filter(nzchar(key))
  purrr::map2_lgl(title_key(queue$title), queue$year, function(k, y) {
    hit <- listed$year[listed$key == k]
    nzchar(k) && length(hit) > 0 && (is.na(y) || any(is.na(hit) | abs(hit - y) <= 1))
  })
}
