# Relevance scoring ----------------------------------------------------------
#
# Every candidate is reviewed by a human, so this only orders the queue and
# explains itself. Scores:
#   +3  strong ACG name in the metadata ("Área de Conservación Guanacaste")
#   +2  sector name, but ONLY alongside "Guanacaste" or "Costa Rica"
#       ("Santa Rosa" alone also matches California)
#   +3  a DataCite geolocation inside the boundary
#   +3  >= 100 GBIF occurrences inside the boundary (+1 for fewer)
#   +2  submitted by a person through the form
# Flags: likely (>= 3), check (1-2), unlikely (0).

read_gazetteer <- function(path) {
  readr::read_csv(path, show_col_types = FALSE,
                  col_types = readr::cols(.default = "c"))
}

fold <- function(x) {
  x <- stringi::stri_trans_general(x, "Latin-ASCII")  # Á -> A, locale-proof
  tolower(ifelse(is.na(x), "", x))
}

match_terms <- function(text, terms) {
  t <- fold(text)
  purrr::map(t, function(s) terms[stringr::str_detect(
    s, stringr::fixed(fold(terms)))])
}

score_relevance <- function(candidates, gazetteer) {
  strong  <- gazetteer$term[gazetteer$type == "strong"]
  sector  <- gazetteer$term[gazetteer$type == "sector"]
  context <- gazetteer$term[gazetteer$type == "context"]

  hits_strong  <- match_terms(candidates$text, strong)
  hits_sector  <- match_terms(candidates$text, sector)
  hits_context <- match_terms(candidates$text, context)

  n <- nrow(candidates)
  score <- integer(n)
  reason <- vector("list", n)
  for (i in seq_len(n)) {
    r <- character()
    if (length(hits_strong[[i]])) {
      score[i] <- score[i] + 3L
      r <- c(r, paste0("names ", hits_strong[[i]][1]))
    }
    if (length(hits_sector[[i]]) && length(hits_context[[i]])) {
      score[i] <- score[i] + 2L
      r <- c(r, paste0("sector ", hits_sector[[i]][1]))
    }
    if (isTRUE(candidates$geo_inside[i])) {
      score[i] <- score[i] + 3L
      r <- c(r, "coordinates inside ACG")
    }
    recs <- candidates$acg_records[i]
    if (!is.na(recs) && recs > 0) {
      score[i] <- score[i] + if (recs >= 100) 3L else 1L
      r <- c(r, sprintf("%s GBIF records inside ACG", format(recs, big.mark = ",")))
    }
    if (identical(candidates$source[i], "submission")) {
      score[i] <- score[i] + 2L
      r <- c(r, "submitted via form")
    }
    reason[[i]] <- paste(r, collapse = "; ")
  }

  candidates |>
    dplyr::mutate(
      relevance_score = score,
      relevance = dplyr::case_when(score >= 3 ~ "likely",
                                   score >= 1 ~ "check",
                                   TRUE ~ "unlikely"),
      relevance_reason = unlist(reason),
      # Plazi extracts every species description as its own DataCite "dataset";
      # label them so they can be bulk-excluded or kept as their own category.
      category = dplyr::if_else(grepl("plazi", fold(publisher)),
                                "taxonomic treatment", "dataset"),
      sectors = guess_sectors(text, gazetteer, submitted_sector)
    )
}

guess_sectors <- function(text, gazetteer, submitted) {
  g <- dplyr::filter(gazetteer, !is.na(sector), nzchar(sector))
  hits <- match_terms(text, g$term)
  purrr::map2_chr(hits, submitted, function(h, s) {
    secs <- unique(c(if (!is.na(s) && nzchar(s)) s,
                     g$sector[match(h, g$term)]))
    paste(secs, collapse = "; ")
  })
}

#' One row per record: prefer DOI as the key, fall back to URL (GBIF datasets
#' without DOIs). When two sources find the same DOI, keep the richest row and
#' carry over GBIF counts and submission details.
dedupe_candidates <- function(candidates) {
  candidates |>
    dplyr::mutate(id = dplyr::coalesce(doi, url)) |>
    dplyr::filter(!is.na(id)) |>
    dplyr::group_by(id) |>
    dplyr::summarise(
      dplyr::across(c(doi, title, creators, year, publisher, url, license,
                      resource_type, text),
                    ~ dplyr::first(stats::na.omit(.x)) %||% NA),
      source = paste(sort(unique(source)), collapse = "+"),
      geo_inside = any(geo_inside, na.rm = TRUE),
      acg_records = suppressWarnings(max(acg_records, na.rm = TRUE)),
      submitted_sector = dplyr::first(stats::na.omit(submitted_sector)) %||% NA,
      submission_note  = dplyr::first(stats::na.omit(submission_note)) %||% NA,
      .groups = "drop"
    ) |>
    dplyr::mutate(acg_records = as.integer(dplyr::if_else(is.finite(acg_records),
                                                          acg_records, NA_real_)),
                  # keep "submission" detectable after merging sources
                  source = dplyr::if_else(grepl("submission", source),
                                          "submission", source))
}

#' Repositories like Zenodo and Mendeley mint a new DOI per version. Collapse
#' entries with the same title and publisher to one row (the newest), and keep
#' the other DOIs in `versions` so nothing is lost.
collapse_versions <- function(candidates) {
  candidates |>
    dplyr::mutate(.key = paste(fold(title), fold(publisher))) |>
    dplyr::arrange(dplyr::desc(year)) |>
    dplyr::group_by(.key) |>
    dplyr::mutate(versions = if (dplyr::n() > 1)
      paste(stats::na.omit(doi[-1]), collapse = "; ") else NA_character_) |>
    dplyr::slice(1) |>
    dplyr::ungroup() |>
    dplyr::select(-.key)
}
