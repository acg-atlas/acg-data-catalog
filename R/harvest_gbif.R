# GBIF harvester -------------------------------------------------------------
#
# A true spatial search: which GBIF datasets have occurrence records inside
# the ACG boundary, and how many. This catches datasets whose metadata never
# mention ACG by name (e.g. iNaturalist, eBird, museum collections).

harvest_gbif <- function(wkt, min_records = 10, max_datasets = 2000) {
  facets <- list()
  offset <- 0
  page <- 500
  repeat {
    res <- get_json("https://api.gbif.org/v1/occurrence/search", query = list(
      geometry = wkt, limit = 0, facet = "datasetKey",
      facetLimit = page, facetOffset = offset
    ))
    counts <- res$facets[[1]]$counts %||% list()
    facets <- c(facets, counts)
    if (length(counts) < page || length(facets) >= max_datasets) break
    offset <- offset + page
  }
  if (length(facets) == 0) return(empty_candidates())

  keys <- tibble::tibble(
    key = purrr::map_chr(facets, "name"),
    acg_records = purrr::map_int(facets, ~ as.integer(.x$count))
  ) |>
    dplyr::filter(acg_records >= min_records)

  purrr::map2(keys$key, keys$acg_records, gbif_dataset_record) |>
    dplyr::bind_rows() |>
    as_candidates()
}

gbif_dataset_record <- function(key, acg_records) {
  d <- get_json(paste0("https://api.gbif.org/v1/dataset/", key))
  tibble::tibble(
    doi           = normalize_doi(d$doi %||% NA_character_),
    title         = d$title %||% NA_character_,
    creators      = gbif_creators(d$contacts %||% list()),
    year          = suppressWarnings(as.integer(substr(d$pubDate %||% d$created %||% NA, 1, 4))),
    publisher     = gbif_org_title(d$publishingOrganizationKey %||% NA_character_),
    url           = paste0("https://www.gbif.org/dataset/", key),
    license       = d$license %||% NA_character_,
    resource_type = paste("Dataset", d$type %||% "", sep = "/"),
    source        = "gbif",
    text          = paste(d$title %||% "", d$description %||% ""),
    acg_records   = acg_records
  )
}

gbif_creators <- function(contacts) {
  people <- purrr::keep(contacts, ~ isTRUE(.x$primary) &&
                          identical(.x$type, "ORIGINATOR"))
  if (length(people) == 0) people <- purrr::keep(contacts, ~ isTRUE(.x$primary))
  nm <- purrr::map_chr(people, ~ trimws(paste(.x$firstName %||% "",
                                              .x$lastName %||% .x$organization %||% "")))
  paste(unique(nm[nzchar(nm)]), collapse = "; ")
}

# Publisher names, cached so each organization is looked up once per run.
.gbif_orgs <- new.env()
gbif_org_title <- function(key) {
  if (is.na(key)) return("GBIF")
  if (is.null(.gbif_orgs[[key]])) {
    org <- tryCatch(get_json(paste0("https://api.gbif.org/v1/organization/", key)),
                    error = function(e) list())
    .gbif_orgs[[key]] <- org$title %||% "GBIF"
  }
  .gbif_orgs[[key]]
}
