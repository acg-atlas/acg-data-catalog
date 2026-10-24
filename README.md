# ACG Data Catalog

A searchable, bilingual (EN/ES) index of publicly available research data from the Área de Conservación Guanacaste, Costa Rica. The catalog **does not host data**: every entry points to a dataset in a permanent repository with its own DOI, license, and citation.

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
 OpenAlex ─► site/data/literature.json
```

- **`catalog/datasets.yaml`** is the only file humans edit. Each entry has `review: pending | approved | excluded`. Only `approved` entries are published. `excluded` entries are never re-queued.
- **The pipeline never overwrites an entry.** It only appends new pending ones, so your edits to titles, sectors, themes, and notes are safe.
- **Merging a pull request is the review.** Pending entries can stay pending across PRs.

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

## One-time setup

1. **GitHub.** Create the `acg-atlas` organization and push this repo. Put your username in `.github/CODEOWNERS` and protect `main` (require a PR and code-owner review).
2. **Cloudflare D1 and Worker** (from `worker/`):
   ```sh
   npm install
   npx wrangler d1 create acg-submissions        # paste the id into wrangler.toml
   npx wrangler d1 execute acg-submissions --remote --file=schema.sql
   npx wrangler secret put ADMIN_TOKEN           # long random string
   npx wrangler secret put TURNSTILE_SECRET      # from Cloudflare Turnstile
   npx wrangler deploy
   ```
   Then put the Worker URL and the Turnstile **site** key in `site/_submit.qmd`.
3. **Cloudflare Pages.** Create a Pages project named `acg-atlas`.
4. **GitHub secrets:** `WORKER_URL`, `WORKER_ADMIN_TOKEN` (the same value as `ADMIN_TOKEN`), `OPENALEX_API_KEY` (free at openalex.org), `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

## Privacy

Submitter emails stay in D1. The admin endpoint never returns them, because its output lands in a public pull request. To read the emails:

```sh
npx wrangler d1 execute acg-submissions --remote \
  --command "SELECT doi, contact FROM submissions"
```

## Boundary

`data-raw/acg_boundary.geojson` is an **interim bounding box**. Replace it with the official SIG-ACG `Areas-protegidas` layer (credit: Waldy Medina/SIG-ACG, CC BY 4.0). No code changes are needed. Because the box is larger than the ACG, GBIF counts are inflated until then.

## Licenses

Code: MIT. Catalog metadata: CC0. Each dataset keeps its own license.
