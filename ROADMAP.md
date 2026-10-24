# Roadmap

## Phase 1: data catalog (done, October 2026)

- Weekly harvest (DataCite, GBIF by the SIG-ACG boundary, form submissions) into a reviewed queue.
- Bilingual site: Search (text, scientist, taxon, sector, repository, year), All data (table with CSV, BibTeX and RIS export), Map (GBIF density by dataset or taxon), Submit a DOI.

## Phase 2

### 2.1 Publications (literature layer)

Goal: a searchable database of every paper about the ACG, for literature reviews, kept separate from the data catalog but linked to it.

**Separate searches, shared design.** Data and papers get their own pages (Data, Publications) because the questions differ ("is there data on X?" versus "what is known about X?") and mixing them is what made COPA hard to use. They share the same filters (sector, taxon, year, people) and cross-link:

- each dataset shows the papers that cite or describe it;
- each paper shows the datasets it used or produced, and a "has open data" flag.

A combined "search everything" box can come later if users ask for it.

**Sources.**

1. OpenAlex. Open (CC0), so records can be republished.
2. Web of Science (through VCU). Use it for discovery and completeness, not as the published record: Clarivate's terms generally do not allow republishing WoS records or abstracts. Export the WoS result set privately, keep it out of this public repo, match on DOI, and fill the public database from OpenAlex or Crossref. Check VCU Libraries' license terms before building on this.
3. Scopus, Google Scholar or SciELO for Spanish-language and grey literature, if coverage gaps show up. Comparing WoS and OpenAlex coverage is itself a methods result for the data paper.

**Steps.**

1. ~~Fix the search string and document it, PRISMA-style~~ (done: `data-raw/literature_search.md`).
2. ~~Run it in WoS and OpenAlex, deduplicate on DOI, record counts~~ (done: 2,673 candidates).
3. ~~Review queue for papers~~ (done, October 2026: 917 approved under the rule "research done in, or mainly about, the ACG"; 1,756 excluded, including duplicates).
4. ~~Tag: sector (gazetteer), taxon, theme, decade, linked datasets (DataCite `relatedIdentifiers` and Scholix links), open access~~ (done, October 2026: 10 themes and taxa from rules in `data-raw/*_terms.csv`, then every paper checked by hand; links from DataCite, ScholeXplorer and GBIF literature tracking in `catalog/links.csv`). Next: tag datasets with the same 10 themes.
5. ~~Publications page: search, filters, table view with BibTeX and RIS export~~ (done: Search papers and All papers, under a Publications menu; site renamed ACG Atlas; Contribute page with separate dataset and paper forms).
6. Evidence and gap map: taxon x theme x sector, cells coloured by number of papers and number of open datasets.

### 2.2 Map

- Dataset footprints from DataCite `geoLocations` (points and boxes) for non-GBIF datasets.
- Sector layer with dataset and paper counts (needs sector polygons or station points from SIG-ACG).
- Cross-database taxon map: GBIF, iNaturalist and BOLD records for one taxon side by side, clipped to the boundary.
- Paper study sites, from coordinates or gazetteer matches.

### 2.3 Site

- Spanish menu on Spanish pages (`babelquarto`).
- One page per dataset with schema.org `Dataset` markup, so Google Dataset Search indexes the catalog.
- Data paper describing the catalog (Data in Brief or Ecology).

### 2.4 Important findings (after the site is polished)

Goal: short, digestible summaries of what is known from the ACG data and papers, so readers can generate research questions and spot gaps. Possibly an "Important findings" page, and a synthesis paper before the LTER application. Builds on the tagging and the evidence and gap map in 2.1. Where it fits best is to be decided once the Publications page is live.

### Clean-ups

- Duplicate tachinid dataset entries (e.g. Spathidexia, Telothyria).
- Re-check the 20 GBIF datasets with fewer than 10 records inside the real boundary.
- Fill `themes` (empty for all entries) before the gap map.
