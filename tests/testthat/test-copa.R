curated_paper <- function(...) {
  base <- list(id = "10.1111/a", doi = "10.1111/a", title = "Dry forest regeneration in Santa Rosa",
               year = 2010L, review = "approved")
  conform_papers(tibble::as_tibble(utils::modifyList(base, list(...))))
}
copa_item <- function(...) {
  base <- list(handle = "11606/1", private = FALSE, doi = NA_character_, title = "A title", authors = "A B",
               year = 2010L, type = "Article", abstract = NA_character_, language = "en",
               venue = NA_character_, subjects = NA_character_)
  tibble::as_tibble(utils::modifyList(base, list(...)))
}
no_rules <- tibble::tibble(taxon = character(), parent = character(), pattern = character())
no_themes <- tibble::tibble(theme = character(), pattern = character(), weight = character())
fake_lookup <- function(dois) {
  known <- intersect(dois, c("10.9999/new", "10.9999/data"))
  out <- dplyr::bind_rows(empty_papers(), tibble::tibble(
    doi = known, openalex_id = rep("W9", length(known)),
    title = rep("From OpenAlex", length(known)), year = rep(2020L, length(known)),
    authors = rep("X Y", length(known)),
    type = ifelse(known == "10.9999/data", "dataset", "article") |> as.character(),
    meta_source = rep("openalex", length(known))))
  attr(out, "excluded") <- out$doi[out$type %in% excluded_types]
  out
}
merge <- function(curated, items) {
  suppressWarnings(merge_copa(curated, items, gazetteer, no_rules, no_themes,
                              lookup = fake_lookup, exists = function(d) FALSE,
                              today = as.Date("2026-10-30")))
}

test_that("DOIs are found in any identifier column and handles in the URI", {
  f <- withr::local_tempfile(fileext = ".csv")
  writeLines(c(
    'id,collection,dc.contributor.author[],dc.date.issued[],dc.identifier.doi[],dc.identifier.uri,dc.identifier.other,dc.title[es_CR],dc.type[es_CR]',
    '1,11606/49,"Janzen, D.||Hallwachs, W.",1999-05,,http://hdl.handle.net/11606/357,"DOI: 10.1111/ABC.123.",Title one,Article',
    '2,11606/48,"Smith, A.",2003,https://doi.org/10.2345/x,http://hdl.handle.net/11606/400,,Title two,Thesis||Other'), f)
  x <- read_copa_csv(f)
  expect_equal(x$handle, c("11606/357", "11606/400"))
  expect_equal(x$doi, c("10.1111/abc.123", "10.2345/x"))
  expect_equal(x$authors[1], "Janzen, D.; Hallwachs, W.")
  expect_equal(x$type, c("Article", "Thesis"))
  expect_equal(x$year, c(1999L, 2003L))
  expect_equal(x$private, c(FALSE, TRUE))   # collection 11606/48 is ColecciÃ³n Privada
})

test_that("OAI records are parsed and deleted ones skipped", {
  rec <- c(paste0('<record><header><identifier>oai:copa.acguanacaste.ac.cr:11606/98</identifier><setSpec>col_11606_48</setSpec></header>',
                  '<metadata><oai_dc:dc><dc:title>Frogs &amp; toads</dc:title><dc:creator>Pounds, A.</dc:creator>',
                  '<dc:creator>Crump, M.</dc:creator><dc:date>2007</dc:date><dc:type>Article</dc:type>',
                  '<dc:identifier>http://hdl.handle.net/11606/98</dc:identifier>',
                  '<dc:identifier>https://doi.org/10.3456/Frog</dc:identifier></oai_dc:dc></metadata></record>'),
           '<record><header status="deleted"><identifier>oai:x:11606/5</identifier></header></record>')
  x <- parse_copa_records(rec)
  expect_equal(nrow(x), 1)
  expect_equal(x$title, "Frogs & toads")
  expect_equal(x$authors, "Pounds, A.; Crump, M.")
  expect_equal(x$doi, "10.3456/frog")
  expect_true(x$private)
})

test_that("merge_copa links, approves, adds and removes duplicates", {
  curated <- dplyr::bind_rows(
    curated_paper(),                                                   # same DOI as a COPA item
    curated_paper(id = "10.1111/b", doi = "10.1111/b", title = "Caterpillars of Pitilla rain forest",
                  review = "pending"),                                 # same title, no DOI in COPA
    curated_paper(id = "10.1111/c", doi = "10.1111/c", title = "Bats of the Guanacaste dry forest",
                  review = "excluded"))
  items <- dplyr::bind_rows(
    copa_item(handle = "11606/10", doi = "10.1111/a"),
    copa_item(handle = "11606/11", title = "Caterpillars of Pitilla rain-forest", year = 2011L),
    copa_item(handle = "11606/12", doi = "10.1111/c", title = "Bats of the Guanacaste dry forest"),
    copa_item(handle = "11606/20", doi = "10.9999/new", title = "A new paper on dry forest bees"),
    copa_item(handle = "11606/21", doi = "10.9999/NEW", title = "A new paper on dry forest bees"),      # duplicate upload
    copa_item(handle = "11606/22", title = "A new paper on dry forest bees"),                        # same, without DOI
    copa_item(handle = "11606/30", title = "An old thesis about dry forest birds", type = "Thesis"),
    copa_item(handle = "11606/31", title = "A private report with no DOI at all"),
    copa_item(handle = "11606/40", doi = "10.9999/data", title = "Climate data"),
    copa_item(handle = "11606/41", title = "Station records", type = "Dataset"),
    copa_item(handle = "11606/50", doi = "10.9999/typo", title = "A paper whose DOI has a typo in COPA"),
    copa_item(handle = "11606/51", title = "Caterpilars of Pitilla rain forest", year = 2012L),
    copa_item(handle = "11606/52", title = "Editorial"))
  items$doi <- normalize_doi(items$doi)
  items$private <- !items$handle %in% c("11606/10", "11606/11", "11606/12", "11606/21", "11606/30", "11606/40", "11606/50", "11606/52")
  out <- merge(curated, items)
  info <- attr(out, "copa")

  expect_equal(out$copa[out$id == "10.1111/a"], "11606/10")             # link added
  expect_equal(out$review[out$id == "10.1111/b"], "approved")           # pending -> approved
  expect_equal(out$copa[out$id == "10.1111/b"], "11606/11")
  expect_equal(out$review[out$id == "10.1111/c"], "excluded")           # excluded left aloneâ€¦
  expect_equal(nrow(info$recheck), 1)                                 # â€¦but listed

  new <- out[out$found_by %in% "copa", ]
  expect_equal(sort(new$id), c("10.9999/new", "copa:11606/30", "copa:11606/50", "copa:11606/52"))   # one copy each; typo DOI -> COPA page
  expect_equal(new$copa[new$id == "10.9999/new"], "11606/21")           # the public duplicate's handle
  expect_equal(new$title[new$id == "10.9999/new"], "From OpenAlex")     # DOI items use OpenAlex metadata
  expect_true(all(new$review == "approved"))
  expect_equal(new$type[new$id == "copa:11606/30"], "dissertation")
  expect_equal(info$counts[["private_without_doi_skipped"]], 1)
  expect_equal(info$counts[["datasets_skipped"]], 1)
  expect_equal(info$counts[["not_papers_skipped"]], 1)
  expect_equal(info$counts[["dois_not_found"]], 1)

  again <- merge(out, items)                                  # weekly rerun changes nothing
  expect_equal(nrow(again), nrow(out))
  expect_equal(attr(again, "copa")$counts[["copa_links_added"]], 0)
})

test_that("publisher page names are cut from DOIs", {
  expect_equal(first_doi("https://onlinelibrary.wiley.com/doi/10.1111/j.1744-7429.2010.00667.x/full"),
               "10.1111/j.1744-7429.2010.00667.x")
  expect_equal(first_doi("doi:10.1016/S0006-3207(00)00123-4."), "10.1016/s0006-3207(00)00123-4")
})
