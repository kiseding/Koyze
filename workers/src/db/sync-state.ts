import type { Env } from '../lib/response';

export async function getSyncRevision(env: Env, userId: number): Promise<number> {
  await env.DB.prepare(
    'INSERT OR IGNORE INTO user_sync_state (user_id, revision) VALUES (?, 0)',
  ).bind(userId).run();
  const row = await env.DB.prepare(
    'SELECT revision FROM user_sync_state WHERE user_id = ?',
  ).bind(userId).first<{ revision: number }>();
  return Number(row?.revision ?? 0);
}

export async function requireSyncRevision(
  env: Env,
  userId: number,
  expected: unknown,
): Promise<
  | { ok: true; revision: number; claimed: boolean }
  | { ok: false; revision: number; claimed: false }
> {
  if (expected == null) return { ok: true, revision: 0, claimed: false };
  const revision = await getSyncRevision(env, userId);
  const parsed = Number(expected);
  return Number.isInteger(parsed) && parsed === revision
    ? { ok: true, revision, claimed: false }
    : { ok: false, revision, claimed: false };
}

export async function advanceSyncRevision(env: Env, userId: number): Promise<number> {
  await env.DB.prepare(
    `INSERT INTO user_sync_state (user_id, revision, updated_at)
     VALUES (?, 1, datetime('now'))
     ON CONFLICT(user_id) DO UPDATE SET
       revision = revision + 1,
       updated_at = datetime('now')`,
  ).bind(userId).run();
  return getSyncRevision(env, userId);
}
