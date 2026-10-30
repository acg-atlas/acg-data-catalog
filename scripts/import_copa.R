# Fold COPA (ACG's repository, "Ciencia e Investigación") into catalog/papers.yaml.
#
#   Rscript scripts/import_copa.R "C:/path/to/Ciencia e Investigación.csv"   # first import, from COPA's CSV export
#   Rscript scripts/import_copa.R                                           # weekly, from COPA's OAI feed
#
# The CSV export stays outside this repo (it includes COPA's private
# collection). COPA items are approved directly; spot-check them in the PR.
# Writes copa_summary.md (counts, and excluded entries that COPA lists, for a
# second look); the weekly workflow adds it to the review PR.

invisible(lapply(list.files("R", full.names = TRUE), source))
args <- commandArgs(trailingOnly = TRUE)

items <- if (length(args)) read_copa_csv(args[1]) else tryCatch(harvest_copa_oai(), error = function(e) e)
if (inherits(items, "error")) {   # COPA is sometimes down: skip it this week, don't fail the run
  msg <- paste("COPA's OAI feed could not be reached:", conditionMessage(items))
  message(msg)
  writeLines(c("### COPA", "", paste0(msg, ". Skipped this week.")), "copa_summary.md")
  quit(save = "no")
}

merged <- merge_copa(
  read_papers("catalog/papers.yaml"), items,
  gazetteer = read_gazetteer("data-raw/gazetteer.csv"),
  taxon_rules = read_tag_rules("data-raw/taxon_terms.csv"),
  theme_rules = read_tag_rules("data-raw/theme_terms.csv"))
write_papers(merged, "catalog/papers.yaml")

info <- attr(merged, "copa")
counts <- info$counts
cat(sprintf("  %-28s %s\n", names(counts), counts), sep = "")
recheck <- if (nrow(info$recheck)) c("", "Excluded in the Atlas but listed in COPA (worth a second look):", "",
  sprintf("- [%s](%s) (%s) · `%s`", info$recheck$title, info$recheck$copa,
          info$recheck$year, info$recheck$id)) else character()
writeLines(c("### COPA", "",
             sprintf("- New from COPA (approved): %d with a DOI, %d without",
                     counts[["new_with_doi"]], counts[["new_without_doi"]]),
             sprintf("- Already in the Atlas: %d (COPA links added: %d; pending entries approved: %d)",
                     counts[["already_in_atlas"]], counts[["copa_links_added"]], counts[["pending_approved"]]),
             recheck), "copa_summary.md")
