import { Env, jsonResponse, requireJsonContentType, readJsonBody } from '../../lib/response';
import { getUserId } from '../../utils/auth';
import { fetchAndRematch } from '../playlist-import';
import type { SongInfo } from '../../utils/types';
import {
  applyLegacyPlaylistMutation,
  type LegacyPlaylistMutation,
  songIdentity,
  writePlaylistAtRevision,
} from '../../db/playlist-staging';
import { getSyncRevision } from '../../db/sync-state';

// P1-4: D1 is now the single source of truth for love-list / playlists. KV
// is a read-through cache, populated on save and on cache miss. This removes
// the previous dual-write race (KV first, D1 in waitUntil) that could leave
// KV ahead of D1, behind it, or missing in concurrent saves.

async function readLoveListFromD1(env: Env, userId: number): Promise<any[]> {
  const songs = await env.DB.prepare(
    "SELECT name, singer, source, songmid, album_name, album_id, img, interval, types, hash, metadata FROM playlist_songs WHERE playlist_id = 'love' AND user_id = ? ORDER BY position"
  ).bind(userId).all<any>();
  return (songs.results || []).map((s: any) => {
    let meta: any = {};
    try { meta = JSON.parse(s.metadata || '{}'); } catch { /* corrupted */ }
    // B1: types 可能因截断/损坏无法解析，回退为空数组。
    let types: any[] = [];
    try { types = JSON.parse(s.types || '[]'); } catch { /* corrupted */ }
    return {
      name: s.name, singer: s.singer, source: s.source,
      songmid: s.songmid, albumName: s.album_name, albumId: s.album_id,
      img: s.img, interval: s.interval,
      types, hash: s.hash,
      mrcUrl: meta.mrcUrl || '', lrcUrl: meta.lrcUrl || '', trcUrl: meta.trcUrl || '',
    };
  });
}

async function readLoveList(env: Env, userId: number, _ctx: ExecutionContext): Promise<any[]> {
  return readLoveListFromD1(env, userId);
}

function parseBaseRevision(value: unknown): number | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0
    ? value
    : null;
}

function isSongList(value: unknown): value is SongInfo[] {
  return Array.isArray(value) && value.every((raw) => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return false;
    const song = raw as Record<string, unknown>;
    return typeof song.name === 'string' && song.name.length > 0 && song.name.length <= 256 &&
      String(song.singer ?? '').length <= 256 &&
      String(song.source ?? '').length <= 32 &&
      String(song.songmid ?? '').length <= 256;
  });
}

// GET /api/user/list — return loveList + imported playlists
export async function handleUserPlaylist(request: Request, url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const startRevision = await getSyncRevision(env, userId);

  const loveList = await readLoveList(env, userId, ctx);

  // P2-2: cap rows to keep the response bounded for power users.
  const playlists = await env.DB.prepare(
    "SELECT * FROM playlists WHERE user_id = ? AND id != 'love' AND id NOT LIKE '__stage__:%' ORDER BY position LIMIT 200"
  ).bind(userId).all<any>();
  const playlistTotal = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM playlists WHERE user_id = ? AND id != 'love' AND id NOT LIKE '__stage__:%'"
  ).bind(userId).first<{ count: number }>();

  let allSongs: any[] = [];
  if (playlists.results?.length) {
    const songsResult = await env.DB.prepare(
      "SELECT * FROM playlist_songs WHERE user_id = ? AND playlist_id != ? AND playlist_id NOT LIKE '__stage__:%' ORDER BY playlist_id, position LIMIT 20000"
    ).bind(userId, 'love').all<any>();
    allSongs = songsResult.results || [];
  }
  const songTotal = await env.DB.prepare(
    "SELECT COUNT(*) AS count FROM playlist_songs WHERE user_id = ? AND playlist_id != 'love' AND playlist_id NOT LIKE '__stage__:%'"
  ).bind(userId).first<{ count: number }>();

  const songsByPlaylist = new Map<string, any[]>();
  for (const s of allSongs) {
    const list = songsByPlaylist.get(s.playlist_id as string) || [];
    list.push(s);
    songsByPlaylist.set(s.playlist_id as string, list);
  }

  const userList: any[] = [];
  for (const pl of (playlists.results || [])) {
    const songs = songsByPlaylist.get(pl.id as string) || [];
    const list = songs.map((s: any) => {
      let meta: any = {};
      try { meta = JSON.parse(s.metadata || '{}'); } catch { /* corrupted */ }
      // B1: types 可能因截断/损坏无法解析，回退为空数组。
      let types: any[] = [];
      try { types = JSON.parse(s.types || '[]'); } catch { /* corrupted */ }
      return {
        name: s.name, singer: s.singer, source: s.source,
        songmid: s.songmid, albumName: s.album_name, albumId: s.album_id,
        img: s.img, interval: s.interval,
        types, hash: s.hash,
        mrcUrl: meta.mrcUrl || '', lrcUrl: meta.lrcUrl || '', trcUrl: meta.trcUrl || '',
      };
    });
    userList.push({
      id: pl.id, name: pl.name,
      source: pl.source, source_id: pl.source_id,
      list,
    });
  }

  const revision = await getSyncRevision(env, userId);
  if (revision !== startRevision) {
    return jsonResponse({ error: 'revision_conflict', currentRevision: revision }, 409);
  }
  const complete = Number(playlistTotal?.count ?? 0) <= 200 && Number(songTotal?.count ?? 0) <= 20000;
  return jsonResponse({
    loveList,
    userList,
    revision,
    syncProtocol: 1,
    complete,
    playlistTotal: Number(playlistTotal?.count ?? 0),
    songTotal: Number(songTotal?.count ?? 0),
  });
}

export async function handleUserSyncStatus(request: Request, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);
  const revision = await getSyncRevision(env, userId);
  return jsonResponse({ revision, syncProtocol: 1 });
}

// POST /api/user/list — save loveList / rename playlists / append playlist songs.
// userList entries with mode:'append' merge songs into an existing playlist
// (or create it) instead of replacing it, so a large playlist can be synced in
// byte-bounded chunks within the Worker request limit.
export async function handleUserPlaylistSave(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;

  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;
  const body = parsed.body as {
    loveList?: unknown;
    pls?: Array<{ id?: unknown; name?: unknown }>;
    userList?: Array<{ id?: unknown; name?: unknown; list?: unknown; mode?: unknown; position?: unknown }>;
    append?: unknown;
    baseRevision?: unknown;
  };
  const { loveList, pls, userList, append } = body;
  const baseRevision = parseBaseRevision(body.baseRevision);
  if (baseRevision == null) {
    return jsonResponse({ error: 'baseRevision 无效' }, 400);
  }
  if (pls != null && !Array.isArray(pls)) {
    return jsonResponse({ error: '歌单名称数据无效' }, 400);
  }
  const plsArray = Array.isArray(pls) ? pls : [];
  const hasLoveList = Object.prototype.hasOwnProperty.call(body, 'loveList');
  if (hasLoveList && !isSongList(loveList)) {
    return jsonResponse({ error: '收藏数据无效' }, 400);
  }
  const loveArray = hasLoveList ? loveList as SongInfo[] : [];

  const mutations: LegacyPlaylistMutation[] = [];
  for (const p of plsArray) {
    const pid = String(p?.id || '');
    const name = typeof p?.name === 'string' ? p.name.trim() : '';
    if (!pid || pid.length > 128 || pid.startsWith('__stage__:') ||
        (pid !== 'love' && (!name || name.length > 128))) {
      return jsonResponse({ error: '歌单名称数据无效' }, 400);
    }
    if (pid !== 'love') {
      mutations.push({ id: pid, name, position: 0, mode: 'rename' });
    }
  }

  if (userList != null) {
    if (!Array.isArray(userList) || userList.length > 200) {
      return jsonResponse({ error: '歌单数据无效或数量超限' }, 400);
    }
    let validatedSongCount = 0;
    const ids = new Set<string>();
    for (let index = 0; index < userList.length; index += 1) {
      const raw = userList[index];
      const rawId = String(raw?.id || '');
      const id = rawId.slice(0, 128);
      const rawName = String(raw?.name || '').trim();
      const name = rawName.slice(0, 128);
      const list = raw?.list;
      const mode = raw?.mode == null ? 'replace' : raw.mode;
      const position = raw?.position == null ? index + 1 : Number(raw.position);
      if (!id || rawId.length > 128 || id === 'love' || id === 'favorites' ||
          id === 'recent' || id === 'local' || id.startsWith('__stage__:') ||
          !name || rawName.length > 128 || !isSongList(list) || ids.has(id) ||
          (mode !== 'replace' && mode !== 'append') ||
          !Number.isSafeInteger(position) || position < 0 || position > 1_000_000) {
        return jsonResponse({ error: '歌单数据无效' }, 400);
      }
      ids.add(id);
      validatedSongCount += list.length;
      if (validatedSongCount > 20000) {
        return jsonResponse({ error: '歌曲数量超限' }, 400);
      }
      mutations.push({
        id,
        name,
        position,
        mode,
        songs: list,
      });
    }
  }
  if (hasLoveList && (loveArray.length > 0 || !append)) {
    mutations.push({
      id: 'love',
      name: '我喜欢',
      position: 0,
      mode: 'replace',
      songs: loveArray,
      deduplicate: true,
    });
  }
  if (mutations.length === 0) {
    return jsonResponse({ ok: true, saved: 0, revision: await getSyncRevision(env, userId) });
  }

  try {
    const result = await applyLegacyPlaylistMutation(
      env,
      userId,
      baseRevision,
      mutations,
    );
    if (!result) {
      return jsonResponse({
        error: 'revision_conflict',
        baseRevision,
        currentRevision: await getSyncRevision(env, userId),
      }, 409);
    }
    if (hasLoveList) {
      try { ctx.waitUntil(env.CACHE.delete(`v2:love:${userId}`)); } catch {}
    }
    return jsonResponse({ ok: true, saved: loveArray.length, revision: result.revision });
  } catch (error) {
    console.error('[playlist:legacy-commit]', error);
    return jsonResponse({ error: '保存失败' }, 500);
  }
}

// POST /api/user/love/add — incrementally add songs to the love list
// without sending the entire list back. Solves the 256KB body limit
// when the love list grows past ~1000 songs.
// Body: { songs: SongInfo[] }
export async function handleLoveAdd(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;

  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;
  const baseRevision = parseBaseRevision(parsed.body.baseRevision);
  if (baseRevision == null) return jsonResponse({ error: 'baseRevision 无效' }, 400);
  if (!isSongList(parsed.body.songs)) return jsonResponse({ error: '歌曲数据无效' }, 400);
  const songs = parsed.body.songs;
  if (songs.length === 0) return jsonResponse({ error: '无歌曲' }, 400);
  if (songs.length > 500) return jsonResponse({ error: '单批最多500首' }, 400);

  // Read the full source-aware identity from D1 to deduplicate.
  const existing = await env.DB.prepare(
    "SELECT songmid, source FROM playlist_songs WHERE playlist_id = 'love' AND user_id = ?"
  ).bind(userId).all<{ songmid: string; source: string }>();
  const existingMids = new Set((existing.results || []).map(r => songIdentity(r.songmid, r.source)));

  // Filter out duplicates and insert.
  const seen = new Set<string>();
  const toInsert: SongInfo[] = [];
  for (const s of songs) {
    const mid = String(s.songmid || '').slice(0, 256);
    const src = String(s.source || '').slice(0, 32);
    const key = songIdentity(mid, src);
    if (!mid || existingMids.has(key) || seen.has(key)) continue;
    seen.add(key);
    // B4: 保存与去重 key 使用相同的截断值，保证 ON CONFLICT 索引一致。
    toInsert.push({ ...s, songmid: mid, source: src });
  }

  if (toInsert.length === 0) {
    return jsonResponse({ ok: true, added: 0, revision: await getSyncRevision(env, userId), message: '全部已存在' });
  }
  let result;
  try {
    result = await applyLegacyPlaylistMutation(env, userId, baseRevision, [{
      id: 'love',
      name: '我喜欢',
      position: 0,
      mode: 'append',
      songs: toInsert,
      deduplicate: true,
    }]);
  } catch (error) {
    console.error('[love:add]', error);
    return jsonResponse({ error: '保存失败' }, 500);
  }
  if (!result) {
    return jsonResponse({
      error: 'revision_conflict',
      currentRevision: await getSyncRevision(env, userId),
    }, 409);
  }

  // Bust the KV cache so the next GET fetches fresh data from D1.
  try { ctx.waitUntil(env.CACHE.delete(`v2:love:${userId}`)); } catch {}

  return jsonResponse({ ok: true, added: result.insertedSongs, revision: result.revision });
}

// POST /api/user/love/remove — incrementally remove songs from the love list.
// Body: { songs: [{ songmid, source }] } or { keys: ["songmid|source", ...] }
export async function handleLoveRemove(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;

  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;
  const body = parsed.body as { songs?: unknown; keys?: unknown; baseRevision?: unknown };
  const baseRevision = parseBaseRevision(body.baseRevision);
  if (baseRevision == null) return jsonResponse({ error: 'baseRevision 无效' }, 400);
  const keys: string[] = [];
  if (Array.isArray(body.songs)) {
    for (const s of body.songs) {
      if (!s || typeof s !== 'object' || Array.isArray(s)) {
        return jsonResponse({ error: '歌曲数据无效' }, 400);
      }
      const mid = String((s as any).songmid || '');
      const src = String((s as any).source || '');
      if (!mid || mid.length > 256 || src.length > 32 || mid.includes('|') || src.includes('|')) {
        return jsonResponse({ error: '歌曲数据无效' }, 400);
      }
      keys.push(mid + '|' + src);
    }
  }
  if (Array.isArray(body.keys)) {
    for (const key of body.keys) {
      if (typeof key !== 'string' || key.length === 0 || key.length > 289 ||
          !key.includes('|')) {
        return jsonResponse({ error: '歌曲数据无效' }, 400);
      }
      keys.push(key);
    }
  }
  const uniqueKeys = [...new Set(keys)];
  if (uniqueKeys.length === 0) return jsonResponse({ error: '无歌曲' }, 400);
  if (uniqueKeys.length > 500) return jsonResponse({ error: '单批最多500首' }, 400);
  let result;
  try {
    result = await applyLegacyPlaylistMutation(env, userId, baseRevision, [{
      id: 'love',
      name: '我喜欢',
      position: 0,
      mode: 'remove-items',
      songs: uniqueKeys.map((key) => {
        const [songmid, source] = key.split('|', 2);
        return { name: songmid, singer: '', songmid, source };
      }),
      deduplicate: true,
    }]);
  } catch (error) {
    console.error('[love:remove]', error);
    return jsonResponse({ error: '保存失败' }, 500);
  }
  if (!result) {
    return jsonResponse({
      error: 'revision_conflict',
      currentRevision: await getSyncRevision(env, userId),
    }, 409);
  }

  try { ctx.waitUntil(env.CACHE.delete(`v2:love:${userId}`)); } catch {}

  return jsonResponse({ ok: true, removed: result.removedSongs, revision: result.revision });
}

// DELETE /api/user/playlist?id=xxx
export async function handlePlaylistDelete(request: Request, url: URL, env: Env): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const id = url.searchParams.get('id');
  if (!id || id.length > 128 || id === 'love' || id.startsWith('__stage__:')) {
    return jsonResponse({ error: '无效歌单ID' }, 400);
  }
  const rawBaseRevision = url.searchParams.get('baseRevision');
  const baseRevision = rawBaseRevision != null && /^\d+$/.test(rawBaseRevision)
    ? Number(rawBaseRevision)
    : null;
  if (baseRevision == null || !Number.isSafeInteger(baseRevision)) {
    return jsonResponse({ error: 'baseRevision 无效' }, 400);
  }
  const existing = await env.DB.prepare(
    'SELECT id, name, position FROM playlists WHERE id = ? AND user_id = ?',
  ).bind(id, userId).first<{ id: string; name: string; position: number }>();
  if (!existing) return jsonResponse({ error: '歌单不存在' }, 404);

  const result = await applyLegacyPlaylistMutation(env, userId, baseRevision, [{
    id,
    name: existing.name,
    position: existing.position,
    mode: 'delete',
  }]);
  if (!result) {
    return jsonResponse({
      error: 'revision_conflict',
      currentRevision: await getSyncRevision(env, userId),
    }, 409);
  }
  return jsonResponse({
    ok: true,
    deleted: result.deletedPlaylists,
    revision: result.revision,
  });
}


// POST /api/user/playlist/refresh — re-pull an imported playlist from its
// platform using the stored source/source_id. Replaces the songs (and the
// name, which the platform may have renamed) in-place so the local copy
// matches the latest state. Renames done locally are intentionally
// overwritten; users who want a custom name should re-rename after refresh.
export async function handlePlaylistRefresh(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const userId = await getUserId(request, env);
  if (!userId) return jsonResponse({ error: '未登录' }, 401);

  const ctErr = requireJsonContentType(request);
  if (ctErr) return ctErr;

  const parsed = await readJsonBody(request);
  if (parsed instanceof Response) return parsed;

  const id = String(parsed.body.id || '').slice(0, 128);
  if (!id || id === 'love') return jsonResponse({ error: '无效歌单ID' }, 400);
  const baseRevision = parseBaseRevision(parsed.body.baseRevision);
  if (baseRevision == null) return jsonResponse({ error: 'baseRevision 无效' }, 400);

  const pl = await env.DB.prepare(
    'SELECT id, name, source, source_id, position FROM playlists WHERE id = ? AND user_id = ?'
  ).bind(id, userId).first<{ id: string; name: string; source: string; source_id: string; position: number }>();
  if (!pl) return jsonResponse({ error: '歌单不存在' }, 404);
  // An imported playlist must have a source + source_id to be refreshable.
  // The 'love' playlist and any future purely-local playlists fall through here.
  if (!pl.source || !pl.source_id) return jsonResponse({ error: '该歌单不支持刷新' }, 400);

  let info;
  try {
    info = await fetchAndRematch(pl.source, pl.source_id, env);
  } catch (err: any) {
    // P2-10: generic message to user; log details server-side.
    console.error('[refresh]', pl.source, pl.source_id, err?.message);
    return jsonResponse({ error: '刷新失败：歌单已失效或网络异常' }, 500);
  }
  const songs: SongInfo[] = (info.songs || []).filter((s: SongInfo) => s && s.name);
  if (!songs.length) return jsonResponse({ error: '歌单为空或已失效' }, 400);

  const newName = String(info.name || pl.name || '').slice(0, 128);
  try {
    const revision = await writePlaylistAtRevision(env, {
      id, userId, name: newName, position: pl.position, source: pl.source, sourceId: pl.source_id,
    }, songs, { replace: true }, baseRevision);
    if (revision == null) {
      return jsonResponse({
        error: 'revision_conflict',
        currentRevision: await getSyncRevision(env, userId),
      }, 409);
    }
    return jsonResponse({
      ok: true,
      revision,
      playlist: { id, name: newName, source: pl.source, count: songs.length },
    });
  } catch (err: any) {
    console.error('[refresh:save]', err?.message);
    return jsonResponse({ error: '刷新保存失败' }, 500);
  }
}
