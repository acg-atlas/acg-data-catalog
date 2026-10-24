test_that("curated YAML round-trips and never re-queues known entries", {
  path <- withr::local_tempfile(fileext = ".yaml")
  writeLines("[]", path)
  cur <- read_curated(path)
  expect_equal(nrow(cur), 0)

  scored <- as_candidates(tibble::tibble(
    doi = c("10.1/a", "10.1/b"), title = c("A", "B"), source = "datacite",
    text = c("Área de Conservación Guanacaste", "Guanacaste Conservation Area")
  )) |> dedupe_candidates() |> score_relevance(gazetteer)

  q <- new_candidates(scored, cur)
  expect_equal(nrow(q), 2)
  append_pending(path, cur, q, today = as.Date("2026-10-24"))

  cur2 <- read_curated(path)
  expect_equal(cur2$review, c("pending", "pending"))
  expect_equal(nrow(new_candidates(scored, cur2)), 0)

  # Exclude one, approve one, and check only approved reaches the site
  cur2$review <- c("approved", "excluded")
  write_curated(cur2, path)
  cur3 <- read_curated(path)
  expect_equal(nrow(new_candidates(scored, cur3)), 0)
  json <- withr::local_tempfile(fileext = ".json")
  build_catalog_json(cur3, json)
  out <- jsonlite::read_json(json)
  expect_length(out, 1)
  expect_equal(out[[1]]$doi, "10.1/a")
})
