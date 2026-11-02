test_that("a failing source is skipped, not fatal, and is named", {
  out <- suppressWarnings(
    try_source("OpenAlex full-text search", stop("HTTP 504 Gateway Timeout."), empty_candidates()))
  expect_equal(nrow(out), 0)
  expect_equal(names(out), names(empty_candidates()))
  expect_match(attr(out, "skipped"), "OpenAlex full-text search (HTTP 504", fixed = TRUE)
  expect_warning(try_source("GBIF", stop("down"), empty_candidates()), "GBIF skipped")
})

test_that("a working source passes through unchanged", {
  ok <- try_source("DataCite", tibble::tibble(x = 1), empty_candidates())
  expect_equal(ok, tibble::tibble(x = 1))
  expect_null(skipped_sources(ok))
})

test_that("skipped sources are listed first in the review summary", {
  f <- tempfile(fileext = ".md")
  review_summary(empty_candidates(), f, skipped = "OpenAlex full-text search (HTTP 504)")
  txt <- readLines(f)
  expect_match(txt[1], "Skipped this week")
  expect_true(any(grepl("OpenAlex full-text search (HTTP 504)", txt, fixed = TRUE)))
})
