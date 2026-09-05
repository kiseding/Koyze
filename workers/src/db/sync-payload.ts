import type { Env } from '../lib/response';
import { getSyncRevision } from './sync-state';

export interface SyncPayload {
  settings: Record<string, string>;
  sources: Record<string, unknown>[];
}

export type PayloadRow = {
  settings: string;
  sources: string;
  base_sequence: number;
};

export type SettingProjectionRow = { key: string; value: string };
export type SourceProjectionRow = { id: string; source: string; deleted: number };

function parseSettings(raw: string | null | undefined): Record<string, string> {
  try {
    const parsed = raw ? JSON.parse(raw) : {};
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};
    return Object.fromEntries(
      Object.entries(parsed as Record<string, unknown>).map(([key, value]) => [key, String(value)]),
    );
  } catch {
    return {};
  }
}

function parseSources(raw: string | null | undefined): Record<string, unknown>[] {
  try {
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed)
      ? parsed.filter((source): source is Record<string, unknown> =>
          !!source && typeof source === 'object' && !Array.isArray(source))
      : [];
  } catch {
    return [];
  }
}

async function legacyPayload(env: Env, userId: number): Promise<SyncPayload> {
  const [settingsRaw, sourcesRaw] = await Promise.all([
    env.CACHE.get(`sync:settings:${userId}`),
    env.CACHE.get(`sync:sources:${userId}`),
  ]);
  return {
    settings: parseSettings(settingsRaw),
    sources: parseSources(sourcesRaw),
  };
}

/**
 * Loads the authoritative D1 payload. Existing KV-only installations migrate
 * lazily and idempotently on first access; concurrent migrations converge via
 * INSERT OR IGNORE.
 */
export async function ensureSyncPayload(env: Env, userId: number): Promise<PayloadRow> {
  let row = await env.DB.prepare(
    'SELECT settings, sources, base_sequence FROM user_sync_payloads WHERE user_id = ?',
  ).bind(userId).first<PayloadRow>();
  if (row) return row;

  const legacy = await legacyPayload(env, userId);
  const cursor = await env.DB.prepare(
    'SELECT COALESCE(MAX(id), 0) AS cursor FROM sync_events WHERE user_id = ?',
  ).bind(userId).first<{ cursor: number }>();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO user_sync_payloads
     (user_id, settings, sources, base_sequence)
     VALUES (?, ?, ?, ?)`,
  ).bind(
    userId,
    JSON.stringify(legacy.settings),
    JSON.stringify(legacy.sources),
    Number(cursor?.cursor ?? 0),
  ).run();
  row = await env.DB.prepare(
    'SELECT settings, sources, base_sequence FROM user_sync_payloads WHERE user_id = ?',
  ).bind(userId).first<PayloadRow>();
  if (!row) throw new Error('sync payload initialization failed');
  return row;
}

export async function readSyncPayload(env: Env, userId: number): Promise<SyncPayload> {
  await ensureSyncPayload(env, userId);
  const results = await env.DB.batch([
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
  ]);
  const row = results[0].results?.[0] as PayloadRow | undefined;
  if (!row) throw new Error('sync payload missing after initialization');
  return materializeSyncPayload(
    row,
    (results[1].results ?? []) as SettingProjectionRow[],
    (results[2].results ?? []) as SourceProjectionRow[],
  );
}

export function materializeSyncPayload(
  row: PayloadRow,
  settingRows: SettingProjectionRow[],
  sourceRows: SourceProjectionRow[],
): SyncPayload {
  const settings = parseSettings(row.settings);
  const sources = new Map<string, Record<string, unknown>>();
  for (const source of parseSources(row.sources)) {
    const id = String(source.id ?? '');
    if (id) sources.set(id, source);
  }

  for (const setting of settingRows) settings[setting.key] = setting.value;
  for (const projection of sourceRows) {
    if (projection.deleted) {
      sources.delete(projection.id);
      continue;
    }
    const parsed = parseSources(`[${projection.source}]`)[0];
    if (parsed) sources.set(projection.id, parsed);
  }
  return { settings, sources: [...sources.values()] };
}

/** Atomically replaces both payloads and advances the optimistic revision. */
export async function replaceSyncPayload(
  env: Env,
  userId: number,
  baseRevision: number,
  payload: SyncPayload,
): Promise<number | null> {
  await getSyncRevision(env, userId);
  const results = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO user_sync_payloads
       (user_id, settings, sources, base_sequence, updated_at)
       SELECT ?, ?, ?, COALESCE((SELECT MAX(id) FROM sync_events WHERE user_id = ?), 0), datetime('now')
       WHERE EXISTS (SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?)
       ON CONFLICT(user_id) DO UPDATE SET
         settings = excluded.settings,
         sources = excluded.sources,
         base_sequence = excluded.base_sequence,
         updated_at = excluded.updated_at`,
    ).bind(
      userId,
      JSON.stringify(payload.settings),
      JSON.stringify(payload.sources),
      userId,
      userId,
      baseRevision,
    ),
    env.DB.prepare(
      `DELETE FROM sync_setting_projections
       WHERE user_id = ? AND EXISTS (
         SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?
       )`,
    ).bind(userId, userId, baseRevision),
    env.DB.prepare(
      `DELETE FROM sync_source_projections
       WHERE user_id = ? AND EXISTS (
         SELECT 1 FROM user_sync_state WHERE user_id = ? AND revision = ?
       )`,
    ).bind(userId, userId, baseRevision),
    env.DB.prepare(
      `UPDATE user_sync_state
       SET revision = revision + 1, updated_at = datetime('now')
       WHERE user_id = ? AND revision = ?`,
    ).bind(userId, baseRevision),
  ]);
  const revisionResult = results[results.length - 1];
  return (revisionResult?.meta?.changes ?? 0) === 1 ? baseRevision + 1 : null;
}

export async function setProjectedSetting(
  env: Env,
  userId: number,
  key: string,
  value: string,
  sequence: number,
): Promise<void> {
  await ensureSyncPayload(env, userId);
  await env.DB.prepare(
    `INSERT INTO sync_setting_projections (user_id, key, value, server_sequence)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id, key) DO UPDATE SET
       value = excluded.value,
       server_sequence = excluded.server_sequence,
       updated_at = datetime('now')
     WHERE excluded.server_sequence > sync_setting_projections.server_sequence`,
  ).bind(userId, key, value, sequence).run();
}

export async function setProjectedSource(
  env: Env,
  userId: number,
  id: string,
  source: Record<string, unknown> | null,
  sequence: number,
): Promise<void> {
  await ensureSyncPayload(env, userId);
  await env.DB.prepare(
    `INSERT INTO sync_source_projections
     (user_id, id, source, deleted, server_sequence)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id, id) DO UPDATE SET
       source = excluded.source,
       deleted = excluded.deleted,
       server_sequence = excluded.server_sequence,
       updated_at = datetime('now')
     WHERE excluded.server_sequence > sync_source_projections.server_sequence`,
  ).bind(userId, id, JSON.stringify(source ?? {}), source == null ? 1 : 0, sequence).run();
}
