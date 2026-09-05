import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import { checkSchemaReady } from '../src/db/schema';
import type { Env } from '../src/lib/response';

type TestEnv = Env & { TEST_MIGRATIONS: D1Migration[] };

describe('schema readiness', () => {
  const testEnv = env as TestEnv;

  beforeEach(async () => {
    await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
    await testEnv.CACHE.delete('v4:system:schema_ready');
  });

  it('recognizes the complete migrated schema', async () => {
    await expect(checkSchemaReady(testEnv)).resolves.toEqual({ ready: true });
  });

  it('rejects a missing required index instead of reporting ready', async () => {
    await testEnv.DB.prepare('DROP INDEX uniq_playlist_item_id').run();
    try {
      await expect(checkSchemaReady(testEnv)).resolves.toEqual({
        ready: false,
        reason: 'D1 migrations are pending',
      });
    } finally {
      await testEnv.DB.prepare(
        `CREATE UNIQUE INDEX uniq_playlist_item_id
         ON playlist_songs(user_id, playlist_id, playlist_item_id)
         WHERE playlist_item_id IS NOT NULL`,
      ).run();
    }
  });
});
