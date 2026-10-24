# Curated catalog (catalog/datasets.yaml) -------------------------------------
#
# The single source of human judgment. Each entry has a `review` field:
#   pending  - found by the harvest or the form, not yet reviewed (hidden)
#   approved - shown on the site
#   excluded - never shown, and never re-queued by future harvests
# Edit titles, sectors, themes, notes etc. freely; the pipeline never
# overwrites an existing entry, it only appends new pending ones.

curated_fields <- c("id", "doi", "review", "featured", "category", "title",
                    "creators", "year", "publisher", "url", "license",
                    "resource_type", "source", "acg_records", "relevance",
                    "relevance_reason", "versions", "sectors", "themes", "taxa",
                    "note_en", "note_es", "added")

yaml_header <- c(
  "# ACG data catalog: curated entries.",
  "# review: pending | approved | excluded   (only 'approved' is published)",
  "# featured: true puts an entry on the home page (keep 6-10 at a time).",
  "# sectors/themes/taxa: semicolon-separated; note_en/note_es: one line each.",
  "# New pending entries are appended by the weekly GitHub Action.",
  ""
)

read_curated <- function(path) {
  if (!file.exists(path)) return(empty_curated())
  txt <- readLines(path, encoding = "UTF-8", warn = FALSE)  # locale-proof
  entries <- yaml::yaml.load(paste(txt, collapse = "\n")) %||% list()
  if (length(entries) == 0) return(empty_curated())
  purrr::map(entries, function(e) {
    e <- e[intersect(names(e), curated_fields)]
    e <- purrr::map(e, ~ if (is.null(.x) || length(.x) == 0) NA else
      paste(.x, collapse = "; "))
    tibble::as_tibble(e)
  }) |>
    dplyr::bind_rows() |>
    conform_curated()
}

empty_curated <- function() {
  conform_curated(tibble::tibble(id = character()))
}

conform_curated <- function(df) {
  for (f in setdiff(curated_fields, names(df))) df[[f]] <- NA
  df <- df[curated_fields]
  df |>
    dplyr::mutate(
      dplyr::across(-c(year, acg_records, featured), as.character),
      year = suppressWarnings(as.integer(year)),
      acg_records = suppressWarnings(as.integer(acg_records)),
      featured = as.logical(featured) %in% TRUE,
      review = dplyr::coalesce(review, "pending")
    )
}

#' Candidates not already in the curated file (approved, pending OR excluded).
new_candidates <- function(scored, curated, min_flag = c("likely", "check")) {
  scored |>
    dplyr::filter(!id %in% curated$id,
                  is.na(doi) | !doi %in% stats::na.omit(curated$doi),
                  relevance %in% min_flag) |>
    # datasets before taxonomic treatments, strongest evidence first
    dplyr::arrange(category != "dataset", dplyr::desc(relevance_score),
                   dplyr::desc(acg_records))
}

#' Append new candidates as pending entries and rewrite the YAML.
append_pending <- function(path, curated, new, today = Sys.Date()) {
  if (nrow(new) > 0) {
    add <- new |>
      dplyr::mutate(review = "pending", featured = FALSE, themes = NA,
                    taxa = NA, note_en = NA, note_es = NA,
                    added = as.character(today)) |>
      conform_curated()
    curated <- dplyr::bind_rows(curated, add)
  }
  write_curated(curated, path)
  path
}

write_curated <- function(curated, path) {
  entries <- purrr::pmap(curated, function(...) {
    e <- list(...)
    purrr::discard(e, ~ length(.x) == 1 && is.na(.x))
  })
  body <- if (length(entries)) yaml::as.yaml(entries, handlers = list(logical = yaml::verbatim_logical)) else "[]\n"
  writeLines(c(yaml_header, body), path, useBytes = TRUE)
}
