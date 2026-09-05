import { Env, jsonResponse, requireJsonContentType, readJsonBody } from '../../lib/response';
import {
  appendSyncEvents,
  currentSyncCursor,
  pullSyncEvents,
  SyncEventIdConflictError,
} from '../../db/sync-events';
import {
  ensureSyncPayload,
  materializeSyncPayload,
  type PayloadRow,
  type SettingProjectionRow,
  type SourceProjectionRow,
} from '../../db/sync-payload';
import {
  getClientIP,
  RateLimiter,
  RateLimiterUnavailableError,
} from '../../middleware/rateLimit';
import { getUserId } from '../../utils/auth';

const EVENT_TYPES = new Set([
  'favorite.add', 'favorite.remove',
  'playlist.create', 'playlist.rename', 'playlist.delete',
  'playlist_item.add', 'playlist_item.remove', 'playlist_item.move',
  'rating.set', 'rating.remove',
  'setting.set', 'custom_source.upsert', 'custom_source.remove',
]);

function validId(value: unknown, max = 128): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= max;
}

function validPlaylistId(value: unknown): value is string {
  return validId(value) && !value.startsWith('__stage__:') &&
    !['favorites', 'recent', 'local'].includes(value);
}

function validSong(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const song = value as Record<string, unknown>;
  const songmid = song.songmid ?? song.id;
  return validId(song.name, 256) && validId(songmid, 256) &&
    typeof (song.source ?? '') === 'string' && String(song.source ?? '').length <= 32 &&
    typeof (song.singer ?? '') === 'string' && String(song.singer ?? '').length <= 256;
}

function validItemIdentity(payload: Record<string, unknown>): boolean {
  const itemId = payload.playlistItemId ?? payload.songId ?? payload.songmid;
  return validId(itemId, 256) && typeof (payload.source ?? '') === 'string' &&
    String(payload.source ?? '').length <= 32;
}

function validEventPayload(
  type: string,
  entityId: string,
  payload: Record<string, unknown>,
): boolean {
  switch (type) {
    case 'favorite.add':
      return validSong(payload.song);
    case 'favorite.remove': {
      const song = payload.song;
      return song == null
        ? validId(payload.songmid ?? entityId, 256) &&
            typeof (payload.source ?? '') === 'string' && String(payload.source ?? '').length <= 32
        : validSong(song);
    }
    case 'playlist.create':
    case 'playlist.rename':
      return validPlaylistId(entityId) && entityId !== 'love' && validId(payload.name, 128);
    case 'playlist.delete':
      return validPlaylistId(entityId) && entityId !== 'love';
    case 'playlist_item.add':
      return validPlaylistId(payload.playlistId) && validSong(payload.song);
    case 'playlist_item.remove':
      return validPlaylistId(payload.playlistId) && validItemIdentity(payload);
    case 'playlist_item.move':
      return validPlaylistId(payload.playlistId) && validItemIdentity(payload) &&
        Number.isSafeInteger(Number(payload.index)) && Number(payload.index) >= 0 &&
        Number(payload.index) <= 1_000_000;
    case 'rating.set':
      return Number.isInteger(Number(payload.rating)) && Number(payload.rating) >= 0 && Number(payload.rating) <= 5;
    case 'setting.set':
      return entityId.length <= 64 && typeof payload.value === 'string' && payload.value.length <= 4096;
    case 'custom_source.upsert':
      return !!payload.source && typeof payload.source === 'object' && !Array.isArray(payload.source) &&
        String((payload.source as Record<string, unknown>).id ?? '') === entityId;
    default:
      return true;
  }
}

export async function handleSyncPush(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const limiter = new RateLimiter(env.RATE_LIMITER, 'sync');
  try {
    const result = await limiter.check(getClientIP(request), [
      { key: 'ip', max: 120, windowSeconds: 60 },
      { key: `account:${userId}`, max: 60, windowSeconds: 60 },
    ]);
    if (!result.allowed) {
      const retryAfter = Math.max(1, Math.ceil((result.resetAt - Date.now()) / 1000));
      return jsonResponse(
        { error: 'sync_rate_limited', retryAfter },
        429,
        { 'Retry-After': String(retryAfter) },
      );
    }
  } catch (error) {
    if (error instanceof RateLimiterUnavailableError) {
      return jsonResponse(
        { error: '同步限流服务暂时不可用' },
        503,
        { 'Retry-After': '60' },
      );
    }
    throw error;
  }
  const contentError = requireJsonContentType(request);
  if (contentError) return contentError;
  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;
  const body = parsed.body;
  const deviceId = body.deviceId;
  const events = body.events;
  if (!validId(deviceId, 128) || !Array.isArray(events) || events.length > 200) {
    return jsonResponse({ error: '同步事件请求无效' }, 400);
  }
  const normalized = [];
  const eventIds = new Set<string>();
  for (const raw of events) {
    if (!raw || typeof raw !== 'object') return jsonResponse({ error: '同步事件无效' }, 400);
    const item = raw as Record<string, unknown>;
    const payload = item.payload;
    if (!validId(item.eventId, 128) || !validId(item.localUserId, 128) ||
        !validId(item.eventType, 64) || !EVENT_TYPES.has(item.eventType) ||
        !validId(item.entityId, 256) || !payload || typeof payload !== 'object' ||
        Array.isArray(payload) || !Number.isSafeInteger(Number(item.createdAt))) {
      return jsonResponse({ error: '同步事件字段无效' }, 400);
    }
    if (eventIds.has(item.eventId)) {
      return jsonResponse({ error: '同步事件 ID 重复' }, 400);
    }
    eventIds.add(item.eventId);
    const normalizedEvent = {
      eventId: item.eventId,
      deviceId,
      localUserId: item.localUserId,
      eventType: item.eventType,
      entityId: item.entityId,
      payload: payload as Record<string, unknown>,
      createdAt: Number(item.createdAt),
    };
    if (!validEventPayload(
      item.eventType as string,
      item.entityId as string,
      normalizedEvent.payload,
    )) {
      return jsonResponse({
        error: 'sync_event_payload_invalid',
        eventType: item.eventType,
        eventId: item.eventId,
        entityId: item.entityId,
      }, 400);
    }
    normalized.push(normalizedEvent);
  }
  try {
    const result = normalized.length === 0
      ? { acceptedEventIds: [], cursor: await currentSyncCursor(env, userId) }
      : await appendSyncEvents(env, userId, normalized);
    return jsonResponse(result);
  } catch (error) {
    if (error instanceof SyncEventIdConflictError) {
      return jsonResponse({
        error: 'sync_event_id_conflict',
        eventId: error.eventId,
      }, 409);
    }
    throw error;
  }
}

export async function handleSyncPull(request: Request, url: URL, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const cursor = Number(url.searchParams.get('cursor') ?? 0);
  if (!Number.isSafeInteger(cursor) || cursor < 0) {
    return jsonResponse({ error: 'cursor 无效' }, 400);
  }
  const result = await pullSyncEvents(env, userId, cursor);
  if (result.expired) {
    return jsonResponse({
      error: 'sync_cursor_expired',
      snapshotRequired: true,
      compactedThrough: result.compactedThrough,
    }, 409);
  }
  const { expired: _, ...page } = result;
  return jsonResponse(page);
}

export async function handleSyncAccountStatus(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const cursor = await currentSyncCursor(env, userId);
  const eventCount = await env.DB.prepare(
    'SELECT COUNT(*) AS count FROM sync_events WHERE user_id = ?',
  ).bind(userId).first<{ count: number }>();
  const favoriteCount = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM playlist_songs WHERE user_id = ? AND playlist_id = 'love'",
  ).bind(userId).first<{ count: number }>();
  return jsonResponse({
    cursor,
    hasCloudData: Number(eventCount?.count ?? 0) > 0,
    eventCount: Number(eventCount?.count ?? 0),
    favoriteCount: Number(favoriteCount?.count ?? 0),
  });
}

export async function handleSyncSnapshot(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  await ensureSyncPayload(env, userId);
  // D1 batch queries execute in one transaction, keeping the materialized
  // state and cursor on the same exact boundary. This avoids replaying a
  // non-idempotent move already present in the snapshot, or skipping an event
  // whose sequence was observed before its state.
  const results = await env.DB.batch([
    env.DB.prepare(
      `SELECT MAX(
         COALESCE((SELECT MAX(id) FROM sync_events WHERE user_id = ?), 0),
         COALESCE((SELECT compacted_through FROM sync_event_watermarks WHERE user_id = ?), 0)
       ) AS cursor`,
    ).bind(userId, userId),
    env.DB.prepare(
      `SELECT id, name, position FROM playlists
       WHERE user_id = ? AND id NOT LIKE '__stage__:%'
       ORDER BY position`,
    ).bind(userId),
    env.DB.prepare(
      `SELECT playlist_id, playlist_item_id, id, name, singer, source, songmid,
              album_name, img, interval, hash, metadata, position
       FROM playlist_songs
       WHERE user_id = ? AND playlist_id NOT LIKE '__stage__:%'
       ORDER BY playlist_id, position`,
    ).bind(userId),
    env.DB.prepare(
      'SELECT settings, sources, base_sequence FROM user_sync_payloads WHERE user_id = ?',
    ).bind(userId),
    env.DB.prepare(
      `SELECT key, value FROM sync_setting_projections
       WHERE user_id = ? AND server_sequence > COALESCE((
         SELECT base_sequence FROM user_sync_payloads WHERE user_id = ?
       ), 0)`,
    ).bind(userId, userId),
    env.DB.prepare(
      `SELECT id, source, deleted FROM sync_source_projections
       WHERE user_id = ? AND server_sequence > COALESCE((
         SELECT base_sequence FROM user_sync_payloads WHERE user_id = ?
       ), 0)`,
    ).bind(userId, userId),
    env.DB.prepare(
      'SELECT song_id, rating FROM sync_ratings WHERE user_id = ?',
    ).bind(userId),
  ]);
  const cursor = Number((results[0].results?.[0] as { cursor?: number } | undefined)?.cursor ?? 0);
  const playlists = (results[1].results ?? []) as Array<{
    id: string;
    name: string;
    position: number;
  }>;
  const songs = (results[2].results ?? []) as Record<string, unknown>[];
  const grouped = new Map<string, Record<string, unknown>[]>();
  for (const row of songs) {
    const metadata = typeof row.metadata === 'string'
      ? (() => { try { return JSON.parse(row.metadata as string); } catch { return {}; } })()
      : {};
    const list = grouped.get(String(row.playlist_id)) ?? [];
    list.push({
      id: row.id,
      name: row.name,
      singer: row.singer,
      source: row.source,
      songmid: row.songmid,
      album: row.album_name,
      artwork: row.img,
      duration: Number.parseInt(String(row.interval ?? 0), 10) || 0,
      hash: row.hash,
      playlistItemId: row.playlist_item_id,
      meta: metadata,
    });
    grouped.set(String(row.playlist_id), list);
  }
  const payloadRow = results[3].results?.[0] as PayloadRow | undefined;
  if (!payloadRow) throw new Error('sync payload missing after initialization');
  const payload = materializeSyncPayload(
    payloadRow,
    (results[4].results ?? []) as SettingProjectionRow[],
    (results[5].results ?? []) as SourceProjectionRow[],
  );
  const ratings = (results[6].results ?? []) as Array<{ song_id: string; rating: number }>;
  return jsonResponse({
    version: 1,
    cursor,
    playlists: playlists.map((playlist) => ({
      id: playlist.id,
      name: playlist.name,
      position: playlist.position,
      songs: grouped.get(playlist.id) ?? [],
    })),
    settings: payload.settings,
    sources: payload.sources,
    ratings: Object.fromEntries(ratings.map((row) => [row.song_id, row.rating])),
  });
}
