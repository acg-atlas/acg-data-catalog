# Submissions from the Cloudflare Worker -------------------------------------
#
# Needs WORKER_URL and WORKER_ADMIN_TOKEN (GitHub secrets). Contact emails stay
# in D1 and are never returned here, because this output lands in a public
# pull request.
#
# The Contribute page has two forms: kind "dataset" goes to the dataset queue
# (catalog/datasets.yaml), kind "paper" to the papers queue (catalog/papers.yaml).

empty_submissions <- function() {
  tibble::tibble(doi = character(), kind = character(), title = character(),
                 creators = character(), year = integer(), publisher = character(),
                 resource_type = character(), sector = character(), note = character())
}

#' Pending submissions of both kinds, one row each.
fetch_submissions <- function(worker_url = Sys.getenv("WORKER_URL"),
                              token = Sys.getenv("WORKER_ADMIN_TOKEN")) {
  if (!nzchar(worker_url) || !nzchar(token)) {
    message("WORKER_URL / WORKER_ADMIN_TOKEN not set; skipping submissions.")
    return(empty_submissions())
  }
  res <- get_json(paste0(worker_url, "/api/pending"),
                  headers = list(Authorization = paste("Bearer", token)))
  parse_submissions(res$submissions %||% list())
}

parse_submissions <- function(subs) {
  if (length(subs) == 0) return(empty_submissions())
  purrr::map(subs, function(s) tibble::tibble(
    doi = normalize_doi(s$doi), kind = s$kind %||% "dataset",
    title = s$title %||% NA_character_, creators = s$creators %||% NA_character_,
    year = as.integer(s$year %||% NA_integer_), publisher = s$publisher %||% NA_character_,
    resource_type = s$resource_type %||% NA_character_,
    sector = s$sector %||% NA_character_, note = s$note %||% NA_character_
  )) |> dplyr::bind_rows()
}

#' Dataset submissions as harvest candidates.
dataset_submissions <- function(subs) {
  s <- dplyr::filter(subs, kind != "paper")
  if (nrow(s) == 0) return(empty_candidates())
  s |>
    dplyr::transmute(
      doi, title, creators, year, publisher,
      url = paste0("https://doi.org/", doi), resource_type,
      source = "submission",
      text = paste(dplyr::coalesce(title, ""), dplyr::coalesce(note, "")),
      submitted_sector = sector, submission_note = note
    ) |>
    as_candidates()
}

#' Paper suggestions as paper records (OpenAlex, else Crossref, else the
#' Worker's own DOI lookup), marked found_by = "submission".
paper_submissions <- function(subs) {
  s <- dplyr::filter(subs, kind == "paper", !is.na(doi))
  if (nrow(s) == 0) return(dplyr::mutate(empty_papers(), found_by = character()))
  oa <- openalex_by_doi(s$doi)
  cr <- crossref_by_doi(setdiff(s$doi, oa$doi))
  rest <- dplyr::filter(s, !doi %in% c(oa$doi, cr$doi)) |>
    dplyr::transmute(doi, title, year, venue = publisher, authors = creators,
                     type = resource_type, meta_source = "submission")
  dplyr::bind_rows(empty_papers(), oa, cr, rest) |>
    dplyr::mutate(found_by = "submission")
}

#' Statuses to send back for pending submissions: any submitted DOI that is
#' now approved or excluded in either catalog file (including papers that were
#' already listed before someone suggested them).
submission_statuses <- function(subs, curated, papers) {
  decided <- dplyr::bind_rows(
    dplyr::select(curated, doi, review),
    dplyr::select(papers, doi, review)
  ) |>
    dplyr::filter(!is.na(doi), review %in% c("approved", "excluded")) |>
    dplyr::mutate(doi = normalize_doi(doi)) |>
    dplyr::distinct(doi, .keep_all = TRUE)
  dplyr::inner_join(dplyr::select(subs, doi), decided, by = "doi")
}

#' After a merge, tell the Worker which submissions were approved/excluded.
push_statuses <- function(curated, papers,
                          worker_url = Sys.getenv("WORKER_URL"),
                          token = Sys.getenv("WORKER_ADMIN_TOKEN")) {
  if (!nzchar(worker_url) || !nzchar(token)) return(invisible(NULL))
  decided <- submission_statuses(fetch_submissions(worker_url, token), curated, papers)
  if (nrow(decided) == 0) return(invisible(0L))
  body <- list(updates = purrr::map2(decided$doi, decided$review,
                                     ~ list(doi = .x, status = .y)))
  httr2::request(paste0(worker_url, "/api/status")) |>
    httr2::req_headers(Authorization = paste("Bearer", token)) |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
  invisible(nrow(decided))
}
