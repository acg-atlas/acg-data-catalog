# OpenAlex harvester (literature layer) --------------------------------------
#
# OpenAlex now requires a free API key: set OPENALEX_API_KEY (locally in
# .Renviron, in GitHub as a repository secret). Without it this returns an
# empty table and the rest of the pipeline still runs.

harvest_openalex <- function(terms, max_pages = 50,
                             api_key = Sys.getenv("OPENALEX_API_KEY")) {
  if (!nzchar(api_key)) {
    message("OPENALEX_API_KEY not set; skipping literature harvest.")
    return(empty_literature())
  }
  search <- paste0('"', terms, '"', collapse = " OR ")
  cursor <- "*"
  works <- list()
  for (i in seq_len(max_pages)) {
    res <- get_json("https://api.openalex.org/works", query = list(
      search = search, `per-page` = 200, cursor = cursor, api_key = api_key
    ))
    works <- c(works, res$results)
    cursor <- res$meta$next_cursor %||% NULL
    if (is.null(cursor) || length(res$results) == 0) break
  }
  if (length(works) == 0) return(empty_literature())
  purrr::map(works, parse_openalex_work) |> dplyr::bind_rows()
}

empty_literature <- function() {
  tibble::tibble(openalex_id = character(), doi = character(),
                 title = character(), year = integer(), venue = character(),
                 authors = character(), topics = character(),
                 abstract = character(), is_oa = logical())
}

parse_openalex_work <- function(w) {
  tibble::tibble(
    openalex_id = w$id %||% NA_character_,
    doi         = normalize_doi(w$doi %||% NA_character_),
    title       = w$display_name %||% NA_character_,
    year        = as.integer(w$publication_year %||% NA_integer_),
    venue       = w$primary_location$source$display_name %||% NA_character_,
    authors     = paste(purrr::map_chr(w$authorships %||% list(),
                                       ~ .x$author$display_name %||% ""),
                        collapse = "; "),
    topics      = paste(purrr::map_chr(w$topics %||% list(),
                                       ~ .x$display_name %||% ""),
                        collapse = "; "),
    abstract    = rebuild_abstract(w$abstract_inverted_index),
    is_oa       = isTRUE(w$open_access$is_oa)
  )
}

#' OpenAlex stores abstracts as {word: [positions]}; put them back in order.
rebuild_abstract <- function(inv) {
  if (is.null(inv) || length(inv) == 0) return(NA_character_)
  pos <- unlist(inv)
  words <- rep(names(inv), lengths(inv))
  paste(words[order(pos)], collapse = " ")
}
