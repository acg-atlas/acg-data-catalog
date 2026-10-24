# Submissions from the Cloudflare Worker -------------------------------------
#
# Needs WORKER_URL and WORKER_ADMIN_TOKEN (GitHub secrets). Contact emails stay
# in D1 and are never returned here, because this output lands in a public
# pull request.

fetch_submissions <- function(worker_url = Sys.getenv("WORKER_URL"),
                              token = Sys.getenv("WORKER_ADMIN_TOKEN")) {
  if (!nzchar(worker_url) || !nzchar(token)) {
    message("WORKER_URL / WORKER_ADMIN_TOKEN not set; skipping submissions.")
    return(empty_candidates())
  }
  res <- get_json(paste0(worker_url, "/api/pending"),
                  headers = list(Authorization = paste("Bearer", token)))
  subs <- res$submissions %||% list()
  if (length(subs) == 0) return(empty_candidates())
  purrr::map(subs, function(s) tibble::tibble(
    doi = normalize_doi(s$doi), title = s$title %||% NA_character_,
    creators = s$creators %||% NA_character_, year = s$year %||% NA_integer_,
    publisher = s$publisher %||% NA_character_,
    url = paste0("https://doi.org/", s$doi),
    resource_type = s$resource_type %||% NA_character_,
    source = "submission",
    text = paste(s$title %||% "", s$note %||% ""),
    submitted_sector = s$sector %||% NA_character_,
    submission_note = s$note %||% NA_character_
  )) |>
    dplyr::bind_rows() |>
    as_candidates()
}

#' After a merge, tell the Worker which submissions were approved/excluded.
push_statuses <- function(curated,
                          worker_url = Sys.getenv("WORKER_URL"),
                          token = Sys.getenv("WORKER_ADMIN_TOKEN")) {
  if (!nzchar(worker_url) || !nzchar(token)) return(invisible(NULL))
  decided <- dplyr::filter(curated, source == "submission",
                           review %in% c("approved", "excluded"), !is.na(doi))
  if (nrow(decided) == 0) return(invisible(NULL))
  body <- list(updates = purrr::map2(decided$doi, decided$review,
                                     ~ list(doi = .x, status = .y)))
  httr2::request(paste0(worker_url, "/api/status")) |>
    httr2::req_headers(Authorization = paste("Bearer", token)) |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
  invisible(nrow(decided))
}
