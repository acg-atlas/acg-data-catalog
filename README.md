# ACG Atlas

**Live site: <https://acg-atlas.org>** (Spanish by default; English at <https://acg-atlas.org/en/>)

A searchable, bilingual (EN/ES) index of research from Área de Conservación Guanacaste, Costa Rica, in two parts: **data** (publicly available datasets, `catalog/datasets.yaml`) and **publications** (papers about research done in ACG, `catalog/papers.yaml`). The Atlas **does not host anything**: every entry points to a dataset or paper in a permanent home with its own DOI, license, and citation.

## How it works

```
 weekly GitHub Action                         merge to main
 ───────────────────                          ─────────────
 DataCite (keyword) ─┐                        catalog/datasets.yaml
 GBIF (spatial)  ────┼─► dedupe ─► score ─►   (approved only)
 Worker /pending ────┘        │                     │
                              ▼                     ▼
                   PR: new `pending` entries   site/data/catalog.json ─► Quarto ─► Cloudflare Pages
                   in catalog/datasets.yaml                          └─► Worker /status (submissions)
 OpenAlex ─► catalog/papers.yaml (pending) ─► site/data/papers.json (approved)
 Web of Science (local, private) ─► scripts/import_wos.R ─┘
```

- **`catalog/datasets.yaml`** is the only file to edit. Each entry has `review: pending | approved | excluded`. Only `approved` entries are published. `excluded` entries are never re-queued.
- **The pipeline never overwrites entries.** It only appends new pending ones, so edits to titles, sectors, themes, and notes are stable.
- **Merging a pull request is the review.** Pending entries can stay pending across pull requests.

## Reviewing the queue

For a few entries, edit `review:` directly in the PR. For many entries, use a spreadsheet:

```r
source("scripts/review_export.R")   # writes review_pending.csv
# fill the `review` column with approved / excluded in Excel or Sheets
source("scripts/review_import.R")   # applies decisions to datasets.yaml
```

Entries are sorted with likely datasets first and taxonomic treatments (Plazi species descriptions) last. Each entry's `relevance_reason` says why it was flagged.

## Running locally

```r
# install.packages(c("targets", "dplyr", "purrr", "tibble", "httr2", "jsonlite",
#                    "readr", "sf", "stringi", "stringr", "yaml", "testthat", "withr"))
targets::tar_make()                 # harvest + score (about 2 minutes)
source("scripts/update_queue.R")    # append new candidates as pending
testthat::test_dir("tests/testthat")
```

Run `renv::init()` once to create `renv.lock` and commit it, so CI and collaborators use the same package versions.

To preview the site: `quarto preview site`.

## Boundary

`data-raw/acg_boundary.geojson` is the official SIG-ACG outline (credit: Waldy Medina/SIG-ACG, CC BY 4.0), with RNVS Bahía Junquillal added, which the dissolved outline omits. `data-raw/make_boundary.R` rebuilds it from the shapefiles. The GBIF query sends the outline itself, simplified just enough to fit in a GBIF request URL (currently 750 m, within 0.5% of the true area).

## Licenses

Code: MIT. Catalog metadata: CC0. Each dataset keeps its own license.
