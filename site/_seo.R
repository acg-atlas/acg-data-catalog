# Post-render SEO (run by Quarto after every full render, from site/):
#   - sitemap.xml: clean URLs (Cloudflare Pages serves /papers, not
#     /papers.html) and Spanish alternates
#   - robots.txt pointing at the sitemap
#   - schema.org JSON-LD: WebSite on the home pages, and a DataCatalog of
#     every approved dataset on the "All data" pages, for Google Dataset Search,
#     and a FAQPage on the FAQ pages
#   - llms.txt, a plain-text site guide for AI assistants
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
                inLanguage = c("es", "en"),
                creator = list(`@type` = "Person", name = "Catherine Hulshof"))
inject("_site/index.html", website)
inject("_site/en/index.html", website)

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
  catalog$url <- paste0(base, "en/browse")
  inject("_site/en/browse.html", catalog)
}

# FAQPage on the FAQ pages: built from the rendered page itself, so the
# structured data always matches the visible questions and answers.
strip_html <- function(s) {
  s <- gsub("<[^>]+>", " ", s)
  for (e in list(c("&amp;", "&"), c("&lt;", "<"), c("&gt;", ">"), c("&quot;", '"'), c("&#39;", "'")))
    s <- gsub(e[1], e[2], s, fixed = TRUE)
  trimws(gsub("\\s+", " ", s))
}
faq_ld <- function(file, lang) {
  if (!file.exists(file)) return(invisible())
  html <- paste(readLines(file, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  m <- regmatches(html, gregexpr("(?s)<h2[^>]*>(.*?)</h2>(.*?)</section>", html, perl = TRUE))[[1]]
  qa <- lapply(m, function(s) {
    q <- strip_html(sub("(?s)^<h2[^>]*>(.*?)</h2>.*$", "\\1", s, perl = TRUE))
    a <- strip_html(sub("(?s)^<h2[^>]*>.*?</h2>(.*)</section>$", "\\1", s, perl = TRUE))
    list(`@type` = "Question", name = q,
         acceptedAnswer = list(`@type` = "Answer", text = a))
  })
  inject(file, list(`@context` = "https://schema.org", `@type` = "FAQPage",
                    inLanguage = lang, mainEntity = qa))
}
faq_ld("_site/faq.html", "es")
faq_ld("_site/en/faq.html", "en")

# llms.txt: a plain-text guide to the site for AI assistants (llmstxt.org)
writeLines(c(
  "# ACG Atlas",
  "",
  "> Free, bilingual (English/Spanish) index of research datasets and scientific papers from Área de Conservación Guanacaste (ACG), Costa Rica, a UNESCO World Heritage Site. It links to each dataset or paper in its permanent home; it does not host them. Independent project by Catherine Hulshof (Virginia Commonwealth University); not an official ACG, SINAC or MINAE site.",
  "",
  "Updated weekly from DataCite, GBIF, OpenAlex and Crossref, plus researcher submissions; every entry is reviewed by hand. Metadata is CC0. Cite each dataset or paper by its own DOI.",
  "",
  "## Pages",
  "",
  paste0("- [FAQ](", base, "en/faq): what the Atlas covers, how to search, cite and contribute"),
  paste0("- [About](", base, "en/about): why the Atlas exists and how entries are found and reviewed"),
  paste0("- [Search data](", base, "en/explore): datasets filtered by theme, taxon, ACG sector, repository and year"),
  paste0("- [Search papers](", base, "en/papers): papers about research done in ACG"),
  paste0("- [Findings](", base, "en/findings): what research in ACG covers, and where the gaps are"),
  paste0("- [Contribute](", base, "en/contribute): submit a dataset or suggest a paper by DOI"),
  paste0("- [Spanish (default)](", base, "): the site's main language; English pages are under /en/"),
  "",
  "## Data",
  "",
  paste0("- [catalog.json](", base, "data/catalog.json): all approved datasets"),
  paste0("- [papers.json](", base, "data/papers.json): all included papers"),
  "- [Source code and curation decisions](https://github.com/acg-atlas/acg-data-catalog)"
), "_site/llms.txt", useBytes = TRUE)
