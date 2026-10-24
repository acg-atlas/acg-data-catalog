paper <- function(...) {
  base <- list(openalex_id = "W1", doi = "10.1/a", title = "A study",
               year = 2020L, venue = "J", authors = "A B", type = "article",
               abstract = "", meta_source = "openalex", found_by = "openalex_core")
  tibble::as_tibble(utils::modifyList(base, list(...)))
}

test_that("read_wos keeps matching fields only and normalizes DOIs", {
  f <- withr::local_tempfile(fileext = ".txt")
  writeLines(c("PT\tAU\tTI\tPY\tDI\tAB\tUT",
               "J\tSmith, A\tDry forest bees\t2001\tHTTPS://doi.org/10.1234/ABC\tsecret abstract\tWOS:1",
               "J\tLee, B\tNo doi here\t1999\t\t\tWOS:2"), f)
  w <- read_wos(f)
  expect_named(w, c("wos_id", "doi", "title", "year"))
  expect_equal(w$doi, c("10.1234/abc", NA))
  expect_false(any(grepl("secret", unlist(w))))
})

test_that("literature_query ties sector names to Costa Rica and skips ambiguous ones", {
  q <- literature_query(gazetteer)
  expect_match(q, '"Area de Conservacion Guanacaste"', fixed = TRUE)
  expect_match(q, 'AND "Costa Rica")', fixed = TRUE)
  expect_false(grepl('"Horizontes"', q, fixed = TRUE))
  expect_false(grepl('AND "Costa Rica"', literature_query(gazetteer, strong_only = TRUE), fixed = TRUE))
})

test_that("title_key ignores case, accents and punctuation", {
  expect_equal(title_key("Árboles: of the  DRY forest!"), title_key("arboles of the dry forest"))
})

test_that("combine_papers merges sources by DOI and drops non-paper types", {
  out <- combine_papers(
    paper(found_by = "wos", meta_source = "crossref", title = "From Crossref"),
    paper(found_by = "openalex_core"),
    paper(doi = NA, openalex_id = "W2", found_by = "openalex_fulltext"),
    paper(doi = "10.1/ds", openalex_id = "W3", type = "dataset")
  )
  expect_equal(nrow(out), 2)
  a <- out[out$id == "10.1/a", ]
  expect_equal(a$found_by, "openalex_core; wos")
  expect_equal(a$title, "A study")            # OpenAlex metadata preferred
  expect_true("W2" %in% out$id)               # no DOI: keyed by OpenAlex id
})

test_that("Zenodo figure and species-description fragments are dropped", {
  expect_equal(is_fragment(
    c("10.5281/zenodo.1", "10.5281/zenodo.2", "10.5281/zenodo.3", "10.1234/x"),
    c("FIGURE 1. Meteorus alejandromasisi in Revision of the genus Meteorus",
      "Meteorus andreae Aguirre & Shaw 2011",
      "A long report on dry forest restoration in the Area de Conservacion Guanacaste",
      "Short title")),
    c(TRUE, TRUE, FALSE, FALSE))
})

test_that("score_papers: core/WoS or strong name -> likely; full text only -> check", {
  p <- combine_papers(
    paper(doi = "10.1/a", found_by = "wos"),
    paper(doi = "10.1/b", openalex_id = "W2", found_by = "openalex_fulltext"),
    paper(doi = "10.1/c", openalex_id = "W3", found_by = "openalex_fulltext",
          title = "Bats of Area de Conservacion Guanacaste")
  ) |> score_papers(gazetteer)
  expect_equal(p$relevance[match(c("10.1/a", "10.1/b", "10.1/c"), p$id)],
               c("likely", "check", "likely"))
})

test_that("papers.yaml round trip and new_papers never re-queue", {
  path <- withr::local_tempfile(fileext = ".yaml")
  scored <- combine_papers(paper(), paper(doi = "10.1/b", openalex_id = "W2")) |>
    score_papers(gazetteer)
  cur <- read_papers(path)
  append_pending_papers(path, cur, new_papers(scored, cur))
  cur <- read_papers(path)
  expect_equal(nrow(cur), 2)
  expect_true(all(cur$review == "pending"))
  cur$review <- c("approved", "excluded")
  write_papers(cur, path)
  expect_equal(nrow(new_papers(scored, read_papers(path))), 0)
  json <- withr::local_tempfile(fileext = ".json")
  build_papers_json(read_papers(path), json)
  expect_length(jsonlite::read_json(json), 1)
})
