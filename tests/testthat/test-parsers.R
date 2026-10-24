test_that("DataCite record parses", {
  rec <- list(id = "10.5061/DRYAD.1", attributes = list(
    titles = list(list(title = "Plant traits")),
    creators = list(list(name = "Hulshof, C"), list(name = "Doe, J")),
    publicationYear = 2024, publisher = "Dryad", url = "https://datadryad.org/x",
    rightsList = list(list(rightsUri = "https://creativecommons.org/publicdomain/zero/1.0/")),
    types = list(resourceTypeGeneral = "Dataset"),
    descriptions = list(list(description = "Santa Rosa, Guanacaste")),
    subjects = list(list(subject = "tropical dry forest")),
    geoLocations = list(list(geoLocationPoint = list(pointLongitude = -85.6,
                                                     pointLatitude = 10.85)))
  ))
  x <- parse_datacite_record(rec, boundary)
  expect_equal(x$doi, "10.5061/dryad.1")
  expect_equal(x$creators, "Hulshof, C; Doe, J")
  expect_true(x$geo_inside)
  expect_match(x$text, "tropical dry forest")
})

test_that("OpenAlex abstract is rebuilt in order", {
  inv <- list(forests = list(1L), Dry = list(0L), burn = list(2L))
  expect_equal(rebuild_abstract(inv), "Dry forests burn")
  expect_true(is.na(rebuild_abstract(NULL)))
})
