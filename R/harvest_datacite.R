# DataCite harvester ---------------------------------------------------------
#
# DataCite mints DOIs for most data repositories (Dryad, Zenodo, EDI, Figshare,
# PANGAEA, GBIF, ...), so one keyword search here covers all of them.

datacite_query <- function(terms) {
  paste0('"', terms, '"', collapse = " OR ")
}

harvest_datacite <- function(terms, boundary, max_pages = 20) {
  base <- "https://api.datacite.org/dois"
  query <- list(
    query = datacite_query(terms),
    `resource-type-id` = "dataset",
    `page[size]` = 500,
    `page[cursor]` = 1
  )
  records <- list()
  url <- base
  for (i in seq_len(max_pages)) {
    res <- get_json(url, query = query)
    records <- c(records, res$data)
    nxt <- res$links$`next` %||% NULL
    if (is.null(nxt) || length(res$data) == 0) break
    url <- nxt
    query <- list()  # the "next" link already carries the query
  }
  if (length(records) == 0) return(empty_candidates())
  purrr::map(records, parse_datacite_record, boundary = boundary) |>
    dplyr::bind_rows() |>
    as_candidates()
}

parse_datacite_record <- function(rec, boundary) {
  a <- rec$attributes
  descriptions <- purrr::map_chr(a$descriptions %||% list(),
                                 ~ .x$description %||% "")
  subjects <- purrr::map_chr(a$subjects %||% list(), ~ .x$subject %||% "")
  title <- a$titles[[1]]$title %||% NA_character_
  tibble::tibble(
    doi           = normalize_doi(rec$id),
    title         = title,
    creators      = paste(purrr::map_chr(a$creators %||% list(),
                                         ~ .x$name %||% ""), collapse = "; "),
    year          = a$publicationYear %||% NA_integer_,
    publisher     = a$publisher %||% NA_character_,
    url           = a$url %||% NA_character_,
    license       = (a$rightsList %||% list(list()))[[1]]$rightsUri %||% NA_character_,
    resource_type = a$types$resourceTypeGeneral %||% NA_character_,
    source        = "datacite",
    text          = paste(c(title, descriptions, subjects), collapse = " "),
    geo_inside    = geolocations_inside(a$geoLocations %||% list(), boundary)
  )
}
