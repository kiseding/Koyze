import { Env, jsonResponse, requireJsonContentType, readJsonBody } from '../../lib/response';
import { insertStageSongs } from '../../db/playlist-staging';
import { getSyncRevision } from '../../db/sync-state';
import { getUserId } from '../../utils/auth';
import type { SongInfo } from '../../utils/types';

// GET /api/user/sync/state — return settings + custom sources + revision (from KV)
export async function handleSyncStateGet(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const settings = await _readKvJson(env, `sync:settings:${userId}`);
  const rawSources = await _readKvJson(env, `sync:sources:${userId}`);
  const fallbackTime = new Date().toISOString();
  const sources = Array.isArray(rawSources)
    ? rawSources.map((source: any) => ({
        ...source,
        createdAt: source?.createdAt || source?.updatedAt || fallbackTime,
        updatedAt: source?.updatedAt || source?.createdAt || fallbackTime,
      }))
    : [];
  const revision = await getSyncRevision(env, userId);
  return jsonResponse({ settings, sources, revision, syncProtocol: 1 });
}

// POST /api/user/sync/state — atomically replace settings + custom sources in KV
export async function handleSyncStateSet(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;
  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;

  const baseRevision = Number(parsed.body.baseRevision);
  const settings = parsed.body.settings;
  const sources = parsed.body.sources;
  if (!Number.isInteger(baseRevision) ||
      (settings != null && typeof settings !== 'object') ||
      (sources != null && !Array.isArray(sources))) {
    return jsonResponse({ error: '同步状态数据无效' }, 400);
  }

  const cleanSettings: Record<string, string> = {};
  if (settings && typeof settings === 'object') {
    for (const [k, v] of Object.entries(settings as Record<string, unknown>)) {
      if (typeof k === 'string' && k.length > 0 && k.length <= 64 &&
          (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean')) {
        cleanSettings[k.slice(0, 64)] = String(v);
      }
    }
  }

  const cleanSources: any[] = [];
  if (Array.isArray(sources)) {
    const seen = new Set<string>();
    for (let i = 0; i < sources.length && i < 200; i++) {
      const s = sources[i] as any;
      const id = String(s?.id || '').slice(0, 128);
      if (!id || id.startsWith('__stage__:') || seen.has(id)) continue;
      seen.add(id);
      cleanSources.push({
        id,
        name: String(s?.name || '').slice(0, 128),
        description: String(s?.description || '').slice(0, 1024),
        version: String(s?.version || '').slice(0, 32),
        author: String(s?.author || '').slice(0, 128),
        homepage: String(s?.homepage || '').slice(0, 512),
        script: String(s?.script || '').slice(0, 2 * 1024 * 1024),
        isEnabled: s?.isEnabled ? true : false,
        createdAt: String(s?.createdAt || s?.updatedAt || new Date().toISOString()),
        updatedAt: String(s?.updatedAt || s?.createdAt || new Date().toISOString()),
      });
    }
  }

  // Check revision (KV is eventually consistent, so we still gate on D1 revision)
  const currentRevision = await getSyncRevision(env, userId);
  if (currentRevision !== baseRevision) {
    return jsonResponse({ error: 'revision_conflict', currentRevision }, 409);
  }

  // Stage KV first. Only the request that wins the D1 CAS promotes staged KV
  // to live keys, so failed 409 writers cannot overwrite the winning state.
  const pendingId = crypto.randomUUID();
  const pendingSettingsKey = `sync:pending:settings:${userId}:${pendingId}`;
  const pendingSourcesKey = `sync:pending:sources:${userId}:${pendingId}`;
  await env.CACHE.put(pendingSettingsKey, JSON.stringify(cleanSettings), { expirationTtl: 3600 });
  await env.CACHE.put(pendingSourcesKey, JSON.stringify(cleanSources), { expirationTtl: 3600 });
  const bumped = await env.DB.prepare(
    `UPDATE user_sync_state SET revision = revision + 1, updated_at = datetime('now') WHERE user_id = ? AND revision = ?`,
  ).bind(userId, baseRevision).run();
  if ((bumped.meta?.changes ?? 0) !== 1) {
    await Promise.allSettled([
      env.CACHE.delete(pendingSettingsKey),
      env.CACHE.delete(pendingSourcesKey),
    ]);
    return jsonResponse({ error: 'revision_conflict', currentRevision: await getSyncRevision(env, userId) }, 409);
  }
  await env.CACHE.put(`sync:settings:${userId}`, JSON.stringify(cleanSettings));
  await env.CACHE.put(`sync:sources:${userId}`, JSON.stringify(cleanSources));
  await Promise.allSettled([
    env.CACHE.delete(pendingSettingsKey),
    env.CACHE.delete(pendingSourcesKey),
  ]);
  return jsonResponse({ ok: true, revision: baseRevision + 1 });
}

async function _readKvJson(env: Env, key: string): Promise<any> {
  try {
    const raw = await env.CACHE.get(key);
    if (!raw) return raw === null ? (key.includes('settings') ? {} : []) : null;
    return JSON.parse(raw);
  } catch {
    return key.includes('settings') ? {} : [];
  }
}

function stagePrefix(operationId: string): string {
  return `__stage__:sync:${operationId}:`;
}

function validOperationId(value: string): boolean {
  return /^[A-Za-z0-9-]{8,64}$/.test(value);
}

export async function handleSyncStage(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;
  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;

  const operationId = String(parsed.body.operationId || '');
  const targetId = String(parsed.body.id || '').slice(0, 128);
  const name = String(parsed.body.name || '').trim().slice(0, 128);
  const position = Number(parsed.body.position) || 0;
  const songs = Array.isArray(parsed.body.songs) ? parsed.body.songs as SongInfo[] : null;
  const reset = parsed.body.reset === true;
  if (!validOperationId(operationId) || !targetId || !name || songs == null ||
      songs.length > 2000 || targetId.startsWith('__stage__:') ||
      (targetId !== 'love' && ['favorites', 'recent', 'local'].includes(targetId))) {
    return jsonResponse({ error: '同步暂存数据无效' }, 400);
  }

  const stageId = stagePrefix(operationId) + targetId;
  if (reset) {
    await env.DB.prepare(
      "DELETE FROM playlists WHERE user_id = ? AND substr(id, 1, ?) = ? AND created_at < datetime('now', '-1 hour')",
    ).bind(userId, '__stage__:sync:'.length, '__stage__:sync:').run();
    await env.DB.prepare('DELETE FROM playlists WHERE id = ? AND user_id = ?')
      .bind(stageId, userId).run();
    await env.DB.prepare(
      'INSERT INTO playlists (id, user_id, name, position, source, source_id) VALUES (?, ?, ?, ?, ?, ?)',
    ).bind(stageId, userId, name, position, '', '').run();
  } else {
    const existing = await env.DB.prepare(
      'SELECT id FROM playlists WHERE id = ? AND user_id = ?',
    ).bind(stageId, userId).first();
    if (!existing) return jsonResponse({ error: '同步暂存会话不存在' }, 409);
  }

  const max = await env.DB.prepare(
    'SELECT MAX(position) AS m FROM playlist_songs WHERE playlist_id = ? AND user_id = ?',
  ).bind(stageId, userId).first<{ m: number | null }>();
  await insertStageSongs(
    env,
    stageId,
    userId,
    songs,
    (max?.m ?? -1) + 1,
    targetId === 'love',
  );
  return jsonResponse({ ok: true, staged: songs.length });
}

export async function handleSyncAbort(request: Request, url: URL, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const operationId = url.searchParams.get('operationId') || '';
  if (!validOperationId(operationId)) {
    return jsonResponse({ error: '同步暂存会话无效' }, 400);
  }
  await _cleanupStaging(env, userId, stagePrefix(operationId));
  return jsonResponse({ ok: true });
}

export async function handleSyncCommit(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;
  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;
  const operationId = String(parsed.body.operationId || '');
  const baseRevision = Number(parsed.body.baseRevision);
  const manifest = Array.isArray(parsed.body.manifest) ? parsed.body.manifest : null;
  if (!validOperationId(operationId) || !Number.isInteger(baseRevision) || manifest == null) {
    return jsonResponse({ error: '同步提交数据无效' }, 400);
  }
  const prefix = stagePrefix(operationId);
  const prefixLength = prefix.length;
  const expected = new Map<string, number>();
  for (const raw of manifest) {
    const id = String((raw as any)?.id || '');
    const count = Number((raw as any)?.count);
    if (!id || id.startsWith('__stage__:') || !Number.isInteger(count) || count < 0 || expected.has(id)) {
      return jsonResponse({ error: '同步提交清单无效' }, 400);
    }
    expected.set(id, count);
  }
  const staged = await env.DB.prepare(
    `SELECT substr(p.id, ?) AS id, COUNT(s.id) AS count
     FROM playlists p
     LEFT JOIN playlist_songs s ON s.playlist_id = p.id AND s.user_id = p.user_id
     WHERE p.user_id = ? AND substr(p.id, 1, ?) = ?
     GROUP BY p.id`,
  ).bind(prefixLength + 1, userId, prefixLength, prefix).all<{ id: string; count: number }>();
  const actual = new Map((staged.results || []).map((row) => [row.id, Number(row.count)]));
  if (actual.size !== expected.size ||
      [...expected].some(([id, count]) => actual.get(id) !== count)) {
    await _cleanupStaging(env, userId, prefix);
    return jsonResponse({ error: '同步暂存会话不存在' }, 409);
  }
  await getSyncRevision(env, userId);
  const guard = 'EXISTS (SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?)';
  let results: D1Result[];
  try {
    results = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO playlists (id, user_id, name, position, source, source_id)
       SELECT substr(id, ?), user_id, name, position, '', ''
       FROM playlists
        WHERE user_id = ? AND substr(id, 1, ?) = ? AND ${guard}
       ON CONFLICT(id, user_id) DO UPDATE SET
         name = excluded.name, position = excluded.position,
         source = excluded.source, source_id = excluded.source_id,
         updated_at = datetime('now')`,
    ).bind(prefixLength + 1, userId, prefixLength, prefix, userId, baseRevision),
    env.DB.prepare(
      `DELETE FROM playlist_songs
       WHERE user_id = ? AND playlist_id NOT LIKE '__stage__:%' AND ${guard}`,
    ).bind(userId, userId, baseRevision),
    env.DB.prepare(
      `INSERT OR IGNORE INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, album_id,
        img, interval, types, hash, str_media_mid, copyright_id, metadata, position)
       SELECT substr(playlist_id, ?), user_id, name, singer, source, songmid,
        album_name, album_id, img, interval, types, hash, str_media_mid,
        copyright_id, metadata, position
       FROM playlist_songs
        WHERE user_id = ? AND substr(playlist_id, 1, ?) = ? AND ${guard}`,
     ).bind(prefixLength + 1, userId, prefixLength, prefix, userId, baseRevision),
    env.DB.prepare(
      `DELETE FROM playlists
       WHERE user_id = ? AND id NOT LIKE '__stage__:%'
         AND id NOT IN (
            SELECT substr(id, ?) FROM playlists WHERE user_id = ? AND substr(id, 1, ?) = ?
         ) AND ${guard}`,
     ).bind(userId, prefixLength + 1, userId, prefixLength, prefix, userId, baseRevision),
    env.DB.prepare(
       `DELETE FROM playlists WHERE user_id = ? AND substr(id, 1, ?) = ? AND ${guard}`,
     ).bind(userId, prefixLength, prefix, userId, baseRevision),
    env.DB.prepare(
      `UPDATE user_sync_state
       SET revision = revision + 1, updated_at = datetime('now')
       WHERE user_id = ? AND revision = ?`,
    ).bind(userId, baseRevision),
    ]);
  } catch (error) {
    await _cleanupStaging(env, userId, prefix);
    throw error;
  }
  const commit = results[results.length - 1];
  if ((commit.meta?.changes ?? 0) !== 1) {
    await _cleanupStaging(env, userId, prefix);
    return jsonResponse({
      error: 'revision_conflict',
      currentRevision: await getSyncRevision(env, userId),
    }, 409);
  }
  return jsonResponse({ ok: true, revision: baseRevision + 1 });
}

async function _cleanupStaging(env: Env, userId: number, prefix: string): Promise<void> {
  try {
    await env.DB.prepare(
      'DELETE FROM playlists WHERE user_id = ? AND substr(id, 1, ?) = ?',
    ).bind(userId, prefix.length, prefix).run();
  } catch {}
}
