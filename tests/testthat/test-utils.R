test_that("normalize_doi handles common forms", {
  expect_equal(normalize_doi("https://doi.org/10.5061/DRYAD.ABC123"),
               "10.5061/dryad.abc123")
  expect_equal(normalize_doi(" doi:10.6073/pasta/xyz "), "10.6073/pasta/xyz")
  expect_equal(normalize_doi("http://dx.doi.org/10.15468/inygc6"), "10.15468/inygc6")
  expect_true(is.na(normalize_doi("not a doi")))
  expect_true(is.na(normalize_doi(NA)))
})

test_that("as_candidates fills the schema", {
  x <- as_candidates(tibble::tibble(doi = "10.1/a", title = "t"))
  expect_named(x, names(empty_candidates()))
  expect_true(is.na(x$acg_records))
})
