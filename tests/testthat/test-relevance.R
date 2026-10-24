cands <- as_candidates(tibble::tibble(
  doi = c("10.1/a", "10.1/b", "10.1/c", "10.1/d", "10.1/e"),
  title = c("Leaf traits in Área de Conservación Guanacaste",
            "Bird counts, Santa Rosa, California",
            "Soil cores, Santa Rosa, Guanacaste, Costa Rica",
            "Unrelated data", "My acoustic data"),
  publisher = c("EDI", "Dryad", "Zenodo", "Zenodo", "Zenodo"),
  source = c("datacite", "datacite", "datacite", "gbif", "submission"),
  acg_records = c(NA, NA, NA, 5000L, NA)
)) |> dplyr::mutate(text = title)

test_that("scoring separates ACG from look-alikes", {
  s <- score_relevance(cands, gazetteer)
  expect_equal(s$relevance[1], "likely")
  expect_equal(s$relevance[2], "unlikely")   # Santa Rosa, California
  expect_equal(s$relevance[3], "check")      # sector + context only
  expect_equal(s$relevance[4], "likely")     # GBIF spatial
  expect_equal(s$relevance[5], "check")      # submitted, no other evidence
  expect_match(s$sectors[3], "Santa Rosa")
})

test_that("Plazi treatments are labeled", {
  x <- cands[1, ]; x$publisher <- "Pensoft via Plazi"
  expect_equal(score_relevance(x, gazetteer)$category, "taxonomic treatment")
})

test_that("dedupe merges sources and keeps GBIF counts", {
  d <- dplyr::bind_rows(
    as_candidates(tibble::tibble(doi = "10.15468/x", title = "T",
                                 source = "datacite", text = "T")),
    as_candidates(tibble::tibble(doi = "10.15468/x", source = "gbif",
                                 acg_records = 42L, text = "T")),
    as_candidates(tibble::tibble(url = "https://www.gbif.org/dataset/k",
                                 source = "gbif", text = "no doi"))
  ) |> dedupe_candidates()
  expect_equal(nrow(d), 2)
  row <- d[d$id == "10.15468/x", ]
  expect_equal(row$acg_records, 42L)
  expect_equal(row$source, "datacite+gbif")
})

test_that("versions of the same dataset collapse to one row", {
  v <- as_candidates(tibble::tibble(
    doi = c("10.5281/zenodo.1", "10.5281/zenodo.2", "10.5281/zenodo.3"),
    title = c("Bromeliad insects", "Bromeliad Insects", "Other"),
    publisher = "Zenodo", year = c(2020L, 2021L, 2021L), source = "datacite",
    text = "x")) |> dedupe_candidates() |> collapse_versions()
  expect_equal(nrow(v), 2)
  b <- v[v$title %in% c("Bromeliad insects", "Bromeliad Insects"), ]
  expect_equal(b$doi, "10.5281/zenodo.2")
  expect_equal(b$versions, "10.5281/zenodo.1")
})
