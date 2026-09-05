import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/lib/response';

vi.mock('../src/utils/auth', () => ({
  getUserId: async () => 1,
}));

import { handleUserPlaylistSave } from '../src/routes/user/playlist';

type TestEnv = Env & { TEST_MIGRATIONS: D1Migration[] };

const context = {
  waitUntil: () => undefined,
  passThroughOnException: () => undefined,
  props: {},
} as unknown as ExecutionContext;

function saveRequest(body: Record<string, unknown>): Request {
  return new Request('https://worker.test/api/user/list', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('legacy playlist mutation transaction', () => {
  const testEnv = env as TestEnv;

  beforeEach(async () => {
    await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
    await testEnv.DB.prepare('DROP TRIGGER IF EXISTS reject_live_song').run();
    await testEnv.DB.prepare('DELETE FROM users').run();
    await testEnv.DB.prepare(
      "INSERT INTO users (id, username, password_hash) VALUES (1, 'playlist-user', 'hash')",
    ).run();
  });

  it('validates the whole request before creating stages or advancing revision', async () => {
    const response = await handleUserPlaylistSave(saveRequest({
      baseRevision: 0,
      userList: [{
        id: 'bad',
        name: 'Bad',
        mode: 'append',
        list: [{ singer: 'missing-name' }],
      }],
    }), testEnv, context);

    expect(response.status).toBe(400);
    const revision = await testEnv.DB.prepare(
      'SELECT revision FROM user_sync_state WHERE user_id = 1',
    ).first<{ revision: number }>();
    const stages = await testEnv.DB.prepare(
      "SELECT COUNT(*) AS count FROM playlists WHERE user_id = 1 AND id LIKE '__stage__:%'",
    ).first<{ count: number }>();
    expect(revision).toBeNull();
    expect(Number(stages?.count ?? 0)).toBe(0);
  });

  it('allows exactly one concurrent writer for the same base revision', async () => {
    const makeBody = (id: string) => ({
      baseRevision: 0,
      userList: [{
        id,
        name: id,
        mode: 'replace',
        position: 1,
        list: [{ name: 'Song', singer: 'Singer', source: 'tx', songmid: id }],
      }],
    });
    const responses = await Promise.all([
      handleUserPlaylistSave(saveRequest(makeBody('writer-a')), testEnv, context),
      handleUserPlaylistSave(saveRequest(makeBody('writer-b')), testEnv, context),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([200, 409]);
    const revision = await testEnv.DB.prepare(
      'SELECT revision FROM user_sync_state WHERE user_id = 1',
    ).first<{ revision: number }>();
    const live = await testEnv.DB.prepare(
      "SELECT id FROM playlists WHERE user_id = 1 AND id NOT LIKE '__stage__:%'",
    ).all<{ id: string }>();
    const stages = await testEnv.DB.prepare(
      "SELECT id FROM playlists WHERE user_id = 1 AND id LIKE '__stage__:%'",
    ).all<{ id: string }>();
    expect(revision?.revision).toBe(1);
    expect(live.results).toHaveLength(1);
    expect(['writer-a', 'writer-b']).toContain(live.results[0].id);
    expect(stages.results).toEqual([]);
  });

  it('preserves normal duplicates, deduplicates favorites, and appends in order', async () => {
    const duplicate = { name: 'Song', singer: 'Singer', source: 'tx', songmid: 'same' };
    const first = await handleUserPlaylistSave(saveRequest({
      baseRevision: 0,
      loveList: [duplicate, duplicate],
      userList: [{
        id: 'normal', name: 'Normal', mode: 'replace', position: 1,
        list: [duplicate, duplicate],
      }],
    }), testEnv, context);
    expect(first.status).toBe(200);

    const second = await handleUserPlaylistSave(saveRequest({
      baseRevision: 1,
      userList: [{
        id: 'normal', name: 'Normal', mode: 'append', position: 1,
        list: [{ name: 'Tail', singer: 'Singer', source: 'tx', songmid: 'tail' }],
      }],
    }), testEnv, context);
    expect(second.status).toBe(200);

    const love = await testEnv.DB.prepare(
      "SELECT songmid FROM playlist_songs WHERE user_id = 1 AND playlist_id = 'love'",
    ).all<{ songmid: string }>();
    const normal = await testEnv.DB.prepare(
      "SELECT songmid, position FROM playlist_songs WHERE user_id = 1 AND playlist_id = 'normal' ORDER BY position, id",
    ).all<{ songmid: string; position: number }>();
    expect(love.results).toEqual([{ songmid: 'same' }]);
    expect(normal.results).toEqual([
      { songmid: 'same', position: 0 },
      { songmid: 'same', position: 1 },
      { songmid: 'tail', position: 2 },
    ]);
  });

  it('rolls back live data and revision when the guarded commit fails', async () => {
    await testEnv.DB.prepare(
      `CREATE TRIGGER reject_live_song
       BEFORE INSERT ON playlist_songs
       WHEN NEW.playlist_id = 'blocked'
       BEGIN SELECT RAISE(FAIL, 'injected commit failure'); END`,
    ).run();

    const response = await handleUserPlaylistSave(saveRequest({
      baseRevision: 0,
      userList: [{
        id: 'blocked', name: 'Blocked', mode: 'replace', position: 1,
        list: [{ name: 'Song', singer: 'Singer', source: 'tx', songmid: 'one' }],
      }],
    }), testEnv, context);

    expect(response.status).toBe(500);
    const revision = await testEnv.DB.prepare(
      'SELECT revision FROM user_sync_state WHERE user_id = 1',
    ).first<{ revision: number }>();
    const live = await testEnv.DB.prepare(
      "SELECT id FROM playlists WHERE user_id = 1 AND id NOT LIKE '__stage__:%'",
    ).all<{ id: string }>();
    const stages = await testEnv.DB.prepare(
      "SELECT id FROM playlists WHERE user_id = 1 AND id LIKE '__stage__:%'",
    ).all<{ id: string }>();
    expect(revision?.revision).toBe(0);
    expect(live.results).toEqual([]);
    expect(stages.results).toEqual([]);
  });
});
