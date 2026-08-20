import { Env, jsonResponse, requireJsonContentType, readJsonBody } from '../../lib/response';
import { appendSyncEvents, currentSyncCursor, pullSyncEvents, readEventArray, readEventState } from '../../db/sync-events';
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

function validEventPayload(type: string, payload: Record<string, unknown>): boolean {
  switch (type) {
    case 'favorite.add':
    case 'playlist_item.add':
      return !!payload.song && typeof payload.song === 'object' && !Array.isArray(payload.song);
    case 'playlist.create':
      return typeof payload.name === 'string' && payload.name.length > 0;
    case 'playlist_item.remove':
    case 'playlist_item.move':
      return validId(payload.playlistId) && validId(payload.songmid) && validId(payload.source);
    case 'rating.set':
      return Number.isInteger(Number(payload.rating)) && Number(payload.rating) >= 0 && Number(payload.rating) <= 5;
    case 'setting.set':
      return typeof payload.value === 'string' && payload.value.length <= 4096;
    case 'custom_source.upsert':
      return !!payload.source && typeof payload.source === 'object' && !Array.isArray(payload.source);
    default:
      return true;
  }
}

export async function handleSyncPush(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
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
    const normalizedEvent = {
      eventId: item.eventId,
      deviceId,
      localUserId: item.localUserId,
      eventType: item.eventType,
      entityId: item.entityId,
      payload: payload as Record<string, unknown>,
      createdAt: Number(item.createdAt),
    };
    if (!validEventPayload(item.eventType as string, normalizedEvent.payload)) {
      return jsonResponse({
        error: 'sync_event_payload_invalid',
        eventType: item.eventType,
        eventId: item.eventId,
        entityId: item.entityId,
      }, 400);
    }
    normalized.push(normalizedEvent);
  }
  const result = normalized.length === 0
    ? { acceptedEventIds: [], cursor: await currentSyncCursor(env, userId) }
    : await appendSyncEvents(env, userId, normalized);
  return jsonResponse(result);
}

export async function handleSyncPull(request: Request, url: URL, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const cursor = Number(url.searchParams.get('cursor') ?? 0);
  if (!Number.isSafeInteger(cursor) || cursor < 0) {
    return jsonResponse({ error: 'cursor 无效' }, 400);
  }
  return jsonResponse(await pullSyncEvents(env, userId, cursor));
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
  const playlists = await env.DB.prepare(
    `SELECT id, name, position FROM playlists
     WHERE user_id = ? AND id NOT LIKE '__stage__:%'
     ORDER BY position`,
  ).bind(userId).all<{ id: string; name: string; position: number }>();
  const songs = await env.DB.prepare(
    `SELECT playlist_id, playlist_item_id, id, name, singer, source, songmid,
            album_name, img, interval, hash, metadata, position
     FROM playlist_songs
     WHERE user_id = ? AND playlist_id NOT LIKE '__stage__:%'
     ORDER BY playlist_id, position`,
  ).bind(userId).all<Record<string, unknown>>();
  const grouped = new Map<string, Record<string, unknown>[]>();
  for (const row of songs.results ?? []) {
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
  const settings = await readEventState(env, `sync:settings:${userId}`);
  const sources = await readEventArray(env, `sync:sources:${userId}`);
  const ratings = await env.DB.prepare(
    'SELECT song_id, rating FROM sync_ratings WHERE user_id = ?',
  ).bind(userId).all<{ song_id: string; rating: number }>();
  return jsonResponse({
    version: 1,
    cursor: await currentSyncCursor(env, userId),
    playlists: (playlists.results ?? []).map((playlist) => ({
      id: playlist.id,
      name: playlist.name,
      position: playlist.position,
      songs: grouped.get(playlist.id) ?? [],
    })),
    settings,
    sources,
    ratings: Object.fromEntries((ratings.results ?? []).map((row) => [row.song_id, row.rating])),
  });
}
