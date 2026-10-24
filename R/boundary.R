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

#' WKT for the GBIF API: the outline itself, simplified only as much as needed.
#'
#' GBIF takes the geometry in the URL and rejects requests whose WKT is much
#' over ~3,000 characters (HTTP 400), so try increasing tolerances and use the
#' first that fits. Outer rings are counter-clockwise and holes clockwise, as
#' GBIF requires; parts under 0.1 km2 are dropped. Falls back to the convex
#' hull if no tolerance fits.
boundary_wkt <- function(boundary, tolerances_m = c(250, 500, 750, 1000, 1500, 2000),
                         max_chars = 3000) {
  b <- sf::st_transform(boundary, 5367)              # CRTM05, metres
  for (tol in tolerances_m) {
    polys <- sf::st_simplify(b, dTolerance = tol) |>
      sf::st_transform(4326) |>
      sf::st_make_valid() |>
      sf::st_cast("POLYGON")
    polys <- polys[as.numeric(sf::st_area(polys)) > 1e5]
    wkt <- polygons_wkt(polys)
    if (nchar(wkt) <= max_chars) return(wkt)
  }
  polygons_wkt(sf::st_transform(sf::st_convex_hull(b), 4326))
}

polygons_wkt <- function(polys) {
  parts <- vapply(seq_along(polys), function(i) {
    rings <- unclass(polys[[i]])
    txt <- vapply(seq_along(rings), function(r) {
      xy <- ring_orient(rings[[r]][, 1:2], ccw = r == 1)
      paste0("(", paste(sprintf("%.4f %.4f", xy[, 1], xy[, 2]), collapse = ","), ")")
    }, "")
    paste0("(", paste(txt, collapse = ","), ")")
  }, "")
  if (length(parts) == 1) return(paste0("POLYGON", parts))
  paste0("MULTIPOLYGON(", paste(parts, collapse = ","), ")")
}

# Shoelace sign: positive area = counter-clockwise
ring_orient <- function(xy, ccw = TRUE) {
  area2 <- sum(xy[-nrow(xy), 1] * xy[-1, 2] - xy[-1, 1] * xy[-nrow(xy), 2])
  if ((area2 > 0) != ccw) xy <- xy[rev(seq_len(nrow(xy))), ]
  xy
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
