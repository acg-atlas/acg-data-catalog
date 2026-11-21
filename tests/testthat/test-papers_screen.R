queued <- function(...) {
  base <- list(id = "10.1/new", openalex_id = "W9", doi = "10.1/new",
               title = "Leaf traits of dry forest trees", year = 2026L,
               authors = "Ana Pérez", type = "article", abstract = "",
               found_by = "openalex_fulltext", relevance = "check",
               relevance_reason = "found by openalex_fulltext")
  tibble::as_tibble(utils::modifyList(base, list(...)))
}

listed <- conform_papers(tibble::tibble(
  id = c("10.1/a", "10.1/b", "10.1/c", "10.1/d"),
  title = c("Caterpillars of Santa Rosa", "Moths of Pitilla",
            "Parasitoids of Cacao", "An older study"),
  year = c(2001L, 2005L, 2010L, 1999L),
  authors = c("Winnie Hallwachs; Daniel H. Janzen", "Daniel H. Janzen",
              "Daniel H. Janzen", "Someone Else"),
  review = c("approved", "approved", "approved", "excluded")
))

test_that("acg_authors needs several approved papers, ignoring accents and case", {
  expect_equal(acg_authors(listed), "daniel h. janzen")
})

test_that("full-text-only papers with no ACG place, region or author are excluded", {
  q <- dplyr::bind_rows(
    queued(id = "1"),                                              # no signal
    queued(id = "2", abstract = "Sampled in Guanacaste, Costa Rica"),  # region
    queued(id = "3", authors = "Daniel H. Janzen; X Y"),           # ACG author
    queued(id = "4", title = "Bats of Sector Santa Rosa"),         # ACG place
    queued(id = "5", found_by = "openalex_core")                   # core search
  )
  out <- auto_screen_papers(q, listed, gazetteer)
  expect_equal(out$review, c("excluded", "pending", "pending", "pending", "pending"))
  expect_match(out$relevance_reason[1], "^auto-excluded: no ACG place")
})

test_that("non-paper types are excluded unless an ACG place is named", {
  q <- dplyr::bind_rows(
    queued(id = "1", type = "other", abstract = "Costa Rica elections"),
    queued(id = "2", type = "other", title = "Hacienda Santa Rosa: history")
  )
  expect_equal(auto_screen_papers(q, listed, gazetteer)$review, c("excluded", "pending"))
})

test_that("a new record with the title of a listed paper is a duplicate", {
  q <- dplyr::bind_rows(
    queued(id = "1", title = "Moths of PITILLA.", year = 2006L, found_by = "openalex_core"),
    queued(id = "2", title = "Moths of Pitilla", year = 2015L, found_by = "openalex_core")
  )
  out <- auto_screen_papers(q, listed, gazetteer)
  expect_equal(out$review, c("excluded", "pending"))
  expect_match(out$relevance_reason[1], "duplicate")
})

test_that("append_pending_papers keeps auto-excluded papers excluded", {
  f <- withr::local_tempfile(fileext = ".yaml")
  q <- auto_screen_papers(dplyr::bind_rows(queued(id = "1"),
                                           queued(id = "2", abstract = "Costa Rica")),
                          listed, gazetteer)
  append_pending_papers(f, listed, q)
  expect_equal(read_papers(f)$review[5:6], c("excluded", "pending"))
})
