import type { Env } from '../lib/response';

export type SchemaReadiness =
  | { ready: true }
  | { ready: false; reason: string };

const READY_CACHE_KEY = 'v3:system:schema_ready';
const READY_CACHE_TTL = 300; // 5 minutes; only consulted once ready

/**
 * Tables that must exist for the API to serve traffic.
 *
 * Readiness is "every required table is present", never "the table count equals
 * N": a migration that adds, renames, or drops an unrelated table must not be
 * able to flip the whole API to 503.
 */
const REQUIRED_TABLES = [
  'users',
  'system_settings',
  'playlists',
  'playlist_songs',
  'user_artists',
  'user_albums',
  'user_settings',
  'playback_progress',
  'user_sync_state',
  'sync_events',
  'sync_devices',
  'sync_tombstones',
  'sync_ratings',
  'sync_play_history',
] as const;

export async function checkSchemaReady(env: Env): Promise<SchemaReadiness> {
  // O1: cache readiness in KV so we don't run a 3-query D1 batch on every
  // request. Only "ready" is cached long-term; a pending-migration state is
  // re-checked after a short TTL so a just-applied migration unblocks fast.
  try {
    const cached = await env.CACHE.get(READY_CACHE_KEY);
    if (cached) return { ready: true };
  } catch {
    // KV read failure is non-fatal; fall through to the DB check.
  }

  let readiness: SchemaReadiness;
  try {
    const [tables, columns, index] = await env.DB.batch([
      env.DB.prepare(`
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name IN (${REQUIRED_TABLES.map(() => '?').join(', ')})
      `).bind(...REQUIRED_TABLES),
      env.DB.prepare("PRAGMA table_info('users')"),
      env.DB.prepare(`
        SELECT COUNT(*) AS count
        FROM sqlite_master
        WHERE type = 'index' AND name = 'uniq_ps_love_song'
      `),
    ]);
    const foundTables = new Set(
      (tables.results as Array<{ name?: string }> | undefined)
        ?.map((row) => row.name)
        .filter((name): name is string => typeof name === 'string') ?? [],
    );
    const missingTables = REQUIRED_TABLES.filter((name) => !foundTables.has(name));
    const hasTokenVersion = (columns.results as Array<{ name?: string }> | undefined)
      ?.some((column) => column.name === 'token_version') ?? false;
    const indexCount = Number((index.results?.[0] as { count?: number } | undefined)?.count ?? 0);
    // Extra tables are fine; only missing ones block readiness.
    readiness = missingTables.length === 0 && hasTokenVersion && indexCount === 1
      ? { ready: true }
      : { ready: false, reason: 'D1 migrations are pending' };
  } catch {
    readiness = { ready: false, reason: 'D1 readiness check failed' };
  }

  try {
    if (readiness.ready) {
      await env.CACHE.put(READY_CACHE_KEY, '1', { expirationTtl: READY_CACHE_TTL });
    } else {
      await env.CACHE.delete(READY_CACHE_KEY);
    }
  } catch {
    // Cache write failure is non-fatal.
  }
  return readiness;
}
