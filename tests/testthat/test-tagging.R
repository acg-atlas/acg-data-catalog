taxon_rules <- read_tag_rules(test_path("../../data-raw/taxon_terms.csv"))
theme_rules <- read_tag_rules(test_path("../../data-raw/theme_terms.csv"))

test_that("taxa: specific groups win over parents, and common traps are avoided", {
  expect_equal(tag_taxa("Tachinid flies reared from caterpillars", taxon_rules), "Lepidoptera; Diptera")
  expect_equal(tag_taxa("Insect diversity of a dry forest", taxon_rules), "Insecta")
  expect_equal(tag_taxa("Fruit picking by Geoffroy's spider monkey", taxon_rules), "Mammalia; Plantae")
  expect_equal(tag_taxa("Isotopes of parrotfish and macroalgae", taxon_rules), "")
  expect_equal(tag_taxa("Reef environments of the Islas Murciélago", taxon_rules), "")
  expect_equal(tag_taxa("Armadillo kills a coral snake", taxon_rules), "Mammalia; Reptilia")
})

test_that("themes: place names do not count, and one passing mention is not enough", {
  expect_equal(tag_themes("Ground deformation before phreatic eruptions", "", theme_rules), "Geology & volcanology")
  expect_equal(tag_themes("Infant handling in mantled howler monkeys", "", theme_rules), "")
  expect_false(grepl("Conservation", tag_themes("Bats of the Area de Conservacion Guanacaste",
                                                "Santa Rosa National Park", theme_rules)))
  two <- tag_themes("A new species of wasp", "We describe its behavior. Behavior varies. Host plants differ.", theme_rules)
  expect_match(two, "Taxonomy & systematics")
  expect_match(two, "Natural history & behavior")
})

test_that("tag_papers fills only empty fields", {
  p <- tibble::tibble(openalex_id = c("W1", "W2"), title = c("Moths of Santa Rosa", "Bats"),
                      taxa = c(NA, "Aves"), themes = c(NA, "Evolution & genetics"))
  texts <- tibble::tibble(openalex_id = c("W1", "W2"), abstract = c("Population density.", ""), topics = "")
  out <- tag_papers(p, texts, taxon_rules, theme_rules)
  expect_equal(out$taxa, c("Lepidoptera", "Aves"))
  expect_equal(out$themes[2], "Evolution & genetics")
})

test_that("links attach to papers without dropping hand-entered ones", {
  p <- tibble::tibble(doi = c("10.1/a", "10.1/b"), datasets = c("10.5/x", NA))
  l <- tibble::tibble(paper_doi = c("10.1/a", "10.1/b"), dataset_id = c("10.5/y", "10.5/z"), source = "scholix")
  expect_equal(link_papers(p, l)$datasets, c("10.5/x; 10.5/y", "10.5/z"))
})
