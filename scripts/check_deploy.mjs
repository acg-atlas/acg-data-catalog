// Deployment check (run by .github/workflows/deploy-check.yml).
// Passes when the latest "Deploy site" run on main succeeded and the live site
// answers on its main pages and serves exactly the approved papers and
// datasets in catalog/. Writes what it found to deploy-check.md and exits 1
// when something is wrong.
//
//   GH_TOKEN=$(gh auth token) node scripts/check_deploy.mjs
import { readFileSync, writeFileSync } from "node:fs";

const site = process.env.SITE || "https://acg-atlas.org";
const repo = process.env.GITHUB_REPOSITORY || "acg-atlas/acg-data-catalog";
const problems = [];

// 1. The latest deploy of main
const runs = await fetch(
  `https://api.github.com/repos/${repo}/actions/workflows/deploy.yml/runs?branch=main&per_page=1`,
  { headers: { Accept: "application/vnd.github+json",
               ...(process.env.GH_TOKEN ? { Authorization: `Bearer ${process.env.GH_TOKEN}` } : {}) } }
).then(r => r.json()).catch(() => ({}));
const run = runs.workflow_runs?.[0];
const deploying = run && run.status !== "completed";
if (!run) problems.push("Could not read the latest “Deploy site” run from GitHub.");
else if (!deploying && run.conclusion !== "success")
  problems.push(`The latest deploy (“${run.display_title}”) ended with **${run.conclusion}**. Its log: ${run.html_url}`);

// 2. The live site answers
for (const page of ["/", "/en/", "/publicaciones", "/papers", "/contribuir", "/sitemap.xml"]) {
  const status = await fetch(site + page).then(r => r.status).catch(e => e.cause?.code || e.message);
  if (status !== 200) problems.push(`${site}${page} answered ${status} instead of 200.`);
}

// 3. The live data matches main (skipped while a deploy is still running)
const approved = file => (readFileSync(file, "utf8").match(/^  review: approved\r?$/gm) || []).length;
if (!deploying) {
  for (const [file, json, what] of [["catalog/papers.yaml", "papers.json", "papers"],
                                    ["catalog/datasets.yaml", "catalog.json", "datasets"]]) {
    const want = approved(file);
    const have = await fetch(`${site}/data/${json}?check=${Date.now()}`)
      .then(r => r.json()).then(j => j.length).catch(() => "no");
    if (have !== want)
      problems.push(`The site lists ${have} ${what}, but ${file} on main has ${want} approved: the latest changes have not reached the site.`);
  }
}

const when = new Date().toISOString().slice(0, 16).replace("T", " ") + " UTC";
const report = problems.length
  ? ["The weekly deployment check found a problem with " + site + ":", "", ...problems.map(p => "- " + p), "",
     "Usually the fix is to open the failed run, read the error near the end of its log, and fix it in a PR. " +
     "To redeploy without changes: Actions → Deploy site → Run workflow.", "", `Checked ${when}.`]
  : [`All good: the latest deploy succeeded and ${site} serves what is on main. Checked ${when}.`];
writeFileSync("deploy-check.md", report.join("\n") + "\n");
console.log(report.join("\n"));
process.exit(problems.length ? 1 : 0);
