# Finish the weekly review ---------------------------------------------------
#
# Run in the RStudio Console after filling in the review sheets:
#
#   source("scripts/finish_review.R")
#
# 1. Applies review_papers.csv and review_pending.csv to the catalog.
# 2. Shows the approved / excluded / pending counts before and after.
# 3. Commits the catalog files and pushes them to GitHub.
# 4. Opens the pull request page. Merging it there publishes the decisions.

invisible(lapply(list.files("R", full.names = TRUE), source))
source("scripts/review_git.R")
check_project_root()

if (current_branch() != review_branch) {
  stop("You are on '", current_branch(), "', not '", review_branch, "'.\n",
       "Run source(\"scripts/start_review.R\") first.", call. = FALSE)
}

# 1. Apply decisions ----------------------------------------------------------

#' Stop if a sheet has decisions but none of its ids are in the catalog
#' (for example, a sheet exported from a different week).
check_sheet_matches <- function(path, catalog) {
  dec <- readr::read_csv(path, show_col_types = FALSE,
                         col_types = readr::cols(.default = "c"))
  filled <- dec$id[!is.na(dec$review) & nzchar(trimws(dec$review))]
  if (length(filled) && !any(filled %in% catalog$id)) {
    stop(path, " has decisions, but none of its papers or datasets are on ",
         "this branch. Was it exported in an earlier week?", call. = FALSE)
  }
  length(filled)
}

before <- review_counts()

n_papers <- 0L
if (file.exists(review_csvs[["papers"]])) {
  n_papers <- check_sheet_matches(review_csvs[["papers"]],
                                  read_papers("catalog/papers.yaml"))
  if (n_papers > 0) source("scripts/review_papers_import.R")
}

n_datasets <- 0L
if (file.exists(review_csvs[["datasets"]])) {
  n_datasets <- check_sheet_matches(review_csvs[["datasets"]],
                                    read_curated("catalog/datasets.yaml"))
  if (n_datasets > 0) source("scripts/review_import.R")
}

after <- review_counts()
message("\nBefore:")
print(before)
message("After:")
print(after)

# 2. Commit and push ----------------------------------------------------------

changed <- uncommitted_files(catalog_files)
if (!length(changed)) {
  stop("No decisions to send: the sheets are empty or match the catalog already.",
       call. = FALSE)
}

papers_after <- after[after$file == "papers", ]
msg <- sprintf("Review: %d paper and %d dataset decisions (%d papers still pending)",
               n_papers, n_datasets, papers_after$pending)
git_run("add", "--", changed)
git_run("commit", "-m", msg)
message("Committed: ", msg)

message("Pushing to GitHub...")
pushed <- tryCatch({
  git_run("push", "origin", review_branch)
  TRUE
}, error = function(e) {
  message(conditionMessage(e))
  FALSE
})

if (!pushed) {
  stop("The commit is saved on this computer but did not reach GitHub. ",
       "Click Push (green arrow) in the Git tab, then open:\n",
       pull_request_url(), call. = FALSE)
}

# 3. Pull request ---------------------------------------------------------------

message("\nDone. Last step, on GitHub: open the pull request and click ",
        "'Merge pull request'.\n", pull_request_url())
if (interactive()) utils::browseURL(pull_request_url())
