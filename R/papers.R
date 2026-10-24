# Publications layer ------------------------------------------------------------
#
# Papers come from two searches (see data-raw/literature_search.md):
#   - Web of Science (VCU licence): private export, used only for its DOIs and
#     titles. WoS records are never written to this repo or the site.
#   - OpenAlex (CC0): title+abstract search ("core") and full-text search
#     ("fulltext", wider and noisier).
# Every published record comes from OpenAlex, or Crossref when OpenAlex lacks
# the DOI. Abstracts are used for scoring only and are not stored.

openalex_select <- paste(
  "id,doi,display_name,publication_year,primary_location,authorships,topics,",
  "abstract_inverted_index,open_access,type,language,cited_by_count", sep = "")

empty_papers <- function() {
  tibble::tibble(
    openalex_id = character(), doi = character(), title = character(),
    year = integer(), venue = character(), authors = character(),
    type = character(), language = character(), is_oa = logical(),
    oa_url = character(), cited_by = integer(), topics = character(),
    abstract = character(), meta_source = character()
  )
}

parse_openalex_paper <- function(w) {
  tibble::tibble(
    openalex_id = sub("^https://openalex.org/", "", w$id %||% NA_character_),
    doi         = normalize_doi(w$doi %||% NA_character_),
    title       = w$display_name %||% NA_character_,
    year        = as.integer(w$publication_year %||% NA_integer_),
    venue       = w$primary_location$source$display_name %||% NA_character_,
    authors     = paste(purrr::map_chr(w$authorships %||% list(),
                                       ~ .x$author$display_name %||% ""),
                        collapse = "; "),
    type        = w$type %||% NA_character_,
    language    = w$language %||% NA_character_,
    is_oa       = isTRUE(w$open_access$is_oa),
    oa_url      = w$open_access$oa_url %||% NA_character_,
    cited_by    = as.integer(w$cited_by_count %||% NA_integer_),
    topics      = paste(purrr::map_chr(w$topics %||% list(),
                                       ~ .x$display_name %||% ""), collapse = "; "),
    abstract    = rebuild_abstract(w$abstract_inverted_index),
    meta_source = "openalex"
  )
}

#' Page through an OpenAlex /works query with a cursor.
openalex_works <- function(query, api_key = Sys.getenv("OPENALEX_API_KEY"),
                           max_pages = 100) {
  if (!nzchar(api_key)) {
    message("OPENALEX_API_KEY not set; skipping OpenAlex.")
    return(empty_papers())
  }
  cursor <- "*"
  works <- list()
  for (i in seq_len(max_pages)) {
    res <- get_json("https://api.openalex.org/works", query = c(query, list(
      `per-page` = 200, cursor = cursor, select = openalex_select, api_key = api_key)))
    works <- c(works, res$results)
    cursor <- res$meta$next_cursor %||% NULL
    if (is.null(cursor) || length(res$results) == 0) break
  }
  if (!length(works)) return(empty_papers())
  purrr::map(works, parse_openalex_paper) |> dplyr::bind_rows()
}

# Sector names that are common words or other places in Costa Rica: kept for
# tagging sectors, never used as search terms. In OpenAlex titles+abstracts
# with "Costa Rica" (Oct 2026): Horizontes 185 (Spanish "horizons"), Santa
# Elena 176 (mostly Monteverde), San Gerardo 56 (de Dota), Brasilia 55.
ambiguous_terms <- c("Horizontes", "San Cristobal", "San Cristóbal", "Junquillal",
                     "Mundo Nuevo", "Estacion San Gerardo", "Estación San Gerardo",
                     "Estacion Brasilia", "Estación Brasilia", "Peninsula Santa Elena",
                     "Península Santa Elena")

# OpenAlex record types that are not papers (datasets belong in the data catalog).
excluded_types <- c("dataset", "erratum", "paratext", "peer-review",
                    "supplementary-materials", "retraction", "grant")

#' Boolean query from the gazetteer: strong ACG names, plus distinctive sector
#' names only alongside "Costa Rica" (as in the WoS query).
literature_query <- function(gazetteer, strong_only = FALSE) {
  q <- function(x) paste0('"', unique(stringi::stri_trans_general(x, "Latin-ASCII")), '"')
  strong <- paste(q(gazetteer$term[gazetteer$type == "strong"]), collapse = " OR ")
  if (strong_only) return(strong)
  sector <- setdiff(gazetteer$term[gazetteer$type == "sector"], ambiguous_terms)
  paste0(strong, " OR ((", paste(q(sector), collapse = " OR "), ') AND "Costa Rica")')
}

#' OpenAlex search in titles and abstracts ("core"), or full text for the
#' strong ACG names only ("fulltext": methods sections, wider and noisier).
search_openalex_papers <- function(gazetteer, scope = c("core", "fulltext")) {
  scope <- match.arg(scope)
  out <- if (scope == "core") {
    openalex_works(list(filter = paste0("title_and_abstract.search:", literature_query(gazetteer))))
  } else {
    openalex_works(list(search = literature_query(gazetteer, strong_only = TRUE)))
  }
  dplyr::mutate(out, found_by = paste0("openalex_", scope))
}

#' OpenAlex records for a set of DOIs (50 per request).
openalex_by_doi <- function(dois) {
  dois <- unique(stats::na.omit(dois))
  if (!length(dois)) return(empty_papers())
  batches <- split(dois, ceiling(seq_along(dois) / 50))
  purrr::map(batches, function(b) {
    openalex_works(list(filter = paste0("doi:", paste(b, collapse = "|"))), max_pages = 1)
  }) |> dplyr::bind_rows() |> dplyr::distinct(doi, .keep_all = TRUE)
}

#' Normalized title for matching records that have no DOI.
title_key <- function(x) {
  x <- tolower(stringi::stri_trans_general(x, "Latin-ASCII"))
  gsub("[^a-z0-9]+", " ", x) |> trimws()
}

#' OpenAlex match for one title (same year +-1); NULL unless the normalized
#' titles agree closely (edit distance <= 5% of the length).
openalex_by_title <- function(title, year) {
  words <- strsplit(title_key(title), " ")[[1]]
  if (length(words) < 3) return(NULL)
  terms <- paste(utils::head(words[nchar(words) > 2], 12), collapse = " ")
  yr <- if (!is.na(year)) sprintf(",publication_year:%d-%d", year - 1, year + 1) else ""
  hits <- openalex_works(list(filter = paste0("title.search:", terms, yr)), max_pages = 1)
  if (!nrow(hits)) return(NULL)
  d <- as.numeric(utils::adist(title_key(title), title_key(hits$title)))
  best <- which.min(d)
  if (d[best] <= 0.05 * nchar(title_key(title))) hits[best, ] else NULL
}

#' Crossref metadata for DOIs that OpenAlex does not have.
crossref_by_doi <- function(dois) {
  rows <- purrr::map(unique(stats::na.omit(dois)), function(d) {
    w <- tryCatch(get_json(paste0("https://api.crossref.org/works/", utils::URLencode(d, reserved = TRUE)))$message,
                  error = function(e) NULL)
    if (is.null(w)) return(NULL)
    tibble::tibble(
      doi = d, title = unlist(w$title)[1] %||% NA_character_,
      year = as.integer(unlist(w$issued$`date-parts`)[1] %||% NA_integer_),
      venue = unlist(w$`container-title`)[1] %||% NA_character_,
      authors = paste(purrr::map_chr(w$author %||% list(),
                                     ~ trimws(paste(.x$given %||% "", .x$family %||% ""))),
                      collapse = "; "),
      type = w$type %||% NA_character_, meta_source = "crossref"
    )
  })
  dplyr::bind_rows(empty_papers(), dplyr::bind_rows(rows))
}

#' OpenAlex stores abstracts as {word: [positions]}; put them back in order.
rebuild_abstract <- function(inv) {
  if (is.null(inv) || length(inv) == 0) return(NA_character_)
  pos <- unlist(inv)
  words <- rep(names(inv), lengths(inv))
  paste(words[order(pos)], collapse = " ")
}

# Web of Science (private) -----------------------------------------------------

#' Read Web of Science tab-delimited exports (one or more files). Only the
#' fields needed for matching are kept.
read_wos <- function(paths) {
  purrr::map(paths, function(p) {
    readr::read_tsv(p, quote = "", col_types = readr::cols(.default = "c"),
                    show_col_types = FALSE, progress = FALSE)
  }) |>
    dplyr::bind_rows() |>
    dplyr::transmute(wos_id = UT, doi = normalize_doi(DI), title = TI,
                     year = as.integer(PY)) |>
    dplyr::distinct(wos_id, .keep_all = TRUE)
}

#' Resolve WoS records to open metadata. Returns the matched records (from
#' OpenAlex or Crossref) and counts for the search log.
resolve_wos <- function(wos) {
  by_doi <- openalex_by_doi(wos$doi)
  missing_doi <- setdiff(stats::na.omit(wos$doi), by_doi$doi)
  from_crossref <- crossref_by_doi(missing_doi)
  no_doi <- dplyr::filter(wos, is.na(doi))
  by_title <- purrr::map2(no_doi$title, no_doi$year, openalex_by_title) |>
    purrr::compact() |> dplyr::bind_rows(empty_papers())
  resolved <- dplyr::bind_rows(by_doi, from_crossref, by_title) |>
    dplyr::mutate(found_by = "wos")
  attr(resolved, "counts") <- c(
    wos_records = nrow(wos), with_doi = sum(!is.na(wos$doi)),
    doi_in_openalex = nrow(by_doi), doi_in_crossref_only = nrow(from_crossref),
    doi_unresolved = length(missing_doi) - nrow(from_crossref),
    no_doi = nrow(no_doi), no_doi_matched_by_title = nrow(by_title),
    unmatched = nrow(wos) - nrow(by_doi) - nrow(from_crossref) - nrow(by_title)
  )
  resolved
}

# Combine and score --------------------------------------------------------------

#' Plazi/Zenodo deposits of single figures or species descriptions from a
#' paper ("FIGURE 1. …", "Meteorus andreae Aguirre & Shaw 2011"). The paper
#' itself is listed separately; these fragments are dropped.
is_fragment <- function(doi, title) {
  zenodo <- grepl("^10\\.5281/", doi %||% NA_character_)
  caption <- grepl("^(FIGURES?|FIGS?\\.|Figures?|Figs?\\.|TABLES?|Tables?)\\s", title)
  short <- lengths(strsplit(trimws(title %||% ""), "\\s+")) <= 8
  zenodo & (caption | short)
}

#' One row per paper. Key: DOI, else OpenAlex id. `found_by` lists every
#' search that found it ("wos; openalex_core").
combine_papers <- function(...) {
  all <- dplyr::bind_rows(...) |>
    dplyr::filter(is.na(type) | !type %in% excluded_types,
                  !is_fragment(doi, title)) |>
    dplyr::mutate(id = dplyr::coalesce(doi, openalex_id))
  found <- all |>
    dplyr::group_by(id) |>
    dplyr::summarise(found_by = paste(sort(unique(found_by)), collapse = "; "),
                     .groups = "drop")
  all |>
    dplyr::arrange(meta_source != "openalex") |>    # prefer OpenAlex metadata
    dplyr::distinct(id, .keep_all = TRUE) |>
    dplyr::select(-found_by) |>
    dplyr::left_join(found, by = "id")
}

#' Relevance from the gazetteer (title + abstract) and which searches found it.
#'   likely: strong ACG name, or found by WoS or the OpenAlex core search
#'   check:  full-text match only, or sector name without "Costa Rica"
score_papers <- function(papers, gazetteer) {
  text <- paste(papers$title, papers$abstract)
  strong <- match_terms(text, gazetteer$term[gazetteer$type == "strong"])
  sector <- match_terms(text, gazetteer$term[gazetteer$type == "sector"])
  core <- grepl("wos|openalex_core", papers$found_by)
  papers |>
    dplyr::mutate(
      relevance = ifelse(lengths(strong) > 0 | core, "likely", "check"),
      relevance_reason = purrr::pmap_chr(list(strong, sector, found_by), function(s, t, f) {
        parts <- c(if (length(s)) paste("names", s[1]),
                   if (length(t)) paste("sector", paste(unique(t), collapse = ", ")),
                   paste("found by", f))
        paste(parts, collapse = "; ")
      }),
      sectors = guess_sectors(text, gazetteer, rep(NA_character_, dplyr::n()))
    )
}
