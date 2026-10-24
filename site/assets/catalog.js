// Helpers shared by the data and publication pages: links, splitting fields, exports.

export const link = d => d.doi ? "https://doi.org/" + d.doi : d.url;

export const split = x => (x || "").split(";").map(s => s.trim()).filter(Boolean);

export const fmt = (s, vars) => s.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? "");

// Surname for a "Last, First" or "First Last" creator, used as a search term.
// Trailing initials of a second surname ("German Vargas G.") are skipped.
const isInitial = w => /^[A-ZÁÉÍÓÚÑ]{1,2}\.?$/.test(w);
export const surname = name => {
  if (name.includes(",")) {
    const sur = name.split(",")[0].trim().split(/\s+/);
    while (sur.length > 1 && isInitial(sur[sur.length - 1])) sur.pop();
    return sur.join(" ");
  }
  const tok = name.trim().split(/\s+/);
  while (tok.length > 2 && isInitial(tok[tok.length - 1])) tok.pop();
  return tok[tok.length - 1];
};

// ---- exports ---------------------------------------------------------------

const csvCell = v => {
  const s = v == null ? "" : String(v);
  return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

export function toCSV(rows) {
  const cols = ["title", "creators", "year", "publisher", "doi", "url", "license",
                "category", "sectors", "taxa", "acg_records", "source", "added"];
  // BOM so Excel opens accented names correctly
  return "﻿" + [cols.join(","), ...rows.map(r => cols.map(c => csvCell(r[c])).join(","))]
    .join("\r\n");
}

const bibEscape = s => String(s ?? "").replace(/([{}])/g, "\\$1");

function bibKey(d, used) {
  const first = split(d.creators)[0] || d.publisher || "anon";
  const sur = surname(first).normalize("NFD").replace(/[^A-Za-z]/g, "") || "anon";
  const word = (d.title || "").normalize("NFD").replace(/[^A-Za-z ]/g, "")
    .split(" ").find(w => w.length > 3) || "data";
  const key = `${sur}${d.year ?? ""}${word}`.toLowerCase();
  let k = key, i = 1;
  while (used.has(k)) k = key + String.fromCharCode(96 + i++);
  used.add(k);
  return k;
}

export function toBibTeX(rows) {
  const used = new Set();
  return rows.map(d => {
    const f = [
      ["title", `{${bibEscape(d.title)}}`],
      ["author", `{${split(d.creators).map(bibEscape).join(" and ")}}`],
      ["year", `{${d.year ?? ""}}`],
      ["publisher", `{${bibEscape(d.publisher)}}`],
      ["doi", d.doi ? `{${d.doi}}` : null],
      ["url", `{${link(d)}}`],
      ["note", `{${d.category === "taxonomic treatment" ? "Taxonomic treatment" : "Dataset"}}`]
    ].filter(([, v]) => v);
    return `@misc{${bibKey(d, used)},\n${f.map(([k, v]) => `  ${k} = ${v}`).join(",\n")}\n}`;
  }).join("\n\n") + "\n";
}

export function toRIS(rows) {
  return rows.map(d => [
    "TY  - DATA",
    `TI  - ${d.title ?? ""}`,
    ...split(d.creators).map(a => `AU  - ${a}`),
    d.year ? `PY  - ${d.year}` : null,
    d.publisher ? `PB  - ${d.publisher}` : null,
    d.doi ? `DO  - ${d.doi}` : null,
    `UR  - ${link(d)}`,
    ...split(d.taxa).map(k => `KW  - ${k}`),
    "ER  - "
  ].filter(Boolean).join("\r\n")).join("\r\n\r\n") + "\r\n";
}

// ---- publications ----------------------------------------------------------

export const paperLink = d => d.doi ? "https://doi.org/" + d.doi : "https://openalex.org/" + d.openalex_id;

// OpenAlex/Crossref types, grouped for the filter (keys into strings.js)
const typeGroups = {
  article: "tArticle", "journal-article": "tArticle", review: "tArticle", "data-paper": "tArticle",
  preprint: "tPreprint", dissertation: "tThesis",
  book: "tBook", "book-chapter": "tBook", "reference-entry": "tBook",
  "conference-paper": "tConference", "conference-abstract": "tConference"
};
export const typeGroup = type => typeGroups[type] || "tOther";
export const typeOrder = ["tArticle", "tThesis", "tBook", "tPreprint", "tConference", "tOther"];

export function papersCSV(rows) {
  const cols = ["title", "authors", "year", "venue", "type", "doi", "openalex_id",
                "language", "is_oa", "oa_url", "sectors", "added"];
  return "﻿" + [cols.join(","), ...rows.map(r => cols.map(c => csvCell(r[c])).join(","))]
    .join("\r\n");
}

const bibTypes = { tArticle: "article", tThesis: "phdthesis", tBook: "book", tConference: "inproceedings" };
const venueField = { article: "journal", inproceedings: "booktitle", phdthesis: "school", book: "publisher" };

export function papersBibTeX(rows) {
  const used = new Set();
  return rows.map(d => {
    let kind = bibTypes[typeGroup(d.type)] || "misc";
    if (d.type === "book-chapter") kind = "incollection";
    const f = [
      ["title", `{${bibEscape(d.title)}}`],
      ["author", `{${split(d.authors).map(bibEscape).join(" and ")}}`],
      ["year", `{${d.year ?? ""}}`],
      [venueField[kind] || "howpublished", d.venue ? `{${bibEscape(d.venue)}}` : null],
      ["doi", d.doi ? `{${d.doi}}` : null],
      ["url", `{${paperLink(d)}}`]
    ].filter(([, v]) => v);
    const key = bibKey({ creators: d.authors, year: d.year, title: d.title }, used);
    return `@${kind}{${key},\n${f.map(([k, v]) => `  ${k} = ${v}`).join(",\n")}\n}`;
  }).join("\n\n") + "\n";
}

const risTypes = { tArticle: "JOUR", tThesis: "THES", tBook: "BOOK", tConference: "CONF", tPreprint: "UNPB" };

export function papersRIS(rows) {
  return rows.map(d => [
    `TY  - ${d.type === "book-chapter" ? "CHAP" : risTypes[typeGroup(d.type)] || "GEN"}`,
    `TI  - ${d.title ?? ""}`,
    ...split(d.authors).map(a => `AU  - ${a}`),
    d.year ? `PY  - ${d.year}` : null,
    d.venue ? `T2  - ${d.venue}` : null,
    d.doi ? `DO  - ${d.doi}` : null,
    `UR  - ${paperLink(d)}`,
    ...split(d.sectors).map(k => `KW  - ${k}`),
    "ER  - "
  ].filter(Boolean).join("\r\n")).join("\r\n\r\n") + "\r\n";
}

export function downloadButton(label, filename, type, makeText) {
  const b = document.createElement("button");
  b.className = "btn btn-sm btn-outline-primary me-2 mb-2";
  b.textContent = label;
  b.onclick = () => {
    const url = URL.createObjectURL(new Blob([makeText()], { type }));
    const a = Object.assign(document.createElement("a"), { href: url, download: filename });
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  return b;
}
