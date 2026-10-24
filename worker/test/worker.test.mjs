// Run: npm test   (uses node:sqlite as a stand-in for D1)
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import worker, { normalizeDoi } from "../src/index.js";

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
