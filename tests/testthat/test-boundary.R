test_that("geolocations inside/outside the boundary", {
  inside  <- list(list(geoLocationPoint = list(pointLongitude = "-85.6",
                                               pointLatitude = "10.85")))
  outside <- list(list(geoLocationPoint = list(pointLongitude = "-84.0",
                                               pointLatitude = "9.9")))
  box     <- list(list(geoLocationBox = list(westBoundLongitude = -85.7,
    eastBoundLongitude = -85.5, southBoundLatitude = 10.8, northBoundLatitude = 10.9)))
  expect_true(geolocations_inside(inside, boundary))
  expect_false(geolocations_inside(outside, boundary))
  expect_true(geolocations_inside(box, boundary))
  expect_false(geolocations_inside(list(), boundary))
})

test_that("boundary_wkt is a closed counter-clockwise polygon", {
  wkt <- boundary_wkt(boundary)
  expect_match(wkt, "^POLYGON\\(\\(")
  g <- sf::st_as_sfc(wkt, crs = 4326)
  expect_true(sf::st_is_valid(g))
})
