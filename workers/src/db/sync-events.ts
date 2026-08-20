import type { Env } from '../lib/response';

export type IncomingSyncEvent = {
  eventId: string;
  deviceId: string;
  localUserId: string;
  eventType: string;
  entityId: string;
  payload: Record<string, unknown>;
  createdAt: number;
};

export async function appendSyncEvents(
  env: Env,
  userId: number,
  events: IncomingSyncEvent[],
): Promise<{ acceptedEventIds: string[]; cursor: number }> {
  if (events.length > 1 && events.every((event) => event.eventType === 'favorite.add')) {
    return appendFavoriteBatch(env, userId, events);
  }
  const acceptedEventIds: string[] = [];
  const device = events[0];
  for (const event of events) {
    const result = await env.DB.prepare(
      `INSERT OR IGNORE INTO sync_events
       (user_id, event_id, device_id, local_user_id, event_type, entity_id,
        payload, client_created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(
      userId,
      event.eventId,
      event.deviceId,
      event.localUserId,
      event.eventType,
      event.entityId,
      JSON.stringify(event.payload),
      event.createdAt,
    ).run();
    if ((result.meta?.changes ?? 0) === 1) {
      const sequence = Number(result.meta.last_row_id);
      try {
        await applySyncEvent(env, userId, event, sequence);
      } catch (error) {
        await env.DB.prepare('DELETE FROM sync_events WHERE user_id = ? AND event_id = ?')
          .bind(userId, event.eventId).run();
        throw error;
      }
      acceptedEventIds.push(event.eventId);
    } else {
      const existing = await env.DB.prepare(
        'SELECT event_id FROM sync_events WHERE user_id = ? AND event_id = ?',
      ).bind(userId, event.eventId).first<{ event_id: string }>();
      if (existing) acceptedEventIds.push(event.eventId);
    }
  }
  if (device) {
    await env.DB.prepare(
      `INSERT INTO sync_devices (user_id, device_id, local_user_id, last_seen_at)
       VALUES (?, ?, ?, datetime('now'))
       ON CONFLICT(user_id, device_id) DO UPDATE SET
         local_user_id = excluded.local_user_id,
         last_seen_at = datetime('now')`,
    ).bind(userId, device.deviceId, device.localUserId).run();
  }
  return { acceptedEventIds, cursor: await currentSyncCursor(env, userId) };
}

async function appendFavoriteBatch(
  env: Env,
  userId: number,
  events: IncomingSyncEvent[],
): Promise<{ acceptedEventIds: string[]; cursor: number }> {
  await env.DB.prepare(
    `INSERT OR IGNORE INTO playlists (id, user_id, name, position)
     VALUES ('love', ?, '我喜欢', 0)`,
  ).bind(userId).run();
  const eventStatements = events.map((event) => env.DB.prepare(
    `INSERT OR IGNORE INTO sync_events
     (user_id, event_id, device_id, local_user_id, event_type, entity_id,
      payload, client_created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(
    userId, event.eventId, event.deviceId, event.localUserId,
    event.eventType, event.entityId, JSON.stringify(event.payload), event.createdAt,
  ));
  const songStatements = events.map((event) => {
    const song = event.payload.song as Record<string, unknown>;
    return env.DB.prepare(
      `INSERT OR IGNORE INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, img,
        interval, hash, metadata, position, playlist_item_id)
       VALUES ('love', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
         COALESCE((SELECT MAX(position) + 1 FROM playlist_songs WHERE playlist_id = 'love' AND user_id = ?), 0), ?)`,
    ).bind(
      userId, String(song.name ?? '').slice(0, 256), String(song.singer ?? '').slice(0, 256),
      String(song.source ?? '').slice(0, 32), String(song.songmid ?? song.id ?? '').slice(0, 256),
      String(song.album ?? song.albumName ?? '').slice(0, 256), String(song.artwork ?? song.img ?? '').slice(0, 512),
      String(song.duration ?? 0), String(song.hash ?? '').slice(0, 256), JSON.stringify(song.meta ?? {}),
      userId, event.entityId,
    );
  });
  for (let index = 0; index < eventStatements.length; index += 100) {
    await env.DB.batch([...eventStatements.slice(index, index + 100), ...songStatements.slice(index, index + 100)]);
  }
  if (events[0]) {
    await env.DB.prepare(
      `INSERT INTO sync_devices (user_id, device_id, local_user_id, last_seen_at)
       VALUES (?, ?, ?, datetime('now'))
       ON CONFLICT(user_id, device_id) DO UPDATE SET last_seen_at = datetime('now')`,
    ).bind(userId, events[0].deviceId, events[0].localUserId).run();
  }
  return { acceptedEventIds: events.map((event) => event.eventId), cursor: await currentSyncCursor(env, userId) };
}

async function applySyncEvent(
  env: Env,
  userId: number,
  event: IncomingSyncEvent,
  sequence: number,
): Promise<void> {
  if (event.eventType === 'favorite.add') {
    const song = event.payload.song;
    if (!song || typeof song !== 'object' || Array.isArray(song)) return;
    const s = song as Record<string, unknown>;
    const songmid = String(s.songmid ?? s.id ?? '').slice(0, 256);
    const source = String(s.source ?? '').slice(0, 32);
    const tombstone = await env.DB.prepare(
      `SELECT server_sequence FROM sync_tombstones
       WHERE user_id = ? AND entity_type = ? AND entity_id = ?`,
    ).bind(userId, 'favorite', event.entityId).first<{ server_sequence: number }>();
    if (tombstone && Number(tombstone.server_sequence) >= sequence) return;
    await env.DB.prepare(
      `INSERT OR IGNORE INTO playlists (id, user_id, name, position)
       VALUES ('love', ?, '我喜欢', 0)`,
    ).bind(userId).run();
    await env.DB.prepare(
      `INSERT OR IGNORE INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, img,
         interval, hash, metadata, position, playlist_item_id)
       VALUES ('love', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          COALESCE((SELECT MAX(position) + 1 FROM playlist_songs WHERE playlist_id = 'love' AND user_id = ?), 0), ?)`,
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
    ).run();
    if (!tombstone || Number(tombstone.server_sequence) < sequence) {
      await env.DB.prepare(
        'DELETE FROM sync_tombstones WHERE user_id = ? AND entity_type = ? AND entity_id = ?',
      ).bind(userId, 'favorite', event.entityId).run();
    }
    return;
  }
  if (event.eventType === 'favorite.remove') {
    const song = event.payload.song;
    const songmid = song && typeof song === 'object'
      ? String((song as Record<string, unknown>).songmid ?? (song as Record<string, unknown>).id ?? '')
      : String(event.payload.songmid ?? event.entityId);
    const source = song && typeof song === 'object'
      ? String((song as Record<string, unknown>).source ?? '')
      : String(event.payload.source ?? '');
    await env.DB.prepare(
      "DELETE FROM playlist_songs WHERE playlist_id = 'love' AND user_id = ? AND songmid = ? AND source = ?",
    ).bind(userId, songmid, source ?? '').run();
    await writeTombstone(env, userId, 'favorite', event.entityId, sequence);
    return;
  }
  if (event.eventType === 'playlist.create') {
    await env.DB.prepare(
      `INSERT OR IGNORE INTO playlists (id, user_id, name, position)
       VALUES (?, ?, ?, COALESCE((SELECT MAX(position) + 1 FROM playlists WHERE user_id = ?), 0))`,
    ).bind(event.entityId, userId, String(event.payload.name ?? event.entityId), userId).run();
    return;
  }
  if (event.eventType === 'playlist.rename') {
    await env.DB.prepare(
      'UPDATE playlists SET name = ?, updated_at = datetime(\'now\') WHERE id = ? AND user_id = ?',
    ).bind(String(event.payload.name ?? event.entityId), event.entityId, userId).run();
    return;
  }
  if (event.eventType === 'playlist.delete') {
    await env.DB.prepare('DELETE FROM playlists WHERE id = ? AND user_id = ?')
      .bind(event.entityId, userId).run();
    await writeTombstone(env, userId, 'playlist', event.entityId, sequence);
    return;
  }
  if (event.eventType === 'playlist_item.add') {
    const playlistId = String(event.payload.playlistId ?? '');
    const song = event.payload.song;
    if (!playlistId || !song || typeof song !== 'object' || Array.isArray(song)) return;
    const s = song as Record<string, unknown>;
    await env.DB.prepare(
      `INSERT INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, img,
         interval, hash, metadata, position, playlist_item_id)
       SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          COALESCE((SELECT MAX(position) + 1 FROM playlist_songs WHERE playlist_id = ? AND user_id = ?), 0), ?
       WHERE EXISTS (SELECT 1 FROM playlists WHERE id = ? AND user_id = ?)`,
    ).bind(
      playlistId, userId, String(s.name ?? '').slice(0, 256),
      String(s.singer ?? '').slice(0, 256), String(s.source ?? '').slice(0, 32),
      String(s.songmid ?? s.id ?? '').slice(0, 256), String(s.album ?? '').slice(0, 256),
      String(s.artwork ?? '').slice(0, 512), String(s.duration ?? 0),
      String(s.hash ?? '').slice(0, 256), JSON.stringify(s.meta ?? {}),
       playlistId, userId, playlistId, userId, event.entityId,
    ).run();
    return;
  }
  if (event.eventType === 'playlist_item.remove') {
    const playlistId = String(event.payload.playlistId ?? '');
    const itemId = String(event.payload.playlistItemId ?? event.payload.songId ?? '');
    const source = String(event.payload.source ?? '');
    await env.DB.prepare(
      'DELETE FROM playlist_songs WHERE playlist_id = ? AND user_id = ? AND (playlist_item_id = ? OR (songmid = ? AND source = ?))',
    ).bind(playlistId, userId, itemId, itemId, source).run();
    return;
  }
  if (event.eventType === 'playlist_item.move') {
    const playlistId = String(event.payload.playlistId ?? '');
    const itemId = String(event.payload.playlistItemId ?? event.payload.songId ?? '');
    const source = String(event.payload.source ?? '');
    const position = Number(event.payload.index);
    if (!playlistId || !Number.isInteger(position) || position < 0) return;
    const item = await env.DB.prepare(
      `SELECT id FROM playlist_songs
       WHERE playlist_id = ? AND user_id = ? AND (playlist_item_id = ? OR (songmid = ? AND source = ?))
       ORDER BY position LIMIT 1`,
    ).bind(playlistId, userId, itemId, itemId, source).first<{ id: number }>();
    if (!item) return;
    await env.DB.prepare(
      `UPDATE playlist_songs SET position = position + 1
       WHERE playlist_id = ? AND user_id = ? AND position >= ? AND id != ?`,
    ).bind(playlistId, userId, position, item.id).run();
    await env.DB.prepare(
      'UPDATE playlist_songs SET position = ? WHERE id = ? AND user_id = ?',
    ).bind(position, item.id, userId).run();
    return;
  }
  if (event.eventType === 'rating.set') {
    const rating = Number(event.payload.rating);
    if (!Number.isInteger(rating) || rating < 0 || rating > 5) return;
    await env.DB.prepare(
      `INSERT INTO sync_ratings (user_id, song_id, rating, server_sequence)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, song_id) DO UPDATE SET
         rating = excluded.rating,
         server_sequence = excluded.server_sequence,
         updated_at = datetime('now')`,
    ).bind(userId, event.entityId, rating, sequence).run();
    return;
  }
  if (event.eventType === 'rating.remove') {
    await env.DB.prepare(
      'DELETE FROM sync_ratings WHERE user_id = ? AND song_id = ?',
    ).bind(userId, event.entityId).run();
    return;
  }
  if (event.eventType === 'setting.set') {
    const settings = await readEventState(env, `sync:settings:${userId}`);
    settings[event.entityId] = String(event.payload.value ?? '');
    await env.CACHE.put(`sync:settings:${userId}`, JSON.stringify(settings));
    return;
  }
  if (event.eventType === 'custom_source.upsert') {
    const sources = await readEventArray(env, `sync:sources:${userId}`);
    const source = event.payload.source;
    if (!source || typeof source !== 'object' || Array.isArray(source)) return;
    const next = sources.filter((item) => item?.id !== event.entityId);
    next.push(source as Record<string, unknown>);
    await env.CACHE.put(`sync:sources:${userId}`, JSON.stringify(next));
    return;
  }
  if (event.eventType === 'custom_source.remove') {
    const sources = await readEventArray(env, `sync:sources:${userId}`);
    await env.CACHE.put(
      `sync:sources:${userId}`,
      JSON.stringify(sources.filter((item) => item?.id !== event.entityId)),
    );
  }
}

export async function readEventState(env: Env, key: string): Promise<Record<string, string>> {
  try {
    const raw = await env.CACHE.get(key);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch (_) {
    return {};
  }
}

export async function readEventArray(env: Env, key: string): Promise<Record<string, unknown>[]> {
  try {
    const raw = await env.CACHE.get(key);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.filter((item) => item && typeof item === 'object') : [];
  } catch (_) {
    return [];
  }
}

async function writeTombstone(
  env: Env,
  userId: number,
  entityType: string,
  entityId: string,
  sequence: number,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO sync_tombstones (user_id, entity_type, entity_id, server_sequence)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
       server_sequence = excluded.server_sequence,
       created_at = datetime('now')`,
  ).bind(userId, entityType, entityId, sequence).run();
}

export async function pullSyncEvents(
  env: Env,
  userId: number,
  cursor: number,
  limit = 200,
): Promise<{ cursor: number; events: Record<string, unknown>[]; hasMore: boolean }> {
  const rows = await env.DB.prepare(
    `SELECT id, event_id, device_id, local_user_id, event_type, entity_id,
            payload, client_created_at, created_at
       FROM sync_events
      WHERE user_id = ? AND id > ?
      ORDER BY id ASC
      LIMIT ?`,
  ).bind(userId, cursor, limit + 1).all<Record<string, unknown>>();
  const records = rows.results ?? [];
  const hasMore = records.length > limit;
  const visible = records.slice(0, limit).map((row) => {
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
  return { cursor: nextCursor, events: visible, hasMore };
}

export async function currentSyncCursor(env: Env, userId: number): Promise<number> {
  const row = await env.DB.prepare(
    'SELECT COALESCE(MAX(id), 0) AS cursor FROM sync_events WHERE user_id = ?',
  ).bind(userId).first<{ cursor: number }>();
  return Number(row?.cursor ?? 0);
}
