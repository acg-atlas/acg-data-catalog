# ACG boundary ---------------------------------------------------------------
#
# data-raw/acg_boundary.geojson is the SIG-ACG outline (credit: Waldy
# Medina/SIG-ACG, CC BY 4.0) plus RNVS Bahia Junquillal; rebuild it with
# data-raw/make_boundary.R. Every function reads the boundary from here.

read_boundary <- function(path) {
  b <- sf::st_read(path, quiet = TRUE)
  b <- sf::st_transform(b, 4326)
  sf::st_union(sf::st_make_valid(b))
}

#' WKT for the GBIF API: simplified, counter-clockwise outer ring.
boundary_wkt <- function(boundary, tolerance_m = 500) {
  b <- sf::st_transform(boundary, 5367) |>          # CRTM05, metres
    sf::st_simplify(dTolerance = tolerance_m) |>
    sf::st_convex_hull() |>                          # GBIF wants a simple polygon
    sf::st_transform(4326)
  xy <- sf::st_coordinates(b)[, c("X", "Y")]
  # Shoelace sign: negative area = clockwise -> reverse for GBIF
  area2 <- sum(xy[-nrow(xy), 1] * xy[-1, 2] - xy[-1, 1] * xy[-nrow(xy), 2])
  if (area2 < 0) xy <- xy[rev(seq_len(nrow(xy))), ]
  pts <- paste(sprintf("%.5f %.5f", xy[, 1], xy[, 2]), collapse = ",")
  sprintf("POLYGON((%s))", pts)
}

#' TRUE if any point/box in a DataCite geoLocations list falls in the boundary.
geolocations_inside <- function(geolocs, boundary) {
  if (length(geolocs) == 0) return(FALSE)
  pts <- purrr::map(geolocs, function(g) {
    if (!is.null(g$geoLocationPoint)) {
      p <- g$geoLocationPoint
      return(c(as.numeric(p$pointLongitude), as.numeric(p$pointLatitude)))
    }
    if (!is.null(g$geoLocationBox)) {
      bx <- g$geoLocationBox
      return(c(mean(as.numeric(c(bx$westBoundLongitude, bx$eastBoundLongitude))),
               mean(as.numeric(c(bx$southBoundLatitude, bx$northBoundLatitude)))))
    }
    NULL
  }) |> purrr::compact()
  pts <- purrr::keep(pts, ~ length(.x) == 2 && all(is.finite(.x)))
  if (length(pts) == 0) return(FALSE)
  m <- do.call(rbind, pts)
  sfc <- sf::st_sfc(lapply(seq_len(nrow(m)), function(i) sf::st_point(m[i, ])),
                    crs = 4326)
  any(lengths(sf::st_intersects(sfc, boundary)) > 0)
}
