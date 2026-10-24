# Add papers found by Web of Science to catalog/papers.yaml (run locally).
#
# The WoS export is licensed to VCU and stays outside this repo. Only its DOIs
# and titles are used, to look papers up in OpenAlex or Crossref; the records
# written here come from those open sources.
#
#   Rscript scripts/import_wos.R C:/Users/cathe/acg-private/wos-export.txt
#
# Prints the counts to copy into the run log in data-raw/literature_search.md.

invisible(lapply(list.files("R", full.names = TRUE), source))
paths <- commandArgs(trailingOnly = TRUE)
if (!length(paths)) stop("Give the path(s) to the Web of Science export file(s).")

gaz <- read_gazetteer("data-raw/gazetteer.csv")
wos <- read_wos(paths)
from_wos <- resolve_wos(wos)
core <- search_openalex_papers(gaz, "core")
full <- search_openalex_papers(gaz, "fulltext")
scored <- combine_papers(from_wos, core, full) |> score_papers(gaz)

curated <- read_papers("catalog/papers.yaml")
new <- new_papers(scored, curated)
append_pending_papers("catalog/papers.yaml", curated, new)

counts <- attr(from_wos, "counts")
cat("\nRun log (", format(Sys.Date()), ")\n", sep = "")
cat(sprintf("  %-26s %s\n", names(counts), counts), sep = "")
cat(sprintf("  %-26s %s\n", c("openalex_core", "openalex_fulltext", "unique_papers",
                               "new_pending", "likely", "check"),
            c(nrow(core), nrow(full), nrow(scored), nrow(new),
              sum(new$relevance == "likely"), sum(new$relevance == "check"))), sep = "")
