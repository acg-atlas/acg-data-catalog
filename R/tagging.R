# Taxon and theme tags --------------------------------------------------------
#
# Rules live in data-raw/taxon_terms.csv and data-raw/theme_terms.csv (one
# regular expression per tag, matched case-insensitively on accent-folded
# text). Suggestions only fill empty fields; tags already in papers.yaml are
# never overwritten, so hand corrections stick.

themes_vocab <- c("Taxonomy & systematics", "Evolution & genetics",
                  "Natural history & behavior", "Species interactions",
                  "Populations & communities", "Ecosystem processes",
                  "Succession & restoration", "Climate & environmental change",
                  "Conservation, management & people", "Geology & volcanology")

read_tag_rules <- function(path) {
  readr::read_csv(path, col_types = readr::cols(.default = "c"), show_col_types = FALSE) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ dplyr::coalesce(.x, "")))
}

fold_text <- function(x) {
  tolower(stringi::stri_trans_general(dplyr::coalesce(x, ""), "Latin-ASCII"))
}

# Place names that contain theme words ("Area de Conservacion", "National
# Park") would tag every paper with conservation; remove them first.
strip_place_names <- function(x) {
  gsub("area de conservacion guanacaste|guanacaste conservation area|conservation area|parque nacional|national park|area silvestre protegida|refugio nacional|wildlife refuge",
       " ", x)
}

#' Taxa found in each text. A parent (Insecta, Arthropoda) is dropped when one
#' of its children matched.
tag_taxa <- function(text, rules) {
  text <- fold_text(text)
  hits <- vapply(rules$pattern, function(p) grepl(p, text, perl = TRUE),
                 logical(length(text)))
  hits <- matrix(hits, nrow = length(text))
  purrr::map_chr(seq_along(text), function(i) {
    found <- rules$taxon[hits[i, ]]
    children_of <- function(t) rules$taxon[rules$parent == t]
    drop <- found[vapply(found, function(t) {
      kids <- children_of(t)
      any(kids %in% found) || any(unlist(lapply(kids, children_of)) %in% found)
    }, logical(1))]
    paste(setdiff(found, drop), collapse = "; ")
  })
}

#' Up to `max` themes per text, ranked by matches (title matches count triple).
#' A theme needs a title match or at least `min_score` abstract matches; if
#' none qualifies, the single best theme is kept.
tag_themes <- function(title, body, rules, max = 3, min_score = 2) {
  title <- rep_len(strip_place_names(fold_text(title)), length(body))
  body <- strip_place_names(fold_text(body))
  count <- function(p, x) lengths(regmatches(x, gregexpr(p, x, perl = TRUE)))
  score <- vapply(rules$pattern, function(p) 3 * count(p, title) + count(p, body),
                  numeric(length(title)))
  score <- matrix(score, nrow = length(title))
  purrr::map_chr(seq_along(title), function(i) {
    s <- score[i, ]
    n <- sum(s >= min_score)
    if (n == 0) n <- min(1, sum(s > 0))
    keep <- order(-s)[seq_len(min(max, n))]
    paste(rules$theme[sort(keep)], collapse = "; ")
  })
}

#' Fill empty taxa/themes. `texts` has openalex_id, abstract and topics (from
#' OpenAlex); it is used for matching only and never stored. Taxa come from the
#' title when it names any (abstracts mention fruit, trees or predators in
#' passing), else from the abstract. OpenAlex topic names ("Lepidoptera:
#' Biology and Taxonomy") are generic, so they are used only as a last resort.
tag_papers <- function(papers, texts, taxon_rules, theme_rules) {
  for (f in c("taxa", "themes")) if (!f %in% names(papers)) papers[[f]] <- NA_character_
  t <- dplyr::left_join(dplyr::select(papers, openalex_id, title),
                        dplyr::distinct(dplyr::select(texts, openalex_id, abstract, topics),
                                        openalex_id, .keep_all = TRUE),
                        by = "openalex_id")
  abstract <- dplyr::coalesce(t$abstract, "")
  topics <- dplyr::coalesce(t$topics, "")
  new_taxa <- tag_taxa(t$title, taxon_rules)
  new_taxa <- ifelse(nzchar(new_taxa), new_taxa, tag_taxa(abstract, taxon_rules))
  new_taxa <- ifelse(nzchar(new_taxa), new_taxa, tag_taxa(topics, taxon_rules))
  new_themes <- tag_themes(t$title, abstract, theme_rules)
  new_themes <- ifelse(nzchar(new_themes), new_themes, tag_themes("", topics, theme_rules, max = 1))
  empty <- function(x) is.na(x) | !nzchar(x)
  papers |>
    dplyr::mutate(taxa = ifelse(empty(taxa) & nzchar(new_taxa), new_taxa, taxa),
                  themes = ifelse(empty(themes) & nzchar(new_themes), new_themes, themes))
}
