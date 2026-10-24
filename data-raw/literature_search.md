# Literature search protocol

How the publications layer is assembled. Record each run in the log below so
the counts can be reported PRISMA-style in the catalog's data paper.

## Sources

| Source | Role | Published on the site? |
|---|---|---|
| Web of Science Core Collection (VCU licence) | discovery and completeness check | No. Exports stay private, outside this repo; only DOIs are used for matching. |
| OpenAlex | discovery and the published record (CC0) | Yes |
| Crossref | fallback metadata for DOIs missing from OpenAlex | Yes (bibliographic facts only) |

Abstracts are not republished; each record links to the publisher and OpenAlex.

## Web of Science query

Run in **Web of Science Core Collection → Advanced search**, all years:

```
TS=("Area de Conservacion Guanacaste" OR "Guanacaste Conservation Area"
 OR "ACG Costa Rica" OR ("ACG" AND "Costa Rica" AND Guanacaste)
 OR "Santa Rosa National Park" OR "Parque Nacional Santa Rosa"
 OR ("Santa Rosa" AND "Costa Rica")
 OR "Guanacaste National Park" OR "Parque Nacional Guanacaste"
 OR "Rincon de la Vieja" OR "Pitilla" OR "Maritza Biological Station"
 OR "Estacion Biologica Maritza" OR "Volcan Cacao" OR "Cacao Volcano"
 OR "Volcan Orosi" OR "Orosi Volcano" OR "Islas Murcielago"
 OR "Murcielago Islands" OR "Bahia Junquillal" OR "Horizontes Experimental Forest"
 OR "Estacion Experimental Forestal Horizontes" OR "Pocosol" OR "San Gerardo"
 AND "Costa Rica")
```

Web of Science ignores accents, so unaccented forms also match "Área" and
"Rincón". `TS=` searches title, abstract, author keywords and Keywords Plus.
Generic place names ("Santa Rosa", "Pocosol", "San Gerardo") are tied to
"Costa Rica" to avoid California, Mexico and elsewhere.

## Export (private)

1. Results page → **Export → Tab delimited file**.
2. Records: 1–1000 (Web of Science allows 1,000 per export; repeat for 1001–2000, and so on).
3. Record content: **Full Record** (cited references not needed).
4. Save the files to `C:\Users\cathe\Documents\acg-private\wos\` (outside the repo), named `wos_YYYY-MM-DD_001.txt`, `_002.txt`, …

## Run log

OpenAlex queries are built by `literature_query()` in `R/papers.R` from
`data-raw/gazetteer.csv`: strong ACG names, OR distinctive sector names AND
"Costa Rica", in titles and abstracts ("core"); strong names only anywhere in
the full text ("fulltext"). Ambiguous sector names (`ambiguous_terms`) are
used for tagging only. Datasets, errata, paratext and peer reviews are dropped.

| Date | Source | Query version | Records | Notes |
|---|---|---|---|---|
| 2026-10-24 | Web of Science Core Collection | v1 (above) | 551 | 452 with DOI. 442 DOIs found in OpenAlex, 4 in Crossref only, 10 in neither. Of 99 without DOI, 36 matched to OpenAlex by title. 69 + 10 = 79 not published. |
| 2026-10-24 | OpenAlex, title + abstract ("core") | v1 | 882 | after dropping non-paper types |
| 2026-10-24 | OpenAlex, full text, strong names ("fulltext") | v1 | 2,465 | |
| 2026-10-24 | Combined, deduplicated (DOI, else OpenAlex id) | | 2,673 | After dropping 99 Zenodo/Plazi fragments (single figures or species descriptions of papers already listed). 1,032 likely (WoS, core or strong ACG name), 1,641 check (full text only). OpenAlex core found 265 of 473 WoS DOIs. |
| 2026-10-24 | Title and abstract screening | | 917 approved | Rule: research done in the ACG (any sector, including marine), using ACG specimens or data, or mainly about the ACG. Claude screened all 2,673; the 220 unsure records were decided by C. Hulshof (219 approved, 1 excluded). 15 same-record duplicates (repository copies, preprints) excluded. 1,756 excluded in total. |
