# Post-render SEO (run by Quarto after every full render, from site/):
#   - sitemap.xml: clean URLs (Cloudflare Pages serves /papers, not
#     /papers.html) and Spanish alternates
#   - robots.txt pointing at the sitemap
#   - schema.org JSON-LD: WebSite on the home pages, and a DataCatalog of
#     every approved dataset on the "All data" pages, for Google Dataset Search
base <- "https://acg-atlas.pages.dev/"
`%||%` <- function(a, b) if (is.null(a)) b else a

# sitemap -----------------------------------------------------------------------
sm <- "_site/sitemap.xml"
if (file.exists(sm)) {
  x <- readLines(sm, encoding = "UTF-8", warn = FALSE)
  x <- gsub("index\\.html</loc>", "</loc>", x)
  x <- gsub("\\.html</loc>", "</loc>", x)
  writeLines(x, sm, useBytes = TRUE)
}
writeLines(c("User-agent: *", "Allow: /", "", paste0("Sitemap: ", base, "sitemap.xml")),
           "_site/robots.txt")

# JSON-LD -------------------------------------------------------------------------
inject <- function(file, obj) {
  if (!file.exists(file)) return(invisible())
  html <- paste(readLines(file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  if (grepl("application/ld+json", html, fixed = TRUE)) return(invisible())  # partial re-render
  json <- jsonlite::toJSON(obj, auto_unbox = TRUE, null = "null")
  json <- gsub("</", "<\\\\/", json, fixed = TRUE)     # keep "</script>" out of titles
  tag <- paste0('<script type="application/ld+json">', json, "</script>\n</head>")
  writeLines(sub("</head>", tag, html, fixed = TRUE), file, useBytes = TRUE)
}

website <- list(`@context` = "https://schema.org", `@type` = "WebSite",
                name = "ACG Atlas", url = base,
                description = "Research data and publications from Área de Conservación Guanacaste, Costa Rica.",
                inLanguage = c("en", "es"),
                creator = list(`@type` = "Person", name = "Catherine Hulshof"))
inject("_site/index.html", website)
inject("_site/es/index.html", website)

cat_file <- "_site/data/catalog.json"
if (file.exists(cat_file)) {
  ds <- jsonlite::read_json(cat_file)
  as_dataset <- function(d) {
    out <- list(`@type` = "Dataset", name = d$title,
                url = if (!is.null(d$doi)) paste0("https://doi.org/", d$doi) else d$url,
                identifier = if (!is.null(d$doi)) paste0("https://doi.org/", d$doi) else NULL,
                creator = lapply(strsplit(d$creators %||% "", ";\\s*")[[1]],
                                 function(n) list(`@type` = "Person", name = n)),
                datePublished = if (!is.null(d$year)) as.character(d$year) else NULL,
                publisher = if (!is.null(d$publisher)) list(`@type` = "Organization", name = d$publisher) else NULL,
                license = d$license,
                keywords = unlist(strsplit(paste(d$taxa %||% "", d$themes %||% "", sep = ";"), ";\\s*")),
                spatialCoverage = "Área de Conservación Guanacaste, Costa Rica",
                isAccessibleForFree = TRUE)
    out$description <- paste0(d$title, ". Dataset from Área de Conservación Guanacaste, Costa Rica",
                              if (!is.null(d$publisher)) paste0(", published by ", d$publisher) else "", ".")
    out$keywords <- out$keywords[nzchar(out$keywords)]
    Filter(Negate(is.null), out)
  }
  catalog <- list(`@context` = "https://schema.org", `@type` = "DataCatalog",
                  name = "ACG Atlas: research data",
                  description = "Index of public research datasets from Área de Conservación Guanacaste, Costa Rica.",
                  url = paste0(base, "browse"),
                  dataset = lapply(ds, as_dataset))
  inject("_site/browse.html", catalog)
  catalog$url <- paste0(base, "es/browse")
  inject("_site/es/browse.html", catalog)
}
