# Build data-raw/acg_boundary.geojson from the SIG-ACG shapefiles (CRTM05).
# The shapefiles are not in the repo. Run from the project root:
#   Rscript data-raw/make_boundary.R path/to/ACGborder.shp
# ACGborder.shp is the dissolved ACG outline; it omits RNVS Bahia Junquillal
# (V25), which ACGborder2.shp (same folder) holds as boundary lines.

args <- commandArgs(trailingOnly = TRUE)
src <- if (length(args)) args[1] else "ACGborder.shp"
out <- "data-raw/acg_boundary.geojson"

b <- sf::st_read(src, quiet = TRUE)
l2 <- sf::st_read(file.path(dirname(src), "ACGborder2.shp"), quiet = TRUE)
junq <- l2[l2$codigo_2 %in% "V25" | l2$CODIGO %in% "V25", ] |>
  sf::st_union() |> sf::st_polygonize() |> sf::st_collection_extract("POLYGON") |>
  sf::st_union()

u <- sf::st_union(sf::st_union(sf::st_make_valid(b)), junq)  # repair in metres
u <- sf::st_buffer(sf::st_simplify(u, dTolerance = 5), 0)     # drop sub-5 m self-crossings
u <- sf::st_make_valid(sf::st_transform(u, 4326))
stopifnot(all(s2::s2_is_valid(sf::st_as_s2(u))))

f <- sf::st_sf(name = "Area de Conservacion Guanacaste",
               source = "SIG-ACG (Waldy Medina), CC BY 4.0; dissolved outline plus RNVS Bahia Junquillal, simplified 5 m",
               geometry = u)
if (file.exists(out)) file.remove(out)
sf::st_write(f, out, driver = "GeoJSON", quiet = TRUE,
             layer_options = c("COORDINATE_PRECISION=6", "RFC7946=YES"))
message("Wrote ", out, ": ", round(as.numeric(sf::st_area(u)) / 1e6), " km2")
