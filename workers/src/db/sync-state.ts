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

