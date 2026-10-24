# Links between papers and datasets ------------------------------------------
#
# Three open sources, queried for each approved dataset:
#   - DataCite relatedIdentifiers (IsCitedBy, IsSupplementTo, IsDocumentedBy…)
#   - ScholeXplorer (OpenAIRE's Scholix link index: publishers + DataCite)
#   - GBIF literature tracking (papers citing a GBIF download that included
#     the dataset)
# Only links where both ends are in the Atlas are kept. They are written to
# catalog/links.csv by scripts/update_links.R and reviewed in the PR diff.

empty_links <- function() {
  tibble::tibble(paper_doi = character(), dataset_id = character(), source = character())
}

safe_json <- function(url, query = list()) {
  tryCatch(get_json(url, query), error = function(e) NULL)
}

#' DOIs related to one dataset DOI in its DataCite record.
datacite_related <- function(doi) {
  res <- safe_json(paste0("https://api.datacite.org/dois/", utils::URLencode(doi, reserved = TRUE)))
  rel <- res$data$attributes$relatedIdentifiers %||% list()
  dois <- purrr::map_chr(rel, function(r)
    if (identical(r$relatedIdentifierType, "DOI")) r$relatedIdentifier %||% NA_character_ else NA_character_)
  stats::na.omit(normalize_doi(dois))
}

#' DOIs linked to one DOI in ScholeXplorer (either direction).
scholix_links <- function(doi, max_pages = 5) {
  out <- character()
  for (page in seq_len(max_pages) - 1) {
    res <- safe_json("https://api.scholexplorer.openaire.eu/v3/Links",
                     list(sourcePid = doi, page = page))
    links <- res$result %||% list()
    ids <- unlist(purrr::map(links, function(l)
      purrr::map_chr(l$target$Identifier %||% l$target$identifier %||% list(), function(i)
        if (tolower(i$IDScheme %||% i$schema %||% "") == "doi") i$ID %||% i$identifier %||% NA_character_
        else NA_character_)))
    out <- c(out, ids)
    if (length(links) == 0 || page + 1 >= (res$totalPages %||% 1)) break
  }
  unique(stats::na.omit(normalize_doi(out)))
}

#' Paper DOIs in GBIF's literature tracker that cite a GBIF dataset (by key).
#' Only papers whose study area covers Costa Rica: global datasets such as
#' iNaturalist are cited by thousands of papers (8,225 vs 22 in Oct 2026), and
#' paging through all of them made the weekly run slow for no gain.
gbif_literature <- function(key, max_pages = 5) {
  out <- character()
  for (page in seq_len(max_pages) - 1) {
    res <- safe_json("https://api.gbif.org/v1/literature/search",
                     list(gbifDatasetKey = key, countriesOfCoverage = "CR",
                          limit = 1000, offset = page * 1000))
    out <- c(out, purrr::map_chr(res$results %||% list(), ~ .x$identifiers$doi %||% NA_character_))
    if (isTRUE(res$endOfRecords) || length(res$results %||% list()) == 0) break
  }
  unique(stats::na.omit(normalize_doi(out)))
}

#' Links between approved datasets and approved papers.
find_links <- function(datasets, papers) {
  datasets <- dplyr::filter(datasets, review == "approved", !is.na(doi))
  paper_dois <- unique(stats::na.omit(normalize_doi(papers$doi[papers$review == "approved"])))
  keep <- function(found, id, source) {
    hit <- intersect(found, paper_dois)
    if (!length(hit)) return(NULL)
    tibble::tibble(paper_doi = hit, dataset_id = id, source = source)
  }
  gbif_key <- sub("^https?://www\\.gbif\\.org/dataset/", "", datasets$url)
  gbif_key[!grepl("^[0-9a-f-]{36}$", gbif_key)] <- NA_character_
  purrr::map(seq_len(nrow(datasets)), function(i) {
    d <- datasets$doi[i]
    dplyr::bind_rows(
      keep(datacite_related(d), datasets$id[i], "datacite"),
      keep(scholix_links(d), datasets$id[i], "scholix"),
      if (!is.na(gbif_key[i])) keep(gbif_literature(gbif_key[i]), datasets$id[i], "gbif")
    )
  }) |>
    dplyr::bind_rows(empty_links()) |>
    dplyr::group_by(paper_doi, dataset_id) |>
    dplyr::summarise(source = paste(sort(unique(source)), collapse = "; "), .groups = "drop") |>
    dplyr::arrange(dataset_id, paper_doi)
}

read_links <- function(path) {
  if (!file.exists(path)) return(empty_links())
  readr::read_csv(path, col_types = readr::cols(.default = "c"), show_col_types = FALSE)
}

#' Attach links: papers get `datasets` (dataset ids), datasets get `papers`
#' (paper DOIs). Hand-entered `datasets` in papers.yaml are kept.
link_papers <- function(papers, links) {
  auto <- links |>
    dplyr::group_by(paper_doi) |>
    dplyr::summarise(auto = paste(dataset_id, collapse = "; "), .groups = "drop")
  papers |>
    dplyr::left_join(auto, by = c("doi" = "paper_doi")) |>
    dplyr::mutate(datasets = purrr::map2_chr(datasets, auto, function(a, b) {
      v <- unique(c(split_field(a), split_field(b)))
      if (length(v)) paste(v, collapse = "; ") else NA_character_
    })) |>
    dplyr::select(-auto)
}

split_field <- function(x) {
  if (is.null(x) || is.na(x) || !nzchar(x)) return(character())
  trimws(strsplit(x, ";")[[1]])
}
