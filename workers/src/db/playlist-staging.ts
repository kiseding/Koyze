import type { Env } from '../lib/response';
import type { SongInfo } from '../utils/types';
import { getSyncRevision } from './sync-state';

export interface PlaylistTarget {
  id: string;
  userId: number;
  name: string;
  position: number;
  source?: string;
  sourceId?: string;
}

export interface StageOptions {
  replace: boolean;
  startPosition?: number;
}

export type LegacyPlaylistMutationMode =
  | 'replace'
  | 'append'
  | 'rename'
  | 'delete'
  | 'remove-items';

export interface LegacyPlaylistMutation {
  id: string;
  name: string;
  position: number;
  mode: LegacyPlaylistMutationMode;
  songs?: SongInfo[];
  deduplicate?: boolean;
}

export interface LegacyPlaylistMutationResult {
  revision: number;
  insertedSongs: number;
  removedSongs: number;
  deletedPlaylists: number;
}

export function makeStageId(): string {
  return `__stage__:${crypto.randomUUID()}`;
}

export function songIdentity(songmid: unknown, source: unknown): string {
  return `${String(songmid || '')}|${String(source || '')}`;
}

export async function createStage(env: Env, userId: number): Promise<string> {
  const stageId = makeStageId();
  await env.DB.prepare(
    'INSERT INTO playlists (id, user_id, name, position, source, source_id) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(stageId, userId, '', -1, '', '').run();
  return stageId;
}

export async function insertStageSongs(
  env: Env,
  stageId: string,
  userId: number,
  songs: SongInfo[],
  startPosition = 0,
  deduplicate = false,
): Promise<void> {
  const normalized: SongInfo[] = [];
  const seen = new Set<string>();
  for (const song of songs) {
    const mid = String(song.songmid || '').slice(0, 256);
    const source = String(song.source || '').slice(0, 32);
    if (deduplicate) {
      const identity = songIdentity(mid, source);
      if (!mid || seen.has(identity)) continue;
      seen.add(identity);
    }
    normalized.push({ ...song, songmid: mid, source });
  }

  const statements = normalized.map((song, index) => {
    const metadata = JSON.stringify({
      mrcUrl: song.mrcUrl || '',
      lrcUrl: song.lrcUrl || '',
      trcUrl: song.trcUrl || '',
    });
    return env.DB.prepare(
      `INSERT INTO playlist_songs
       (playlist_id, user_id, name, singer, source, songmid, album_name, album_id, img, interval, types, hash, metadata, position)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(
      stageId, userId, String(song.name || '').slice(0, 256), String(song.singer || '').slice(0, 256),
      song.source || '', song.songmid || '', String(song.albumName || '').slice(0, 256),
      String(song.albumId || '').slice(0, 128), String(song.img || '').slice(0, 512), song.interval || '0',
      JSON.stringify(song.types || []).slice(0, 1024), String(song.hash || '').slice(0, 256), metadata,
      startPosition + index,
    );
  });
  for (let i = 0; i < statements.length; i += 100) {
    await env.DB.batch(statements.slice(i, i + 100));
  }
}

export async function cleanupStage(env: Env, stageId: string, userId: number): Promise<void> {
  await env.DB.prepare('DELETE FROM playlists WHERE id = ? AND user_id = ?').bind(stageId, userId).run();
}

function mutationMarker(mode: LegacyPlaylistMutationMode): string {
  return `__mutation__:${mode}`;
}

async function cleanupMutationStages(
  env: Env,
  userId: number,
  prefix: string,
): Promise<void> {
  try {
    await env.DB.prepare(
      'DELETE FROM playlists WHERE user_id = ? AND substr(id, 1, ?) = ?',
    ).bind(userId, prefix.length, prefix).run();
  } catch {
    // Best-effort cleanup. Stages are hidden from every read API and a later
    // mutation also removes stale rows for the same account.
  }
}

/**
 * Applies a complete legacy playlist request with one optimistic revision.
 * Song payloads are first written under hidden playlist IDs; the only writes
 * to live playlists and the revision claim then happen in one D1 batch
 * transaction. A stale writer therefore changes neither data nor revision,
 * and an execution error rolls the whole commit back.
 */
export async function applyLegacyPlaylistMutation(
  env: Env,
  userId: number,
  baseRevision: number,
  mutations: LegacyPlaylistMutation[],
): Promise<LegacyPlaylistMutationResult | null> {
  await getSyncRevision(env, userId);
  const operationId = crypto.randomUUID();
  const prefix = `__stage__:legacy:${operationId}:`;

  try {
    // Old abandoned stages are never visible, but bounding them prevents a
    // crashed upload from accumulating storage forever.
    await env.DB.prepare(
      "DELETE FROM playlists WHERE user_id = ? AND id LIKE '__stage__:legacy:%' AND created_at < datetime('now', '-1 hour')",
    ).bind(userId).run();

    for (let index = 0; index < mutations.length; index += 1) {
      const mutation = mutations[index];
      const stageId = `${prefix}${index}`;
      await env.DB.prepare(
        `INSERT INTO playlists (id, user_id, name, position, source, source_id)
         VALUES (?, ?, ?, ?, ?, ?)`,
      ).bind(
        stageId,
        userId,
        mutation.name,
        mutation.position,
        mutationMarker(mutation.mode),
        mutation.id,
      ).run();
      if (mutation.songs?.length) {
        await insertStageSongs(
          env,
          stageId,
          userId,
          mutation.songs,
          0,
          mutation.deduplicate === true,
        );
      }
    }

    const guard = 'EXISTS (SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?)';
    const results = await env.DB.batch([
      // Renames intentionally run before replacements, matching the legacy
      // endpoint's historical ordering when both mention the same playlist.
      env.DB.prepare(
        `UPDATE playlists AS target
         SET name = COALESCE((
           SELECT stage.name FROM playlists AS stage
           WHERE stage.user_id = target.user_id
             AND substr(stage.id, 1, ?) = ?
             AND stage.source = ?
             AND stage.source_id = target.id
           LIMIT 1
         ), target.name), updated_at = datetime('now')
         WHERE target.user_id = ?
           AND target.id NOT LIKE '__stage__:%'
           AND EXISTS (
             SELECT 1 FROM playlists AS stage
             WHERE stage.user_id = target.user_id
               AND substr(stage.id, 1, ?) = ?
               AND stage.source = ?
               AND stage.source_id = target.id
           ) AND ${guard}`,
      ).bind(
        prefix.length, prefix, mutationMarker('rename'),
        userId,
        prefix.length, prefix, mutationMarker('rename'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `INSERT INTO playlists (id, user_id, name, position, source, source_id)
         SELECT stage.source_id, stage.user_id, stage.name, stage.position, '', ''
         FROM playlists AS stage
         WHERE stage.user_id = ? AND substr(stage.id, 1, ?) = ?
           AND stage.source IN (?, ?) AND ${guard}
         ON CONFLICT(id, user_id) DO UPDATE SET
           name = excluded.name,
           position = excluded.position,
           updated_at = datetime('now')`,
      ).bind(
        userId, prefix.length, prefix,
        mutationMarker('replace'), mutationMarker('append'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `DELETE FROM playlist_songs
         WHERE user_id = ? AND playlist_id IN (
           SELECT source_id FROM playlists
           WHERE user_id = ? AND substr(id, 1, ?) = ? AND source = ?
         ) AND ${guard}`,
      ).bind(
        userId, userId, prefix.length, prefix, mutationMarker('replace'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `DELETE FROM playlist_songs AS target
         WHERE target.user_id = ? AND EXISTS (
           SELECT 1
           FROM playlists AS stage
           JOIN playlist_songs AS staged_song
             ON staged_song.playlist_id = stage.id
            AND staged_song.user_id = stage.user_id
           WHERE stage.user_id = target.user_id
             AND substr(stage.id, 1, ?) = ?
             AND stage.source = ?
             AND stage.source_id = target.playlist_id
             AND staged_song.songmid = target.songmid
             AND staged_song.source = target.source
         ) AND ${guard}`,
      ).bind(
        userId, prefix.length, prefix, mutationMarker('remove-items'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `INSERT OR IGNORE INTO playlist_songs
         (playlist_id, user_id, name, singer, source, songmid, album_name,
          album_id, img, interval, types, hash, str_media_mid, copyright_id,
          metadata, position, playlist_item_id)
         SELECT stage.source_id, song.user_id, song.name, song.singer,
                song.source, song.songmid, song.album_name, song.album_id,
                song.img, song.interval, song.types, song.hash,
                song.str_media_mid, song.copyright_id, song.metadata,
                CASE WHEN stage.source = ? THEN
                  song.position + COALESCE((
                    SELECT MAX(existing.position) + 1
                    FROM playlist_songs AS existing
                    WHERE existing.user_id = song.user_id
                      AND existing.playlist_id = stage.source_id
                  ), 0)
                ELSE song.position END,
                song.playlist_item_id
         FROM playlist_songs AS song
         JOIN playlists AS stage
           ON stage.id = song.playlist_id AND stage.user_id = song.user_id
         WHERE stage.user_id = ? AND substr(stage.id, 1, ?) = ?
           AND stage.source IN (?, ?) AND ${guard}`,
      ).bind(
        mutationMarker('append'),
        userId, prefix.length, prefix,
        mutationMarker('replace'), mutationMarker('append'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `DELETE FROM playlists
         WHERE user_id = ? AND id NOT LIKE '__stage__:%' AND id IN (
           SELECT source_id FROM playlists AS stage
           WHERE stage.user_id = ? AND substr(stage.id, 1, ?) = ?
             AND stage.source = ?
         ) AND ${guard}`,
      ).bind(
        userId, userId, prefix.length, prefix, mutationMarker('delete'),
        userId, baseRevision,
      ),
      env.DB.prepare(
        `DELETE FROM playlists
         WHERE user_id = ? AND substr(id, 1, ?) = ? AND ${guard}`,
      ).bind(userId, prefix.length, prefix, userId, baseRevision),
      env.DB.prepare(
        `UPDATE user_sync_state
         SET revision = revision + 1, updated_at = datetime('now')
         WHERE user_id = ? AND revision = ?`,
      ).bind(userId, baseRevision),
    ]);
    const revision = results[results.length - 1];
    if ((revision?.meta?.changes ?? 0) === 1) {
      return {
        revision: baseRevision + 1,
        insertedSongs: results[4]?.meta?.changes ?? 0,
        removedSongs: results[3]?.meta?.changes ?? 0,
        deletedPlaylists: results[5]?.meta?.changes ?? 0,
      };
    }
    await cleanupMutationStages(env, userId, prefix);
    return null;
  } catch (error) {
    await cleanupMutationStages(env, userId, prefix);
    throw error;
  }
}

/** Atomically publishes one already validated playlist at a revision. */
export async function writePlaylistAtRevision(
  env: Env,
  target: PlaylistTarget,
  songs: SongInfo[],
  options: StageOptions,
  baseRevision: number,
): Promise<number | null> {
  await getSyncRevision(env, target.userId);
  const stageId = await createStage(env, target.userId);
  try {
    await insertStageSongs(
      env,
      stageId,
      target.userId,
      songs,
      options.startPosition ?? 0,
      target.id === 'love',
    );
    const guard = 'EXISTS (SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?)';
    const statements = [
      env.DB.prepare(
        `INSERT INTO playlists (id, user_id, name, position, source, source_id)
         SELECT ?, ?, ?, ?, ?, ? WHERE ${guard}
         ON CONFLICT(id, user_id) DO UPDATE SET
           name = excluded.name,
           position = excluded.position,
           source = excluded.source,
           source_id = excluded.source_id,
           updated_at = datetime('now')`,
      ).bind(
        target.id, target.userId, target.name, target.position,
        target.source || '', target.sourceId || '', target.userId, baseRevision,
      ),
    ];
    if (options.replace) {
      statements.push(
        env.DB.prepare(
          `DELETE FROM playlist_songs
           WHERE playlist_id = ? AND user_id = ? AND ${guard}`,
        ).bind(target.id, target.userId, target.userId, baseRevision),
      );
    }
    statements.push(
      env.DB.prepare(
        `INSERT OR IGNORE INTO playlist_songs
         (playlist_id, user_id, name, singer, source, songmid, album_name,
          album_id, img, interval, types, hash, str_media_mid, copyright_id,
          metadata, position, playlist_item_id)
         SELECT ?, user_id, name, singer, source, songmid, album_name,
                album_id, img, interval, types, hash, str_media_mid,
                copyright_id, metadata, position, playlist_item_id
         FROM playlist_songs
         WHERE playlist_id = ? AND user_id = ? AND ${guard}`,
      ).bind(
        target.id, stageId, target.userId, target.userId, baseRevision,
      ),
      env.DB.prepare(
        `DELETE FROM playlists
         WHERE id = ? AND user_id = ? AND ${guard}`,
      ).bind(stageId, target.userId, target.userId, baseRevision),
      env.DB.prepare(
        `UPDATE user_sync_state
         SET revision = revision + 1, updated_at = datetime('now')
         WHERE user_id = ? AND revision = ?`,
      ).bind(target.userId, baseRevision),
    );
    const results = await env.DB.batch(statements);
    const revision = results[results.length - 1];
    if ((revision?.meta?.changes ?? 0) === 1) return baseRevision + 1;
    await cleanupStage(env, stageId, target.userId);
    return null;
  } catch (error) {
    try { await cleanupStage(env, stageId, target.userId); } catch {}
    throw error;
  }
}
