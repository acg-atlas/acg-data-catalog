// ACG Atlas: DOI submission Worker
//
// Public:
//   GET  /api/resolve?doi=...   look up a DOI, return a metadata preview
//   POST /api/submit            store a submission (Turnstile-protected);
//                               kind = "dataset" (default) or "paper"
// Admin (Authorization: Bearer ADMIN_TOKEN):
//   GET  /api/pending           pending submissions, WITHOUT contact emails
//   POST /api/status            {updates: [{doi, status}]} after review;
//                               approved/excluded also erases the contact email
//
// Bindings (wrangler.toml / secrets): DB (D1), ADMIN_TOKEN, TURNSTILE_SECRET,
// ALLOWED_ORIGIN (the catalog site, e.g. https://acg-atlas.pages.dev).

const SECTORS = [
  "Santa Rosa", "Murciélago", "Pocosol", "Junquillal", "Horizontes",
  "Guanacaste", "Rincón de la Vieja", "Pitilla", "Cacao", "Maritza",
  "San Cristóbal", "Del Oro", "Santa Elena", "Marino", "Other / Otro",
];

export function normalizeDoi(input) {
  if (typeof input !== "string") return null;
  let d = input.trim().toLowerCase();
  d = d.replace(/^(https?:\/\/)?(dx\.)?doi\.org\//, "").replace(/^doi:\s*/, "");
  return /^10\.\d{4,9}\/\S+$/.test(d) ? d : null;
}

// CSL-JSON content negotiation works for both DataCite and Crossref DOIs.
export async function resolveDoi(doi, fetchImpl = fetch) {
  const res = await fetchImpl(`https://doi.org/${encodeURIComponent(doi).replace(/%2F/g, "/")}`, {
    headers: { Accept: "application/vnd.citationstyles.csl+json" },
    redirect: "follow",
  });
  if (!res.ok) return null;
  const m = await res.json();
  const authors = (m.author || [])
    .map((a) => a.literal || [a.family, a.given].filter(Boolean).join(", "))
    .filter(Boolean);
  const year = m.issued?.["date-parts"]?.[0]?.[0] ?? null;
  const title = Array.isArray(m.title) ? m.title[0] : m.title;
  return {
    doi,
    title: title || null,
    creators: authors.join("; ") || null,
    year: Number.isInteger(year) ? year : null,
    publisher: m.publisher || null,
    resource_type: m.type || null,
    is_dataset: /dataset/i.test(m.type || ""),
  };
}

async function verifyTurnstile(token, secret, ip, fetchImpl = fetch) {
  if (!secret) return true; // local development only
  if (!token) return false;
  const body = new FormData();
  body.append("secret", secret);
  body.append("response", token);
  if (ip) body.append("remoteip", ip);
  const res = await fetchImpl(
    "https://challenges.cloudflare.com/turnstile/v0/siteverify",
    { method: "POST", body },
  );
  const out = await res.json();
  return out.success === true;
}

function cors(env) {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function json(data, status, env) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...cors(env) },
  });
}

function isAdmin(request, env) {
  const h = request.headers.get("Authorization") || "";
  return env.ADMIN_TOKEN && h === `Bearer ${env.ADMIN_TOKEN}`;
}

const clip = (s, n) => (typeof s === "string" ? s.trim().slice(0, n) : null);

export default {
  async fetch(request, env, ctx, fetchImpl = fetch) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: cors(env) });

    // -- Public: preview -------------------------------------------------
    if (url.pathname === "/api/resolve" && request.method === "GET") {
      const doi = normalizeDoi(url.searchParams.get("doi"));
      if (!doi) return json({ ok: false, error: "invalid_doi" }, 400, env);
      const existing = await env.DB.prepare(
        "SELECT status FROM submissions WHERE doi = ?").bind(doi).first();
      const meta = await resolveDoi(doi, fetchImpl);
      if (!meta) return json({ ok: false, error: "not_found" }, 404, env);
      return json({ ok: true, metadata: meta, already: existing?.status ?? null }, 200, env);
    }

    // -- Public: submit --------------------------------------------------
    if (url.pathname === "/api/submit" && request.method === "POST") {
      // Rate limit per visitor (Cloudflare rate-limiting binding; absent in tests)
      if (env.SUBMIT_LIMITER) {
        const ip = request.headers.get("CF-Connecting-IP") || "unknown";
        const { success } = await env.SUBMIT_LIMITER.limit({ key: ip });
        if (!success) return json({ ok: false, error: "rate_limited" }, 429, env);
      }
      let body;
      try { body = await request.json(); } catch { return json({ ok: false, error: "bad_json" }, 400, env); }
      const doi = normalizeDoi(body.doi);
      if (!doi) return json({ ok: false, error: "invalid_doi" }, 400, env);
      const human = await verifyTurnstile(body.turnstileToken, env.TURNSTILE_SECRET,
        request.headers.get("CF-Connecting-IP"), fetchImpl);
      if (!human) return json({ ok: false, error: "captcha" }, 403, env);

      const existing = await env.DB.prepare(
        "SELECT status FROM submissions WHERE doi = ?").bind(doi).first();
      if (existing) return json({ ok: true, duplicate: true, status: existing.status }, 200, env);

      const meta = await resolveDoi(doi, fetchImpl);
      if (!meta) return json({ ok: false, error: "not_found" }, 404, env);
      const sector = SECTORS.includes(body.sector) ? body.sector : null;
      const kind = body.kind === "paper" ? "paper" : "dataset";

      await env.DB.prepare(
        `INSERT INTO submissions
           (doi, kind, title, creators, year, publisher, resource_type, sector,
            note, contact, lang, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', datetime('now'), datetime('now'))`,
      ).bind(doi, kind, meta.title, meta.creators, meta.year, meta.publisher,
        meta.resource_type, sector, clip(body.note, 1000), clip(body.contact, 200),
        body.lang === "es" ? "es" : "en").run();
      return json({ ok: true, metadata: meta }, 201, env);
    }

    // -- Admin -----------------------------------------------------------
    if (url.pathname === "/api/pending" && request.method === "GET") {
      if (!isAdmin(request, env)) return json({ ok: false }, 401, env);
      const { results } = await env.DB.prepare(
        `SELECT doi, kind, title, creators, year, publisher, resource_type, sector, note,
                lang, created_at
           FROM submissions WHERE status = 'pending' ORDER BY created_at`).all();
      return json({ ok: true, submissions: results }, 200, env);
    }

    if (url.pathname === "/api/status" && request.method === "POST") {
      if (!isAdmin(request, env)) return json({ ok: false }, 401, env);
      const { updates = [] } = await request.json();
      const valid = updates.filter((u) => normalizeDoi(u.doi) &&
        ["approved", "excluded", "pending"].includes(u.status));
      if (valid.length) {
        await env.DB.batch(valid.map((u) => env.DB.prepare(
          // Once decided, the submitter's email is no longer needed: erase it.
          `UPDATE submissions SET status = ?1,
             contact = CASE WHEN ?1 IN ('approved', 'excluded') THEN NULL ELSE contact END,
             updated_at = datetime('now') WHERE doi = ?2`,
        ).bind(u.status, normalizeDoi(u.doi))));
      }
      return json({ ok: true, updated: valid.length }, 200, env);
    }

    return json({ ok: false, error: "not_found" }, 404, env);
  },
};
