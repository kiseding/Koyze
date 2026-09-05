import type { Env } from '../lib/response';
import { ensureSyncPayload } from './sync-payload';
import { getSyncRevision } from './sync-state';

export type IncomingSyncEvent = {
  eventId: string;
  deviceId: string;
  localUserId: string;
  eventType: string;
  entityId: string;
  payload: Record<string, unknown>;
  createdAt: number;
};

type SyncEventReceipt = {
  device_id: string;
  local_user_id: string;
  event_type: string;
  entity_id: string;
  payload: string;
  client_created_at: number;
};

export class SyncEventIdConflictError extends Error {
  constructor(readonly eventId: string) {
    super(`sync event id already belongs to a different event: ${eventId}`);
    this.name = 'SyncEventIdConflictError';
  }
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson(object[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function receiptMatches(receipt: SyncEventReceipt, event: IncomingSyncEvent): boolean {
  let storedPayload: unknown;
  try {
    storedPayload = JSON.parse(receipt.payload);
  } catch {
    return false;
  }
  return receipt.device_id === event.deviceId &&
    receipt.local_user_id === event.localUserId &&
    receipt.event_type === event.eventType &&
    receipt.entity_id === event.entityId &&
    Number(receipt.client_created_at) === event.createdAt &&
    canonicalJson(storedPayload) === canonicalJson(event.payload);
}

export async function appendSyncEvents(
  env: Env,
  userId: number,
  events: IncomingSyncEvent[],
): Promise<{ acceptedEventIds: string[]; cursor: number }> {
  const acceptedEventIds: string[] = [];
  await getSyncRevision(env, userId);
  for (const event of events) {
    if (event.eventType === 'setting.set' || event.eventType.startsWith('custom_source.')) {
      await ensureSyncPayload(env, userId);
    }
    const statements = buildEventTransaction(env, userId, event);
    const results = await env.DB.batch(statements);
    const receipt = results.at(-1)?.results?.[0] as SyncEventReceipt | undefined;
    if (!receipt || !receiptMatches(receipt, event)) {
      throw new SyncEventIdConflictError(event.eventId);
    }
    // A durable receipt survives replay-log compaction. Both a new event and
    // an identical retry are acknowledged; only the new pending row can touch
    // projections.
    acceptedEventIds.push(event.eventId);
  }
  try {
    await compactSyncEvents(env, userId);
  } catch (error) {
    // Compaction is maintenance, not part of event acceptance. A failed
    // maintenance pass is safe to retry on the next push.
    console.error('[sync:compact]', error);
  }
  return { acceptedEventIds, cursor: await currentSyncCursor(env, userId) };
}

/**
 * Bounds each account's replay log. Materialized state remains authoritative;
 * clients behind the recorded watermark must bootstrap from a snapshot.
 */
export async function compactSyncEvents(
  env: Env,
  userId: number,
  maxRetained = 10_000,
): Promise<number> {
  if (!Number.isInteger(maxRetained) || maxRetained < 1) {
    throw new RangeError('maxRetained must be a positive integer');
  }
  const cutoff = await env.DB.prepare(
    `SELECT id FROM sync_events
     WHERE user_id = ? AND applied_at IS NOT NULL
     ORDER BY id DESC LIMIT 1 OFFSET ?`,
  ).bind(userId, maxRetained).first<{ id: number }>();
  if (!cutoff) return 0;
  const cutoffId = Number(cutoff.id);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO sync_event_watermarks (user_id, compacted_through, updated_at)
       VALUES (?, ?, datetime('now'))
       ON CONFLICT(user_id) DO UPDATE SET
         compacted_through = MAX(compacted_through, excluded.compacted_through),
         updated_at = datetime('now')`,
    ).bind(userId, cutoffId),
    env.DB.prepare(
      'DELETE FROM sync_events WHERE user_id = ? AND id <= ? AND applied_at IS NOT NULL',
    ).bind(userId, cutoffId),
  ]);
  return cutoffId;
}

export async function syncEventWatermark(env: Env, userId: number): Promise<number> {
  const row = await env.DB.prepare(
    'SELECT compacted_through FROM sync_event_watermarks WHERE user_id = ?',
  ).bind(userId).first<{ compacted_through: number }>();
  return Number(row?.compacted_through ?? 0);
}

const PENDING_EVENT = `EXISTS (
  SELECT 1 FROM sync_events AS pending
  WHERE pending.user_id = ? AND pending.event_id = ?
    AND pending.applied_at IS NULL
)`;

function tombstoneStatement(
  env: Env,
  userId: number,
  eventId: string,
  entityType: string,
  entityId: string,
): D1PreparedStatement {
  return env.DB.prepare(
    `INSERT INTO sync_tombstones
     (user_id, entity_type, entity_id, server_sequence)
     SELECT ?, ?, ?, pending.id
     FROM sync_events AS pending
     WHERE pending.user_id = ? AND pending.event_id = ?
       AND pending.applied_at IS NULL
     ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
       server_sequence = excluded.server_sequence,
       created_at = datetime('now')
     WHERE excluded.server_sequence > sync_tombstones.server_sequence`,
  ).bind(userId, entityType, entityId, userId, eventId);
}

function buildEventTransaction(
  env: Env,
  userId: number,
  event: IncomingSyncEvent,
): D1PreparedStatement[] {
  const statements: D1PreparedStatement[] = [env.DB.prepare(
    `INSERT INTO sync_events
     (user_id, event_id, device_id, local_user_id, event_type, entity_id,
      payload, client_created_at)
     SELECT ?, ?, ?, ?, ?, ?, ?, ?
     WHERE NOT EXISTS (
       SELECT 1 FROM sync_event_receipts WHERE user_id = ? AND event_id = ?
     )
     ON CONFLICT(user_id, event_id) DO NOTHING`,
  ).bind(
    userId,
    event.eventId,
    event.deviceId,
    event.localUserId,
    event.eventType,
    event.entityId,
    JSON.stringify(event.payload),
    event.createdAt,
    userId,
    event.eventId,
  )];

  if (event.eventType === 'favorite.add') {
    const s = event.payload.song as Record<string, unknown>;
    const songmid = String(s.songmid ?? s.id ?? '').slice(0, 256);
    const source = String(s.source ?? '').slice(0, 32);
    const noNewerTombstone = `NOT EXISTS (
      SELECT 1 FROM sync_tombstones AS tombstone
      WHERE tombstone.user_id = ? AND tombstone.entity_type = 'favorite'
        AND tombstone.entity_id = ? AND tombstone.server_sequence >= (
          SELECT id FROM sync_events WHERE user_id = ? AND event_id = ?
        )
    )`;
    statements.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO playlists (id, user_id, name, position)
         SELECT 'love', ?, '我喜欢', 0
         WHERE ${PENDING_EVENT} AND ${noNewerTombstone}`,
      ).bind(
        userId, userId, event.eventId,
        userId, event.entityId, userId, event.eventId,
      ),
      env.DB.prepare(
        `INSERT OR IGNORE INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, img,
         interval, hash, metadata, position, playlist_item_id)
         SELECT 'love', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
           COALESCE((SELECT MAX(position) + 1 FROM playlist_songs
                     WHERE playlist_id = 'love' AND user_id = ?), 0), ?
         WHERE ${PENDING_EVENT} AND ${noNewerTombstone}`,
      ).bind(
        userId,
        String(s.name ?? '').slice(0, 256),
        String(s.singer ?? '').slice(0, 256),
        source,
        songmid,
        String(s.album ?? s.albumName ?? '').slice(0, 256),
        String(s.artwork ?? s.img ?? '').slice(0, 512),
        String(s.duration ?? 0),
        String(s.hash ?? '').slice(0, 256),
        JSON.stringify(s.meta ?? {}),
        userId,
        event.entityId,
        userId, event.eventId,
        userId, event.entityId, userId, event.eventId,
      ),
      env.DB.prepare(
        `DELETE FROM sync_tombstones
         WHERE user_id = ? AND entity_type = 'favorite' AND entity_id = ?
           AND server_sequence < (
             SELECT id FROM sync_events WHERE user_id = ? AND event_id = ?
           ) AND ${PENDING_EVENT}`,
      ).bind(
        userId, event.entityId, userId, event.eventId,
        userId, event.eventId,
      ),
    );
  } else if (event.eventType === 'favorite.remove') {
    const song = event.payload.song;
    const songmid = song && typeof song === 'object'
      ? String((song as Record<string, unknown>).songmid ?? (song as Record<string, unknown>).id ?? '')
      : String(event.payload.songmid ?? event.entityId);
    const source = song && typeof song === 'object'
      ? String((song as Record<string, unknown>).source ?? '')
      : String(event.payload.source ?? '');
    statements.push(
      env.DB.prepare(
        `DELETE FROM playlist_songs
         WHERE playlist_id = 'love' AND user_id = ? AND songmid = ?
           AND source = ? AND ${PENDING_EVENT}`,
      ).bind(userId, songmid, source, userId, event.eventId),
      tombstoneStatement(env, userId, event.eventId, 'favorite', event.entityId),
    );
  } else if (event.eventType === 'playlist.create') {
    statements.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO playlists (id, user_id, name, position)
         SELECT ?, ?, ?, COALESCE((SELECT MAX(position) + 1 FROM playlists
                                   WHERE user_id = ? AND id NOT LIKE '__stage__:%'), 0)
         WHERE ${PENDING_EVENT}`,
      ).bind(
        event.entityId, userId, String(event.payload.name ?? event.entityId), userId,
        userId, event.eventId,
      ),
      env.DB.prepare(
        `DELETE FROM sync_tombstones
         WHERE user_id = ? AND entity_type = 'playlist' AND entity_id = ?
           AND server_sequence < (
             SELECT id FROM sync_events WHERE user_id = ? AND event_id = ?
           ) AND ${PENDING_EVENT}`,
      ).bind(
        userId, event.entityId, userId, event.eventId,
        userId, event.eventId,
      ),
    );
  } else if (event.eventType === 'playlist.rename') {
    statements.push(env.DB.prepare(
      `UPDATE playlists SET name = ?, updated_at = datetime('now')
       WHERE id = ? AND user_id = ? AND ${PENDING_EVENT}`,
    ).bind(
      String(event.payload.name ?? event.entityId), event.entityId, userId,
      userId, event.eventId,
    ));
  } else if (event.eventType === 'playlist.delete') {
    statements.push(
      env.DB.prepare(
        `DELETE FROM playlists WHERE id = ? AND user_id = ? AND ${PENDING_EVENT}`,
      ).bind(event.entityId, userId, userId, event.eventId),
      tombstoneStatement(env, userId, event.eventId, 'playlist', event.entityId),
    );
  } else if (event.eventType === 'playlist_item.add') {
    const playlistId = String(event.payload.playlistId ?? '');
    const s = event.payload.song as Record<string, unknown>;
    statements.push(env.DB.prepare(
      `INSERT INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, img,
         interval, hash, metadata, position, playlist_item_id)
       SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          COALESCE((SELECT MAX(position) + 1 FROM playlist_songs WHERE playlist_id = ? AND user_id = ?), 0), ?
       WHERE EXISTS (SELECT 1 FROM playlists WHERE id = ? AND user_id = ?)
         AND ${PENDING_EVENT}`,
    ).bind(
      playlistId, userId, String(s.name ?? '').slice(0, 256),
      String(s.singer ?? '').slice(0, 256), String(s.source ?? '').slice(0, 32),
      String(s.songmid ?? s.id ?? '').slice(0, 256), String(s.album ?? '').slice(0, 256),
      String(s.artwork ?? '').slice(0, 512), String(s.duration ?? 0),
      String(s.hash ?? '').slice(0, 256), JSON.stringify(s.meta ?? {}),
      playlistId, userId, event.entityId, playlistId, userId,
      userId, event.eventId,
    ));
  } else if (event.eventType === 'playlist_item.remove') {
    const playlistId = String(event.payload.playlistId ?? '');
    const itemId = String(
      event.payload.playlistItemId ?? event.payload.songId ?? event.payload.songmid ?? '',
    );
    const source = String(event.payload.source ?? '');
    statements.push(env.DB.prepare(
      `DELETE FROM playlist_songs
       WHERE playlist_id = ? AND user_id = ?
         AND (playlist_item_id = ? OR (songmid = ? AND source = ?))
         AND ${PENDING_EVENT}`,
    ).bind(
      playlistId, userId, itemId, itemId, source,
      userId, event.eventId,
    ));
  } else if (event.eventType === 'playlist_item.move') {
    const playlistId = String(event.payload.playlistId ?? '');
    const itemId = String(
      event.payload.playlistItemId ?? event.payload.songId ?? event.payload.songmid ?? '',
    );
    const source = String(event.payload.source ?? '');
    const position = Number(event.payload.index);
    statements.push(env.DB.prepare(
      `WITH moving AS (
         SELECT id, position AS old_position
         FROM playlist_songs
         WHERE playlist_id = ? AND user_id = ?
           AND (playlist_item_id = ? OR (songmid = ? AND source = ?))
         ORDER BY position LIMIT 1
       )
       UPDATE playlist_songs
       SET position = CASE
         WHEN id = (SELECT id FROM moving) THEN ?
         WHEN (SELECT old_position FROM moving) < ?
              AND position > (SELECT old_position FROM moving) AND position <= ?
           THEN position - 1
         WHEN (SELECT old_position FROM moving) > ?
              AND position >= ? AND position < (SELECT old_position FROM moving)
           THEN position + 1
         ELSE position
       END
       WHERE playlist_id = ? AND user_id = ? AND EXISTS (SELECT 1 FROM moving)
         AND ${PENDING_EVENT}`,
    ).bind(
      playlistId, userId, itemId, itemId, source,
      position, position, position, position, position,
      playlistId, userId, userId, event.eventId,
    ));
  } else if (event.eventType === 'rating.set') {
    const rating = Number(event.payload.rating);
    statements.push(env.DB.prepare(
      `INSERT INTO sync_ratings (user_id, song_id, rating, server_sequence)
       SELECT ?, ?, ?, pending.id FROM sync_events AS pending
       WHERE pending.user_id = ? AND pending.event_id = ?
         AND pending.applied_at IS NULL
       ON CONFLICT(user_id, song_id) DO UPDATE SET
         rating = excluded.rating,
         server_sequence = excluded.server_sequence,
         updated_at = datetime('now')
       WHERE excluded.server_sequence > sync_ratings.server_sequence`,
    ).bind(userId, event.entityId, rating, userId, event.eventId));
  } else if (event.eventType === 'rating.remove') {
    statements.push(env.DB.prepare(
      `DELETE FROM sync_ratings
       WHERE user_id = ? AND song_id = ? AND ${PENDING_EVENT}`,
    ).bind(userId, event.entityId, userId, event.eventId));
  } else if (event.eventType === 'setting.set') {
    statements.push(env.DB.prepare(
      `INSERT INTO sync_setting_projections (user_id, key, value, server_sequence)
       SELECT ?, ?, ?, pending.id FROM sync_events AS pending
       WHERE pending.user_id = ? AND pending.event_id = ?
         AND pending.applied_at IS NULL
       ON CONFLICT(user_id, key) DO UPDATE SET
         value = excluded.value,
         server_sequence = excluded.server_sequence,
         updated_at = datetime('now')
       WHERE excluded.server_sequence > sync_setting_projections.server_sequence`,
    ).bind(
      userId, event.entityId, String(event.payload.value ?? ''),
      userId, event.eventId,
    ));
  } else if (event.eventType === 'custom_source.upsert') {
    statements.push(env.DB.prepare(
      `INSERT INTO sync_source_projections
       (user_id, id, source, deleted, server_sequence)
       SELECT ?, ?, ?, 0, pending.id FROM sync_events AS pending
       WHERE pending.user_id = ? AND pending.event_id = ?
         AND pending.applied_at IS NULL
       ON CONFLICT(user_id, id) DO UPDATE SET
         source = excluded.source,
         deleted = 0,
         server_sequence = excluded.server_sequence,
         updated_at = datetime('now')
       WHERE excluded.server_sequence > sync_source_projections.server_sequence`,
    ).bind(
      userId, event.entityId, JSON.stringify(event.payload.source),
      userId, event.eventId,
    ));
  } else if (event.eventType === 'custom_source.remove') {
    statements.push(env.DB.prepare(
      `INSERT INTO sync_source_projections
       (user_id, id, source, deleted, server_sequence)
       SELECT ?, ?, '{}', 1, pending.id FROM sync_events AS pending
       WHERE pending.user_id = ? AND pending.event_id = ?
         AND pending.applied_at IS NULL
       ON CONFLICT(user_id, id) DO UPDATE SET
         source = '{}',
         deleted = 1,
         server_sequence = excluded.server_sequence,
         updated_at = datetime('now')
       WHERE excluded.server_sequence > sync_source_projections.server_sequence`,
    ).bind(userId, event.entityId, userId, event.eventId));
  }

  statements.push(
    env.DB.prepare(
      `INSERT OR IGNORE INTO sync_event_receipts
       (user_id, event_id, device_id, local_user_id, event_type, entity_id,
        payload, client_created_at, server_sequence)
       SELECT ?, ?, ?, ?, ?, ?, ?, ?, pending.id
       FROM sync_events AS pending
       WHERE pending.user_id = ? AND pending.event_id = ?
         AND pending.applied_at IS NULL`,
    ).bind(
      userId, event.eventId, event.deviceId, event.localUserId,
      event.eventType, event.entityId, JSON.stringify(event.payload), event.createdAt,
      userId, event.eventId,
    ),
    env.DB.prepare(
      `UPDATE user_sync_state
       SET revision = revision + 1, updated_at = datetime('now')
       WHERE user_id = ? AND ${PENDING_EVENT}`,
    ).bind(userId, userId, event.eventId),
    env.DB.prepare(
      `INSERT INTO sync_devices (user_id, device_id, local_user_id, last_seen_at)
       SELECT ?, ?, ?, datetime('now') WHERE ${PENDING_EVENT}
       ON CONFLICT(user_id, device_id) DO UPDATE SET
         local_user_id = excluded.local_user_id,
         last_seen_at = datetime('now')`,
    ).bind(
      userId, event.deviceId, event.localUserId,
      userId, event.eventId,
    ),
    env.DB.prepare(
      `UPDATE sync_events SET applied_at = datetime('now')
       WHERE user_id = ? AND event_id = ? AND applied_at IS NULL`,
    ).bind(userId, event.eventId),
    env.DB.prepare(
      `SELECT device_id, local_user_id, event_type, entity_id, payload,
              client_created_at
       FROM sync_event_receipts WHERE user_id = ? AND event_id = ?`,
    ).bind(userId, event.eventId),
  );
  return statements;
}

export type PullSyncEventsResult =
  | { expired: true; compactedThrough: number }
  | {
    expired: false;
    cursor: number;
    events: Record<string, unknown>[];
    hasMore: boolean;
  };

export async function pullSyncEvents(
  env: Env,
  userId: number,
  cursor: number,
  limit = 200,
): Promise<PullSyncEventsResult> {
  const rows = await env.DB.prepare(
    `WITH boundary AS (
       SELECT COALESCE((
         SELECT compacted_through FROM sync_event_watermarks WHERE user_id = ?
       ), 0) AS compacted_through
     ), page AS (
       SELECT id, event_id, device_id, local_user_id, event_type, entity_id,
              payload, client_created_at, created_at
       FROM sync_events, boundary
       WHERE user_id = ? AND id > ? AND ? >= boundary.compacted_through
       ORDER BY id ASC
       LIMIT ?
     )
     SELECT boundary.compacted_through, page.id, page.event_id, page.device_id,
            page.local_user_id, page.event_type, page.entity_id, page.payload,
            page.client_created_at, page.created_at
     FROM boundary LEFT JOIN page ON TRUE
     ORDER BY page.id ASC`,
  ).bind(userId, userId, cursor, cursor, limit + 1).all<Record<string, unknown>>();
  const records = rows.results ?? [];
  const compactedThrough = Number(records[0]?.compacted_through ?? 0);
  if (cursor < compactedThrough) return { expired: true, compactedThrough };
  const eventRows = records.filter((row) => row.id !== null && row.id !== undefined);
  const hasMore = eventRows.length > limit;
  const visible = eventRows.slice(0, limit).map((row) => {
    let payload: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(String(row.payload ?? '{}'));
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) payload = parsed;
    } catch {}
    return {
      serverSequence: Number(row.id),
      eventId: row.event_id,
      deviceId: row.device_id,
      localUserId: row.local_user_id,
      eventType: row.event_type,
      entityId: row.entity_id,
      payload,
      createdAt: Number(row.client_created_at),
      serverCreatedAt: row.created_at,
    };
  });
  const nextCursor = visible.length === 0 ? cursor : Number(visible[visible.length - 1].serverSequence);
  return { expired: false, cursor: nextCursor, events: visible, hasMore };
}

export async function currentSyncCursor(env: Env, userId: number): Promise<number> {
  const row = await env.DB.prepare(
    `SELECT MAX(
       COALESCE((SELECT MAX(id) FROM sync_events WHERE user_id = ?), 0),
       COALESCE((SELECT compacted_through FROM sync_event_watermarks WHERE user_id = ?), 0)
     ) AS cursor`,
  ).bind(userId, userId).first<{ cursor: number }>();
  return Number(row?.cursor ?? 0);
}
