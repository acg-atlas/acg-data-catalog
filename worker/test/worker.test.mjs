// Run: npm test   (uses node:sqlite as a stand-in for D1)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import worker, { normalizeDoi, sameSecret } from "../src/index.js";

function fakeD1() {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const stmt = (sql) => ({
    args: [],
    bind(...a) { this.args = a; return this; },
    first() { return db.prepare(sql).get(...this.args) ?? null; },
    all() { return { results: db.prepare(sql).all(...this.args) }; },
    run() { return db.prepare(sql).run(...this.args); },
  });
  return { prepare: stmt, batch: async (s) => s.map((x) => x.run()), _db: db };
}

const csl = { title: "Leaf traits, ACG", type: "dataset", publisher: "EDI",
  author: [{ family: "Hulshof", given: "C" }], issued: { "date-parts": [[2025]] } };
const fakeFetch = async (url) => {
  if (String(url).includes("doi.org/10.9999/missing")) return new Response("", { status: 404 });
  if (String(url).includes("doi.org/10.5555/")) return Response.json({ ...csl, type: "article-journal" });
  if (String(url).includes("doi.org")) return Response.json(csl);
  if (String(url).includes("turnstile")) return Response.json({ success: true });
  throw new Error("unexpected fetch " + url);
};
const env = () => ({ DB: fakeD1(), ADMIN_TOKEN: "s3cret", TURNSTILE_SECRET: "x",
  ALLOWED_ORIGIN: "https://example.org" });
const call = (e, path, init = {}) =>
  worker.fetch(new Request("https://w.example" + path, init), e, {}, fakeFetch);
const post = (body, headers = {}) => ({ method: "POST",
  headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) });

test("normalizeDoi", () => {
  assert.equal(normalizeDoi("https://doi.org/10.6073/PASTA/ABC"), "10.6073/pasta/abc");
  assert.equal(normalizeDoi("doi: 10.5061/dryad.x"), "10.5061/dryad.x");
  assert.equal(normalizeDoi("hello"), null);
});

test("resolve, submit, duplicate, pending hides contact, status update", async () => {
  const e = env();
  let r = await call(e, "/api/resolve?doi=10.1234/abc");
  let j = await r.json();
  assert.equal(j.metadata.creators, "Hulshof, C");
  assert.equal(j.metadata.is_dataset, true);

  r = await call(e, "/api/submit", post({ doi: "https://doi.org/10.1234/ABC",
    sector: "Pitilla", contact: "me@x.org", note: "ALTA plots", turnstileToken: "t" }));
  assert.equal(r.status, 201);

  r = await call(e, "/api/submit", post({ doi: "10.1234/abc", turnstileToken: "t" }));
  j = await r.json();
  assert.equal(j.duplicate, true);

  r = await call(e, "/api/pending");
  assert.equal(r.status, 401);
  r = await call(e, "/api/pending", { headers: { Authorization: "Bearer s3cret" } });
  j = await r.json();
  assert.equal(j.submissions.length, 1);
  assert.equal(j.submissions[0].sector, "Pitilla");
  assert.equal("contact" in j.submissions[0], false);

  r = await call(e, "/api/status", post({ updates: [{ doi: "10.1234/abc", status: "approved" }] },
    { Authorization: "Bearer s3cret" }));
  assert.equal((await r.json()).updated, 1);
  r = await call(e, "/api/pending", { headers: { Authorization: "Bearer s3cret" } });
  assert.equal((await r.json()).submissions.length, 0);
  const row = e.DB._db.prepare("SELECT contact FROM submissions WHERE doi = '10.1234/abc'").get();
  assert.equal(row.contact, null);   // email erased once decided
});

test("rate limiter blocks a visitor over the limit", async () => {
  const e = env();
  let n = 0;
  e.SUBMIT_LIMITER = { limit: async () => ({ success: ++n <= 1 }) };
  assert.equal((await call(e, "/api/submit", post({ doi: "10.1234/r1", turnstileToken: "t" }))).status, 201);
  assert.equal((await call(e, "/api/submit", post({ doi: "10.1234/r2", turnstileToken: "t" }))).status, 429);
});

test("submissions record kind: dataset by default, paper when asked", async () => {
  const e = env();
  await call(e, "/api/submit", post({ doi: "10.1234/data", turnstileToken: "t" }));
  await call(e, "/api/submit", post({ doi: "10.1234/paper", kind: "paper", turnstileToken: "t" }));
  await call(e, "/api/submit", post({ doi: "10.1234/odd", kind: "poem", turnstileToken: "t" }));
  const r = await call(e, "/api/pending", { headers: { Authorization: "Bearer s3cret" } });
  const kinds = Object.fromEntries((await r.json()).submissions.map((s) => [s.doi, s.kind]));
  assert.deepEqual(kinds, { "10.1234/data": "dataset", "10.1234/paper": "paper", "10.1234/odd": "dataset" });
});

test("bad input is rejected", async () => {
  const e = env();
  assert.equal((await call(e, "/api/submit", post({ doi: "nope" }))).status, 400);
  assert.equal((await call(e, "/api/resolve?doi=10.9999/missing")).status, 404);
  const r = await call(e, "/api/submit", post({ doi: "10.1234/x", sector: "Narnia", turnstileToken: "t" }));
  assert.equal(r.status, 201);
  const row = e.DB._db.prepare("SELECT sector FROM submissions").get();
  assert.equal(row.sector, null);
});

test("a list of DOIs: one captcha, sorted by type, answered per DOI", async () => {
  const e = env();
  await call(e, "/api/submit", post({ doi: "10.1234/old", turnstileToken: "t" }));
  const r = await call(e, "/api/submit", post({ turnstileToken: "t", sector: "Cacao",
    dois: ["https://doi.org/10.1234/NEW", "10.5555/article", "10.1234/old", "10.9999/missing",
           "not a doi", "10.1234/new"] }));
  assert.equal(r.status, 200);
  const res = Object.fromEntries((await r.json()).results.map((x) => [x.doi, x]));
  assert.deepEqual(Object.keys(res), ["10.1234/new", "10.5555/article", "10.1234/old", "10.9999/missing"]);
  assert.equal(res["10.1234/new"].result, "added");
  assert.equal(res["10.1234/new"].kind, "dataset");
  assert.equal(res["10.5555/article"].kind, "paper");
  assert.equal(res["10.1234/old"].result, "duplicate");
  assert.equal(res["10.1234/old"].status, "pending");
  assert.equal(res["10.9999/missing"].result, "not_found");
  const sectors = e.DB._db.prepare("SELECT DISTINCT sector FROM submissions WHERE doi != '10.1234/old'").all();
  assert.deepEqual(sectors.map((s) => s.sector), ["Cacao"]);
});

test("a list of DOIs is capped and needs the captcha", async () => {
  const e = env();
  let j;
  const many = Array.from({ length: 26 }, (_, i) => `10.1234/n${i}`);
  let r = await call(e, "/api/submit", post({ turnstileToken: "t", dois: many }));
  j = await r.json();
  assert.equal(j.error, "too_many");
  assert.equal(j.max, 25);
  r = await call(e, "/api/submit", post({ turnstileToken: "t", dois: ["junk"] }));
  assert.equal(r.status, 400);
  const noCaptcha = { ...e, TURNSTILE_SECRET: "x" };
  r = await worker.fetch(new Request("https://w.example/api/submit", post({ dois: ["10.1234/z"] })),
    noCaptcha, {}, fakeFetch);
  assert.equal(r.status, 403);
});

test("CORS answers each allowed site with its own address", async () => {
  const e = { ...env(), ALLOWED_ORIGIN: "https://acg-atlas.org, https://acg-atlas.pages.dev" };
  const from = (origin) => worker.fetch(new Request("https://w.example/api/submit",
    { method: "OPTIONS", headers: { Origin: origin } }), e, {}, fakeFetch);
  assert.equal((await from("https://acg-atlas.pages.dev")).headers.get("Access-Control-Allow-Origin"),
    "https://acg-atlas.pages.dev");
  assert.equal((await from("https://acg-atlas.org")).headers.get("Access-Control-Allow-Origin"),
    "https://acg-atlas.org");
  assert.equal((await from("https://evil.example")).headers.get("Access-Control-Allow-Origin"),
    "https://acg-atlas.org");
});

test("admin token check: right token passes, near misses fail", async () => {
  assert.equal(sameSecret("Bearer s3cret", "Bearer s3cret"), true);
  assert.equal(sameSecret("Bearer s3creT", "Bearer s3cret"), false);
  assert.equal(sameSecret("Bearer s3cret!", "Bearer s3cret"), false);
  assert.equal(sameSecret("", "Bearer s3cret"), false);
  const e = env();
  const get = (h) => call(e, "/api/pending", { headers: { Authorization: h } });
  assert.equal((await get("Bearer s3cret")).status, 200);
  assert.equal((await get("Bearer s3creT")).status, 401);
  e.ADMIN_TOKEN = "";                                   // no token configured: nobody is admin
  assert.equal((await get("Bearer ")).status, 401);
});

test("lookups and admin calls are rate limited; bad admin JSON is rejected", async () => {
  const e = env();
  let n = 0;
  e.RESOLVE_LIMITER = { limit: async () => ({ success: ++n <= 1 }) };
  assert.equal((await call(e, "/api/resolve?doi=10.1234/abc")).status, 200);
  assert.equal((await call(e, "/api/resolve?doi=10.1234/abc")).status, 429);
  let m = 0;
  e.ADMIN_LIMITER = { limit: async () => ({ success: ++m <= 1 }) };
  const auth = { Authorization: "Bearer s3cret" };
  assert.equal((await call(e, "/api/status", { method: "POST", headers: auth, body: "not json" })).status, 400);
  assert.equal((await call(e, "/api/pending", { headers: auth })).status, 429);
  const huge = Array.from({ length: 1000 }, (_, i) => `10.1234/x${i}`);
  const r = await call(env(), "/api/submit", post({ turnstileToken: "t", dois: huge }));
  assert.equal((await r.json()).error, "too_many");
});
