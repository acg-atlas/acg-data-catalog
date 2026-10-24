subs <- parse_submissions(list(
  list(doi = "10.1234/DATA", title = "Leaf traits", year = 2025, sector = "Pitilla"),
  list(doi = "10.1234/paper", kind = "paper", title = "A paper", year = 2024),
  list(doi = "10.1234/data2", kind = "dataset", title = "More data")
))

test_that("submissions without a kind are datasets", {
  expect_equal(subs$kind, c("dataset", "paper", "dataset"))
  expect_equal(subs$doi[1], "10.1234/data")
})

test_that("only dataset submissions become dataset candidates", {
  d <- dataset_submissions(subs)
  expect_equal(d$doi, c("10.1234/data", "10.1234/data2"))
  expect_true(all(d$source == "submission"))
  expect_equal(names(d), names(empty_candidates()))
})

test_that("no paper suggestions gives an empty papers table", {
  p <- paper_submissions(dplyr::filter(subs, kind != "paper"))
  expect_equal(nrow(p), 0)
  expect_true("found_by" %in% names(p))
})

test_that("statuses come from either catalog file", {
  curated <- tibble::tibble(doi = c("10.1234/data", "10.9/other"), review = c("approved", "approved"))
  papers <- tibble::tibble(doi = c("10.1234/paper", "10.1234/data2"), review = c("excluded", "pending"))
  s <- submission_statuses(subs, curated, papers)
  expect_equal(s$doi, c("10.1234/data", "10.1234/paper"))
  expect_equal(s$review, c("approved", "excluded"))
})
