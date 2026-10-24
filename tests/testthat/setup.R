root <- normalizePath(file.path("..", ".."))
invisible(lapply(list.files(file.path(root, "R"), full.names = TRUE), source))
boundary  <- read_boundary(file.path(root, "data-raw", "acg_boundary.geojson"))
gazetteer <- read_gazetteer(file.path(root, "data-raw", "gazetteer.csv"))
