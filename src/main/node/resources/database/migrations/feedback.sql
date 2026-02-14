-- feedback table (PostgreSQL) — durable storage for Phase 4
CREATE TABLE IF NOT EXISTS feedback (
  id            BIGSERIAL PRIMARY KEY,
  session_id    TEXT NOT NULL,
  user_id       TEXT,
  query         TEXT NOT NULL,
  mode          TEXT NOT NULL,
  vertical      TEXT NOT NULL,
  thumb         TEXT NOT NULL,
  reason        TEXT,
  comment       TEXT,
  debug_json    JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_session_id ON feedback(session_id);
CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback(created_at);
