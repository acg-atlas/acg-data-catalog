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

test_that("boundary_wkt follows the outline and fits in a GBIF URL", {
  wkt <- boundary_wkt(boundary)
  expect_match(wkt, "^(MULTI)?POLYGON\\(\\(")
  expect_lte(nchar(wkt), 3000)
  g <- sf::st_as_sfc(wkt, crs = 4326)
  expect_true(all(sf::st_is_valid(g)))
  # Close to the real area, i.e. not a convex hull
  ratio <- as.numeric(sf::st_area(sf::st_union(g))) / as.numeric(sf::st_area(boundary))
  expect_gt(ratio, 0.95)
  expect_lt(ratio, 1.05)
})

test_that("polygons_wkt orients outer rings counter-clockwise", {
  sq <- sf::st_sfc(sf::st_polygon(list(rbind(c(0, 0), c(0, 1), c(1, 1), c(1, 0), c(0, 0)))))
  expect_equal(polygons_wkt(sq),
               "POLYGON((0.0000 0.0000,1.0000 0.0000,1.0000 1.0000,0.0000 1.0000,0.0000 0.0000))")
})
