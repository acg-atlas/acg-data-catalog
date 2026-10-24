-- Submissions can be datasets or papers (Contribute page, October 2026).
-- Existing rows are datasets. Apply once to the live database with:
--   npx wrangler d1 execute acg-submissions --remote --file=migrations/0001_add_kind.sql
ALTER TABLE submissions ADD COLUMN kind TEXT NOT NULL DEFAULT 'dataset'
  CHECK (kind IN ('dataset', 'paper'));
