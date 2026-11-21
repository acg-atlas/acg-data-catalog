# Start the weekly review ----------------------------------------------------
#
# Run in the RStudio Console, from the acg-data-catalog project:
#
#   source("scripts/start_review.R")
#
# 1. Downloads GitHub's current "Catalog review queue" branch (harvest/weekly)
#    and switches to it. The robot rebuilds that branch every week, so any old
#    copy on this computer is replaced (after checking nothing would be lost).
# 2. Writes the pending papers to review_papers.csv and pending datasets to
#    review_pending.csv, and opens them in Excel.
#
# Fill the `review` column with approved or excluded (blank = still pending),
# save as "CSV UTF-8", then run source("scripts/finish_review.R").

invisible(lapply(list.files("R", full.names = TRUE), source))
source("scripts/review_git.R")
check_project_root()
ignore_review_sheets()

# 1. Get the review branch ----------------------------------------------------

dirty <- uncommitted_files(catalog_files)
if (length(dirty)) {
  stop("These catalog files have changes that are not committed:\n  ",
       paste(dirty, collapse = "\n  "),
       "\nIf they are decisions you still want, run ",
       "source(\"scripts/finish_review.R\") first.", call. = FALSE)
}

message("Getting the latest review branch from GitHub...")
git_run("fetch", "--prune", "origin")
if (!remote_branch_exists()) {
  stop("There is no review branch on GitHub right now: nothing to review.",
       call. = FALSE)
}

lost <- unpushed_commits()
if (length(lost)) {
  stop("The local ", review_branch, " branch has commits that are not on GitHub:\n  ",
       paste(lost, collapse = "\n  "),
       "\nPush them (or ask for help) before starting a new review.", call. = FALSE)
}

# Make the local branch an exact copy of GitHub's
git_run("checkout", "-B", review_branch, paste0("origin/", review_branch))
message("On branch ", current_branch(), ", matching GitHub.")

# 2. Export the review sheets -------------------------------------------------

# Never overwrite a sheet that already has decisions in it
for (path in review_csvs) {
  if (filled_decisions(path) > 0) {
    backup <- sub("\\.csv$", format(Sys.time(), "_%Y%m%d-%H%M.csv"), path)
    file.rename(path, backup)
    message("Kept your earlier sheet as ", backup)
  }
}

source("scripts/review_papers_export.R")
source("scripts/review_export.R")

print(review_counts())

for (path in review_csvs) {
  n <- nrow(readr::read_csv(path, show_col_types = FALSE,
                            col_types = readr::cols(.default = "c")))
  if (n > 0) open_file(path)
}

message("\nNext: fill the `review` column (approved / excluded), save as ",
        "CSV UTF-8, then run source(\"scripts/finish_review.R\").")
