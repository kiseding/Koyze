-- Durable, transaction-friendly replacement for the two eventually-consistent
-- KV sync-state keys. Event projections retain their server sequence so an
-- older event that finishes late cannot overwrite a newer projection.
CREATE TABLE IF NOT EXISTS user_sync_payloads (
  user_id INTEGER PRIMARY KEY,
  settings TEXT NOT NULL DEFAULT '{}',
  sources TEXT NOT NULL DEFAULT '[]',
  base_sequence INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_setting_projections (
  user_id INTEGER NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  server_sequence INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, key),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_source_projections (
  user_id INTEGER NOT NULL,
  id TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT '{}',
  deleted INTEGER NOT NULL DEFAULT 0,
  server_sequence INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_setting_projection_sequence
  ON sync_setting_projections(user_id, server_sequence);
CREATE INDEX IF NOT EXISTS idx_sync_source_projection_sequence
  ON sync_source_projections(user_id, server_sequence);

CREATE TABLE IF NOT EXISTS sync_event_watermarks (
  user_id INTEGER PRIMARY KEY,
  compacted_through INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- An event and every materialized projection are committed in one D1 batch.
-- Existing events predate the marker and were already projected by 0007-era
-- code, so mark them applied during migration.
ALTER TABLE sync_events ADD COLUMN applied_at TEXT;
UPDATE sync_events SET applied_at = COALESCE(applied_at, created_at);
