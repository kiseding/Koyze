import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';
import {
  readSyncPayload,
  replaceSyncPayload,
  setProjectedSetting,
  setProjectedSource,
} from '../src/db/sync-payload';
import { compactSyncEvents, syncEventWatermark } from '../src/db/sync-events';
import type { Env } from '../src/lib/response';

type TestEnv = Env & { TEST_MIGRATIONS: D1Migration[] };

describe('D1 sync payload integration', () => {
  const testEnv = env as TestEnv;

  beforeEach(async () => {
    await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
    await testEnv.DB.prepare('DELETE FROM users').run();
    await testEnv.DB.prepare(
      "INSERT INTO users (id, username, password_hash) VALUES (1, 'sync-user', 'hash')",
    ).run();
  });

  it('atomically replaces settings and sources with one winning revision', async () => {
    await expect(replaceSyncPayload(testEnv, 1, 0, {
      settings: { theme: 'dark' },
      sources: [{ id: 'source-a', name: 'A' }],
    })).resolves.toBe(1);

    const contenders = await Promise.all([
      replaceSyncPayload(testEnv, 1, 1, {
        settings: { theme: 'light', winner: 'a' },
        sources: [{ id: 'source-a', name: 'A2' }],
      }),
      replaceSyncPayload(testEnv, 1, 1, {
        settings: { theme: 'system', winner: 'b' },
        sources: [{ id: 'source-b', name: 'B' }],
      }),
    ]);

    expect(contenders.filter((revision) => revision === 2)).toHaveLength(1);
    expect(contenders.filter((revision) => revision == null)).toHaveLength(1);
    const payload = await readSyncPayload(testEnv, 1);
    expect(['a', 'b']).toContain(payload.settings.winner);
    if (payload.settings.winner === 'a') {
      expect(payload.sources).toEqual([{ id: 'source-a', name: 'A2' }]);
    } else {
      expect(payload.sources).toEqual([{ id: 'source-b', name: 'B' }]);
    }
  });

  it('overlays only events newer than the replacement baseline', async () => {
    await replaceSyncPayload(testEnv, 1, 0, {
      settings: { theme: 'dark' },
      sources: [{ id: 'source-a', name: 'A' }],
    });
    await setProjectedSetting(testEnv, 1, 'theme', 'light', 3);
    await setProjectedSource(testEnv, 1, 'source-a', null, 4);
    await setProjectedSource(testEnv, 1, 'source-b', { id: 'source-b', name: 'B' }, 5);

    await expect(readSyncPayload(testEnv, 1)).resolves.toEqual({
      settings: { theme: 'light' },
      sources: [{ id: 'source-b', name: 'B' }],
    });
  });

  it('compacts replay history and records the exact snapshot boundary', async () => {
    for (let id = 1; id <= 4; id += 1) {
      await testEnv.DB.prepare(
        `INSERT INTO sync_events
         (id, user_id, event_id, device_id, local_user_id, event_type,
          entity_id, payload, client_created_at, applied_at)
         VALUES (?, 1, ?, 'device', 'local', 'setting.set', ?, '{}', ?, datetime('now'))`,
      ).bind(id, `event-${id}`, `setting-${id}`, id).run();
    }

    await expect(compactSyncEvents(testEnv, 1, 2)).resolves.toBe(2);
    await expect(syncEventWatermark(testEnv, 1)).resolves.toBe(2);
    const retained = await testEnv.DB.prepare(
      'SELECT id FROM sync_events WHERE user_id = 1 ORDER BY id',
    ).all<{ id: number }>();
    expect(retained.results).toEqual([{ id: 3 }, { id: 4 }]);
  });
});
