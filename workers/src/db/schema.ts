import type { Env } from '../lib/response';

export type SchemaReadiness =
  | { ready: true }
  | { ready: false; reason: string };

const READY_CACHE_KEY = 'v4:system:schema_ready';
const READY_CACHE_TTL = 300; // 5 minutes; only consulted once ready

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
  'user_sync_payloads',
  'sync_setting_projections',
  'sync_source_projections',
  'sync_event_watermarks',
  'sync_events',
  'sync_event_receipts',
  'sync_devices',
  'sync_tombstones',
  'sync_ratings',
  'sync_play_history',
] as const;

const REQUIRED_INDEXES = [
  'uniq_ps_love_song',
  'uniq_playlist_item_id',
  'idx_sync_events_user_id',
  'idx_sync_setting_projection_sequence',
  'idx_sync_source_projection_sequence',
] as const;

function placeholders(values: readonly string[]): string {
  return values.map(() => '?').join(', ');
}

function hasEveryName(
  rows: Array<{ name?: string }> | undefined,
  expected: readonly string[],
): boolean {
  const names = new Set((rows ?? []).map((row) => row.name));
  return expected.every((name) => names.has(name));
}

export async function checkSchemaReady(env: Env): Promise<SchemaReadiness> {
  // Cache only successful readiness. Pending migrations are checked on every
  // request so a just-applied migration can unblock immediately.
  try {
    const cached = await env.CACHE.get(READY_CACHE_KEY);
    if (cached) return { ready: true };
  } catch {
    // KV read failure is non-fatal; fall through to the DB check.
  }

  let readiness: SchemaReadiness;
  try {
    const [tables, userColumns, eventColumns, songColumns, indexes] = await env.DB.batch([
      env.DB.prepare(`
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name IN (${placeholders(REQUIRED_TABLES)})
      `).bind(...REQUIRED_TABLES),
      env.DB.prepare("PRAGMA table_info('users')"),
      env.DB.prepare("PRAGMA table_info('sync_events')"),
      env.DB.prepare("PRAGMA table_info('playlist_songs')"),
      env.DB.prepare(`
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND name IN (${placeholders(REQUIRED_INDEXES)})
      `).bind(...REQUIRED_INDEXES),
    ]);
    const hasColumn = (result: D1Result<unknown>, name: string) =>
      (result.results as Array<{ name?: string }> | undefined)
        ?.some((column) => column.name === name) ?? false;
    const schemaComplete =
      hasEveryName(tables.results as Array<{ name?: string }> | undefined, REQUIRED_TABLES) &&
      hasEveryName(indexes.results as Array<{ name?: string }> | undefined, REQUIRED_INDEXES) &&
      hasColumn(userColumns, 'token_version') &&
      hasColumn(eventColumns, 'applied_at') &&
      hasColumn(songColumns, 'playlist_item_id');
    readiness = schemaComplete
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
