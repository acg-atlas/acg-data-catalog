-- D1 schema for DOI submissions.
-- Apply with: npx wrangler d1 execute acg-submissions --remote --file=schema.sql
CREATE TABLE IF NOT EXISTS submissions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  doi           TEXT NOT NULL UNIQUE,
  kind          TEXT NOT NULL DEFAULT 'dataset'
                CHECK (kind IN ('dataset', 'paper')),
  title         TEXT,
  creators      TEXT,
  year          INTEGER,
  publisher     TEXT,
  resource_type TEXT,
  sector        TEXT,
  note          TEXT,
  contact       TEXT,          -- private: never returned by /api/pending
  lang          TEXT DEFAULT 'en',
  status        TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'approved', 'excluded')),
  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions (status);
