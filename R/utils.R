# Shared helpers -------------------------------------------------------------

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x

#' Normalize a DOI to bare, lower-case form ("10.xxxx/yyyy").
#'
#' Accepts "https://doi.org/...", "doi:...", mixed case, and stray whitespace.
#' Returns NA for anything that does not look like a DOI.
normalize_doi <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- sub("^(https?://)?(dx\\.)?doi\\.org/", "", x)
  x <- sub("^doi:\\s*", "", x)
  ifelse(grepl("^10\\.\\d{4,9}/\\S+$", x), x, NA_character_)
}

#' Empty candidate table. Every harvester returns exactly these columns,
#' so results can be row-bound without surprises.
empty_candidates <- function() {
  tibble::tibble(
    doi           = character(),
    title         = character(),
    creators      = character(),
    year          = integer(),
    publisher     = character(),
    url           = character(),
    license       = character(),
    resource_type = character(),
    source        = character(),
    text          = character(),  # title + description + subjects, for scoring
    geo_inside    = logical(),    # any DataCite geolocation inside the boundary
    acg_records   = integer(),    # GBIF occurrences inside the boundary
    submitted_sector = character(),
    submission_note  = character()
  )
}

#' Coerce a partial tibble to the candidate schema (adds missing columns as NA).
as_candidates <- function(df) {
  template <- empty_candidates()
  for (col in setdiff(names(template), names(df))) {
    df[[col]] <- rep(template[[col]][NA_integer_], nrow(df))
  }
  df <- df[names(template)]
  df$year        <- as.integer(df$year)
  df$acg_records <- as.integer(df$acg_records)
  df$geo_inside  <- as.logical(df$geo_inside)
  tibble::as_tibble(df)
}

#' Polite GET returning parsed JSON (lists, not simplified).
get_json <- function(url, query = list(), headers = list()) {
  req <- httr2::request(url) |>
    httr2::req_url_query(!!!query) |>
    httr2::req_user_agent("acg-data-catalog (https://github.com/acg-atlas)") |>
    httr2::req_retry(max_tries = 4, backoff = function(i) 2^i) |>
    httr2::req_throttle(rate = 5)
  if (length(headers)) req <- httr2::req_headers(req, !!!headers)
  httr2::req_perform(req) |> httr2::resp_body_json(simplifyVector = FALSE)
}
