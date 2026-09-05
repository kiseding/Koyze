-- Keep idempotency keys after replay rows are compacted. The receipt is part
-- of the same transaction as the event projection, so an acknowledged event
-- can never be applied again even after its sync_events row is removed.
CREATE TABLE IF NOT EXISTS sync_event_receipts (
  user_id INTEGER NOT NULL,
  event_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  local_user_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  client_created_at INTEGER NOT NULL,
  server_sequence INTEGER NOT NULL,
  accepted_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, event_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Preserve the idempotency history of events accepted before this migration.
INSERT OR IGNORE INTO sync_event_receipts
  (user_id, event_id, device_id, local_user_id, event_type, entity_id,
   payload, client_created_at, server_sequence, accepted_at)
SELECT user_id, event_id, device_id, local_user_id, event_type, entity_id,
       payload, client_created_at, id, COALESCE(applied_at, created_at)
FROM sync_events;
