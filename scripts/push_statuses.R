# After a merge to main: tell the Worker which submissions were decided,
# so submitters' DOIs (datasets and papers) show as approved/excluded rather
# than pending.
invisible(lapply(list.files("R", full.names = TRUE), source))
n <- push_statuses(read_curated("catalog/datasets.yaml"), read_papers("catalog/papers.yaml"))
message("Pushed ", n %||% 0, " status update(s) to the Worker")
