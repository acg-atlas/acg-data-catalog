# Git helpers for the weekly review ------------------------------------------
#
# Used by scripts/start_review.R and scripts/finish_review.R. Not meant to be
# run on its own. Calls the Git that RStudio already uses (no extra packages).

review_branch <- "harvest/weekly"
catalog_files <- c("catalog/papers.yaml", "catalog/datasets.yaml")
review_csvs   <- c(papers = "review_papers.csv", datasets = "review_pending.csv")

#' Path to git: on the PATH, or the usual Git for Windows location.
git_path <- function() {
  found <- Sys.which("git")
  if (nzchar(found)) return(unname(found))
  win <- c("C:/Program Files/Git/cmd/git.exe", "C:/Program Files/Git/bin/git.exe")
  win <- win[file.exists(win)]
  # short 8.3 form avoids the space in "Program Files"
  if (length(win)) return(utils::shortPathName(win[1]))
  stop("Could not find Git. Is Git for Windows installed?", call. = FALSE)
}

#' Run a git command; stop with git's own message if it fails.
git_run <- function(...) {
  args <- c(...)
  # shQuote() keeps arguments with spaces (commit messages) in one piece
  out <- suppressWarnings(system2(git_path(), shQuote(args),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("git ", paste(args, collapse = " "), " failed:\n",
         paste(out, collapse = "\n"), call. = FALSE)
  }
  out
}

check_project_root <- function() {
  if (!file.exists("catalog/papers.yaml") || !dir.exists(".git")) {
    stop("Run this from the acg-data-catalog project ",
         "(File > Open Project > acg-data-catalog.Rproj).", call. = FALSE)
  }
}

current_branch <- function() git_run("rev-parse", "--abbrev-ref", "HEAD")

#' Tell git on this computer to ignore the review sheets, so they never show
#' up in the Git tab (uses .git/info/exclude, which is not committed).
ignore_review_sheets <- function() {
  exclude <- file.path(".git", "info", "exclude")
  lines <- if (file.exists(exclude)) readLines(exclude, warn = FALSE) else character()
  if (!"review_*.csv" %in% lines) {
    dir.create(dirname(exclude), showWarnings = FALSE, recursive = TRUE)
    write(c("# Weekly review sheets (never commit these)", "review_*.csv"),
          exclude, append = TRUE)
  }
}

#' Tracked files with uncommitted changes (untracked and ignored files are fine).
uncommitted_files <- function(paths = character()) {
  out <- git_run("status", "--porcelain", "--untracked-files=no", "--", paths)
  trimws(substring(out, 4))
}

#' Commits on the local review branch that are on no GitHub branch at all.
#' (Old commits that were already pushed and merged do not count.)
unpushed_commits <- function() {
  local <- git_run("branch", "--list", review_branch)
  if (!length(local)) return(character())
  git_run("log", "--oneline", review_branch, "--not", "--remotes=origin")
}

remote_branch_exists <- function() {
  length(git_run("branch", "--remotes", "--list", paste0("origin/", review_branch))) > 0
}

#' review: approved / excluded / pending counts in both catalog files.
review_counts <- function() {
  dplyr::bind_rows(
    count_reviews(read_papers("catalog/papers.yaml"), "papers"),
    count_reviews(read_curated("catalog/datasets.yaml"), "datasets")
  )
}

count_reviews <- function(df, label) {
  tibble::tibble(
    file     = label,
    approved = sum(df$review == "approved"),
    excluded = sum(df$review == "excluded"),
    pending  = sum(df$review == "pending")
  )
}

#' Rows in a review CSV with a decision filled in.
filled_decisions <- function(path) {
  if (!file.exists(path)) return(0L)
  dec <- readr::read_csv(path, show_col_types = FALSE,
                         col_types = readr::cols(.default = "c"))
  if (!"review" %in% names(dec)) return(0L)
  sum(!is.na(dec$review) & nzchar(trimws(dec$review)))
}

#' Open a file in its default program (Excel for .csv on Windows).
open_file <- function(path) {
  if (!interactive()) return(invisible())
  if (.Platform$OS.type == "windows") shell.exec(normalizePath(path))
  else utils::browseURL(normalizePath(path))
}

pull_request_url <- function() {
  paste0("https://github.com/acg-atlas/acg-data-catalog/compare/main...",
         review_branch)
}
