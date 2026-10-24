# Append newly harvested candidates to catalog/datasets.yaml and new papers to
# catalog/papers.yaml as `pending`. Run after targets::tar_make(); the GitHub
# Action then opens a PR if either file changed.
library(targets)
invisible(lapply(list.files("R", full.names = TRUE), source))

queue   <- tar_read(queue)
curated <- tar_read(curated)
append_pending("catalog/datasets.yaml", curated, queue)
message(nrow(queue), " new pending dataset entr", ifelse(nrow(queue) == 1, "y", "ies"))

papers <- tar_read(papers_queue)
append_pending_papers("catalog/papers.yaml", tar_read(papers_curated), papers)
message(nrow(papers), " new pending paper", ifelse(nrow(papers) == 1, "", "s"))
