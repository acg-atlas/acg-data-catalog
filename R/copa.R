# COPA, ACG's own repository ---------------------------------------------------
#
# COPA (copa.acguanacaste.ac.cr, DSpace 5) holds ACG's collection of research.
# Its "Ciencia e Investigación" community is ACG research by definition, so
# COPA items are approved without review (spot-checked instead).
#   - Items with a DOI get OpenAlex/Crossref metadata like every other paper,
#     link to the original by DOI, and also to their COPA page.
#   - Items without a DOI (older papers, theses, reports) use COPA's own
#     metadata and link to their COPA page.
# Items in COPA's private collection ("Colección Privada", 11606/48) have pages
# the public cannot open: they get no COPA link and are listed only if they
# have a DOI.
#
# First import: scripts/import_copa.R <export.csv> (the export stays outside
# the repo: it includes the private collection). Weekly: the OAI feed.

copa_base <- "https://copa.acguanacaste.ac.cr"
copa_set  <- "com_11606_1"   # Ciencia e Investigación
copa_private <- "11606/48"   # Colección Privada: pages need a COPA login

empty_copa <- function() {
  tibble::tibble(handle = character(), private = logical(), doi = character(), title = character(),
                 authors = character(), year = integer(), type = character(),
                 abstract = character(), language = character(), venue = character(),
                 subjects = character())
}

#' First DOI anywhere in a string (DOIs hide in uri, other and citation fields).
first_doi <- function(x) {
  d <- stringr::str_extract(x, "10\\.\\d{4,9}/[^\\s\"'<>,;|?#]+")
  d <- sub("[]).]+$", "", d)
  # Publisher links add a page name after the DOI (…/abc.x/full, …/abstract)
  normalize_doi(sub("/(full|abstract|pdf|epdf|fulltext|html|full\\.pdf)$", "", d, ignore.case = TRUE))
}

# DSpace joins repeated values with "||"
copa_multi <- function(x) ifelse(is.na(x), NA_character_, gsub("\\s*\\|\\|\\s*", "; ", x))
copa_first <- function(x) sub("\\|\\|.*$", "", x)

#' COPA's CSV export (one row per item; field names like dc.title[es_CR]).
read_copa_csv <- function(path) {
  raw <- readr::read_csv(path, col_types = readr::cols(.default = "c"),
                         show_col_types = FALSE, progress = FALSE)
  # A field can sit in several language-tagged columns: take the first filled one
  pick <- function(field) {
    cols <- names(raw)[sub("\\[.*\\]$", "", names(raw)) == field]
    if (!length(cols)) return(rep(NA_character_, nrow(raw)))
    do.call(dplyr::coalesce, unname(as.list(raw[cols])))
  }
  # Where DOIs appear, most reliable first
  doi_fields <- c("dc.identifier.doi", "dc.identifier.uri", "dc.identifier.other",
                  "dc.identifier", "dc.identifier.citation", "dc.relation.ispartof")
  doi_text <- do.call(paste, lapply(doi_fields, pick))
  tibble::tibble(
    handle   = stringr::str_extract(pick("dc.identifier.uri"), "11606/\\d+"),
    private  = raw$collection %in% copa_private,
    doi      = first_doi(doi_text),
    title    = pick("dc.title"),
    authors  = copa_multi(pick("dc.contributor.author")),
    year     = as.integer(stringr::str_extract(pick("dc.date.issued"), "\\d{4}")),
    type     = copa_first(pick("dc.type")),
    abstract = pick("dc.description.abstract"),
    language = substr(copa_first(pick("dc.language.iso")), 1, 2),
    venue    = copa_first(dplyr::coalesce(pick("dc.relation.ispartof"), pick("dc.publisher"))),
    subjects = copa_multi(pick("dc.subject"))
  ) |> dplyr::filter(!is.na(handle), !is.na(title))
}

xml_text <- function(x) {
  x <- gsub("<!\\[CDATA\\[|\\]\\]>", "", x)
  x <- gsub("&lt;", "<", gsub("&gt;", ">", gsub("&quot;", "\"", gsub("&apos;", "'", x, fixed = TRUE), fixed = TRUE), fixed = TRUE), fixed = TRUE)
  x <- gsub("&#(\\d+);", "\\1", x)   # numeric entities: rare in titles, kept as numbers
  trimws(gsub("&amp;", "&", x, fixed = TRUE))
}

#' Every public record in a COPA OAI set (Dublin Core), deleted ones left out.
harvest_copa_oai <- function(set = copa_set, base = copa_base) {
  query <- list(verb = "ListRecords", metadataPrefix = "oai_dc", set = set)
  records <- character()
  repeat {
    xml <- httr2::request(paste0(base, "/oai/request")) |>
      httr2::req_url_query(!!!query) |>
      httr2::req_user_agent("acg-data-catalog (https://github.com/acg-atlas)") |>
      httr2::req_retry(max_tries = 4, backoff = function(i) 2^i) |>
      httr2::req_timeout(120) |>
      httr2::req_perform() |>
      httr2::resp_body_string()
    records <- c(records, stringr::str_extract_all(xml, "(?s)<record>.*?</record>")[[1]])
    token <- stringr::str_match(xml, "<resumptionToken[^>]*>([^<]+)</resumptionToken>")[, 2]
    if (is.na(token)) break
    query <- list(verb = "ListRecords", resumptionToken = token)
  }
  parse_copa_records(records)
}

parse_copa_records <- function(records) {
  records <- records[!grepl("<header status=\"deleted\"", records)]
  if (!length(records)) return(empty_copa())
  dc <- function(rec, tag) {
    v <- stringr::str_match_all(rec, sprintf("(?s)<dc:%s[^>]*>(.*?)</dc:%s>", tag, tag))[[1]][, 2]
    if (length(v)) xml_text(v) else NA_character_
  }
  purrr::map(records, function(r) {
    ids <- c(dc(r, "identifier"), dc(r, "relation"))
    # dc:date lists upload dates as well as the publication date: take the earliest
    years <- as.integer(stringr::str_extract(dc(r, "date"), "\\d{4}"))
    tibble::tibble(
      handle   = stringr::str_extract(stringr::str_match(r, "<identifier>([^<]+)</identifier>")[, 2], "11606/\\d+"),
      private  = grepl(paste0("<setSpec>col_", sub("/", "_", copa_private), "</setSpec>"), r, fixed = TRUE),
      doi      = first_doi(paste(ids, collapse = " ")),
      title    = dc(r, "title")[1],
      authors  = paste(stats::na.omit(dc(r, "creator")), collapse = "; "),
      year     = if (all(is.na(years))) NA_integer_ else min(years, na.rm = TRUE),
      type     = dc(r, "type")[1],
      abstract = dc(r, "description")[1],
      language = substr(dc(r, "language")[1], 1, 2),
      venue    = dc(r, "publisher")[1],
      subjects = paste(stats::na.omit(dc(r, "subject")), collapse = "; ")
    )
  }) |> dplyr::bind_rows() |>
    dplyr::mutate(authors = dplyr::na_if(authors, ""), subjects = dplyr::na_if(subjects, "")) |>
    dplyr::filter(!is.na(handle), !is.na(title))
}

# COPA item types -> the OpenAlex types the site groups by
copa_types <- c(Article = "article", Thesis = "dissertation", Book = "book",
                `Book chapter` = "book-chapter", Report = "report",
                `Technical Report` = "report", `Reporte de Trabajo` = "report",
                `Working Paper` = "report", Presentation = "other", Other = "other")

#' Index of the closest curated paper for each COPA item (or NA): imported from
#' the same COPA page before, the same DOI, or
#' same title (normalized, edit distance <= 5%) within a year.
match_copa <- function(copa, curated) {
  ckey <- title_key(curated$title)
  seen <- if (all(c("id", "copa") %in% names(curated))) {   # Atlas entries, not other COPA rows
    function(h) which(curated$id == paste0("copa:", h) | curated$copa %in% h)
  } else function(h) integer()
  ckey[grepl("^(map|figure|fig|table|plate) \\d+ (in|from) ", ckey)] <- NA   # "Map 2 in <the book>" is not the book
  purrr::map_int(seq_len(nrow(copa)), function(i) {
    hit <- seen(copa$handle[i])
    if (length(hit)) return(hit[1])          # imported from COPA before
    if (!is.na(copa$doi[i])) {
      hit <- which(curated$doi == copa$doi[i])
      if (length(hit)) return(hit[1])
    }
    k <- sub("^\\d{1,2} ", "", title_key(copa$title[i]))   # COPA titles sometimes start "1 Review…"
    if (nchar(k) < 15) return(NA_integer_)   # "Introduction", "Editorial"…
    near <- which(is.na(curated$year) | is.na(copa$year[i]) | abs(curated$year - copa$year[i]) <= 1)
    if (!length(near)) return(NA_integer_)
    # COPA sometimes cuts long titles short: a 40+ character start counts too
    if (nchar(k) >= 40) {
      cut <- which(!is.na(ckey[near]) & (startsWith(ckey[near], k) | startsWith(k, ckey[near])) &
                   nchar(ckey[near]) >= 40)
      if (length(cut)) return(near[cut[1]])
    }
    d <- as.numeric(utils::adist(k, ckey[near]))
    best <- which.min(d)
    if (length(best) && d[best] <= 0.05 * nchar(k)) near[best] else NA_integer_
  })
}

#' One row per COPA item. Copies share a DOI, or a title (normalized, edit
#' distance <= 5%) within a year: an item uploaded twice, under two DOIs, or
#' with a typo. Keep a copy with a DOI, then a public one, then the oldest, and
#' take the COPA page from a public copy when the kept one is private.
dedupe_copa <- function(copa) {
  copa <- copa |>
    dplyr::arrange(is.na(doi), dplyr::desc(public), num)
  by_doi <- match(copa$doi, copa$doi)            # first row with the same DOI
  first <- ifelse(is.na(copa$doi), NA_integer_, by_doi)
  keep <- is.na(first) | first == seq_len(nrow(copa))
  for (i in which(keep)) {                       # titles, against rows kept so far
    earlier <- which(keep[seq_len(i - 1)])
    if (!length(earlier)) next
    j <- match_copa(dplyr::mutate(copa[i, ], doi = NA_character_), copa[earlier, ])
    if (!is.na(j)) { keep[i] <- FALSE; first[i] <- earlier[j] }
  }
  for (i in which(!keep)) {                      # a public copy lends its page
    j <- first[i]
    while (!keep[j]) j <- first[j]
    if (!copa$public[j] && copa$public[i]) { copa$handle[j] <- copa$handle[i]; copa$public[j] <- TRUE }
  }
  copa[keep, ]
}

#' Fold COPA items into the curated papers.
#'   - duplicates inside COPA collapse to one (same DOI, or same title + year),
#'     keeping a public handle when there is one
#'   - items already in the Atlas: add the COPA link; pending ones are
#'     approved; excluded ones are listed for a second look, not changed
#'   - new items: added as approved
#' `lookup` resolves DOIs to metadata (OpenAlex, then Crossref); `exists` asks doi.org.
merge_copa <- function(curated, copa, gazetteer, taxon_rules, theme_rules,
                       lookup = copa_lookup, exists = doi_exists, today = Sys.Date()) {
  copa <- copa |>
    dplyr::mutate(public = !private,
                  num = as.integer(sub(".*/", "", handle)))
  n_items <- nrow(copa)
  datasets <- dplyr::filter(copa, !is.na(type), type == "Dataset")   # for the data side, not papers
  copa <- dplyr::filter(copa, is.na(type) | type != "Dataset")
  n_rows <- nrow(copa)
  copa <- dedupe_copa(copa)
  dup_inside <- n_rows - nrow(copa)

  # Already in the Atlas?
  hit <- match_copa(copa, curated)
  recheck <- tibble::tibble()
  linked <- 0L; approved_now <- 0L
  for (i in which(!is.na(hit))) {
    j <- hit[i]
    if (copa$public[i] && is.na(curated$copa[j])) { curated$copa[j] <- copa$handle[i]; linked <- linked + 1L }
    if (curated$review[j] == "pending") { curated$review[j] <- "approved"; approved_now <- approved_now + 1L }
    if (curated$review[j] == "excluded")
      recheck <- dplyr::bind_rows(recheck, tibble::tibble(
        id = curated$id[j], title = curated$title[j], year = curated$year[j],
        copa = paste0(copa_base, "/handle/", copa$handle[i])))
  }

  # New to the Atlas
  new <- copa[is.na(hit), ]
  meta <- lookup(new$doi)
  not_papers <- attr(meta, "excluded") %||% character()   # OpenAlex says dataset, erratum…
  meta <- dplyr::filter(meta, !doi %in% not_papers)
  not_paper <- sum(new$doi %in% not_papers)
  new <- dplyr::filter(new, is.na(doi) | !doi %in% not_papers)
  # A DOI that OpenAlex and Crossref don't know and doi.org can't resolve is a
  # typo in COPA ("zookeys.@@"): drop it rather than link to a dead page
  unknown <- setdiff(stats::na.omit(new$doi), meta$doi)
  bad_doi <- new$doi %in% unknown[!vapply(unknown, exists, logical(1))]
  new$doi[bad_doi] <- NA
  private_no_doi <- sum(is.na(new$doi) & !new$public)   # no DOI, no public page: nothing to link to
  new <- dplyr::filter(new, !is.na(doi) | public)
  from_meta <- dplyr::inner_join(dplyr::select(new, doi, handle, public, copa_abstract = abstract,
                                               subjects),
                                 meta, by = "doi")
  from_copa <- new |>
    dplyr::filter(is.na(doi) | !doi %in% meta$doi) |>
    dplyr::transmute(doi, handle, public, title, year, venue, authors, abstract, subjects,
                     type = unname(dplyr::coalesce(copa_types[type], "other")),
                     language, meta_source = "copa", is_oa = FALSE)
  added <- dplyr::bind_rows(
    dplyr::mutate(from_meta, abstract = dplyr::coalesce(abstract, copa_abstract)),
    from_copa
  ) |>
    dplyr::mutate(id = dplyr::coalesce(doi, paste0("copa:", handle)),
                  copa = ifelse(public, handle, NA_character_),
                  topics = dplyr::coalesce(topics, subjects))
  if (nrow(added)) {
    text <- paste(added$title, added$abstract)
    added <- added |>
      dplyr::mutate(review = "approved", found_by = "copa", relevance = "likely",
                    relevance_reason = "in COPA (ACG's repository)",
                    sectors = guess_sectors(text, gazetteer, rep(NA_character_, dplyr::n())),
                    added = as.character(today))
    keyed <- dplyr::mutate(added, openalex_id = id)   # tag_papers joins texts on openalex_id
    tagged <- tag_papers(keyed, keyed, taxon_rules, theme_rules)
    added$taxa <- tagged$taxa; added$themes <- tagged$themes
    curated <- dplyr::bind_rows(curated, conform_papers(added))
  }

  attr(curated, "copa") <- list(
    counts = c(copa_items = n_items, duplicates_inside_copa = dup_inside,
               datasets_skipped = nrow(datasets), already_in_atlas = sum(!is.na(hit)),
               copa_links_added = linked, pending_approved = approved_now,
               excluded_to_recheck = nrow(recheck), new_with_doi = nrow(from_meta) +
                 sum(!is.na(from_copa$doi)),
               new_without_doi = sum(is.na(from_copa$doi)), dois_not_found = sum(bad_doi),
               private_without_doi_skipped = private_no_doi, not_papers_skipped = not_paper),
    recheck = recheck, datasets = datasets)
  curated
}

#' TRUE when doi.org knows the DOI (its handle API answers responseCode 1).
doi_exists <- function(doi) {
  res <- tryCatch(get_json(paste0("https://doi.org/api/handles/", utils::URLencode(doi, reserved = TRUE))),
                  error = function(e) NULL)
  isTRUE(res$responseCode == 1)
}

#' OpenAlex metadata for DOIs, Crossref for the rest. DOIs OpenAlex knows but
#' types as non-papers (datasets, errata) are returned in attr "excluded".
copa_lookup <- function(dois) {
  dois <- unique(stats::na.omit(dois))
  oa <- openalex_by_doi(dois)
  cr <- crossref_by_doi(setdiff(dois, oa$doi))
  out <- dplyr::bind_rows(oa, cr)
  attr(out, "excluded") <- out$doi[!is.na(out$type) & out$type %in% excluded_types]
  out
}
