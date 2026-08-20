CREATE TABLE IF NOT EXISTS sync_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  event_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  local_user_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  client_created_at INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE(user_id, event_id)
);

ALTER TABLE playlist_songs ADD COLUMN playlist_item_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_playlist_item_id
  ON playlist_songs(user_id, playlist_id, playlist_item_id)
  WHERE playlist_item_id IS NOT NULL;


CREATE INDEX IF NOT EXISTS idx_sync_events_user_id
  ON sync_events(user_id, id);

CREATE TABLE IF NOT EXISTS sync_tombstones (
  user_id INTEGER NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  server_sequence INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, entity_type, entity_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_ratings (
  user_id INTEGER NOT NULL,
  song_id TEXT NOT NULL,
  rating INTEGER NOT NULL,
  server_sequence INTEGER NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, song_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_play_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  event_id TEXT NOT NULL,
  song_id TEXT NOT NULL,
  played_at INTEGER NOT NULL,
  listened_sec REAL NOT NULL DEFAULT 0,
  payload TEXT NOT NULL DEFAULT '{}',
  UNIQUE(user_id, event_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS sync_devices (
  user_id INTEGER NOT NULL,
  device_id TEXT NOT NULL,
  local_user_id TEXT NOT NULL,
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, device_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
