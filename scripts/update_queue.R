# Append newly harvested candidates to catalog/datasets.yaml as `pending`.
# Run after targets::tar_make(); the GitHub Action then opens a PR if the
# file changed.
library(targets)
invisible(lapply(list.files("R", full.names = TRUE), source))

queue   <- tar_read(queue)
curated <- tar_read(curated)
append_pending("catalog/datasets.yaml", curated, queue)
message(nrow(queue), " new pending entr", ifelse(nrow(queue) == 1, "y", "ies"))
