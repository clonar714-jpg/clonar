-- Run this against your PostgreSQL DB to enable "Report this source" feedback.
CREATE TABLE IF NOT EXISTS source_feedback (
  id SERIAL PRIMARY KEY,
  session_id TEXT NOT NULL,
  source_index INTEGER NOT NULL,
  url TEXT NOT NULL,
  reason TEXT,
  user_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_source_feedback_session ON source_feedback (session_id);
