import { applyD1Migrations, env } from 'cloudflare:test';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { IncomingSyncEvent } from '../src/db/sync-events';
import {
  appendSyncEvents,
  compactSyncEvents,
  pullSyncEvents,
  syncEventWatermark,
} from '../src/db/sync-events';
import type { Env } from '../src/lib/response';

vi.mock('../src/utils/auth', () => ({
  getUserId: async () => 1,
}));

import { handleSyncPull, handleSyncPush } from '../src/routes/user/sync-events';

type TestEnv = Env & { TEST_MIGRATIONS: D1Migration[] };

function event(
  eventId: string,
  eventType: string,
  entityId: string,
  payload: Record<string, unknown>,
): IncomingSyncEvent {
  return {
    eventId,
    deviceId: 'device-a',
    localUserId: 'local-a',
    eventType,
    entityId,
    payload,
    createdAt: Date.now(),
  };
}

describe('transactional sync events', () => {
  const testEnv = env as TestEnv;

  beforeEach(async () => {
    await applyD1Migrations(testEnv.DB, testEnv.TEST_MIGRATIONS);
    await testEnv.DB.prepare('DROP TRIGGER IF EXISTS reject_setting_projection').run();
    await testEnv.DB.prepare('DELETE FROM users').run();
    await testEnv.DB.prepare(
      "INSERT INTO users (id, username, password_hash) VALUES (1, 'event-user', 'hash')",
    ).run();
  });

  it('applies an event exactly once and advances revision exactly once', async () => {
    const add = event('favorite-1', 'favorite.add', 'favorite-item-1', {
      song: { name: 'Song', singer: 'Singer', source: 'tx', songmid: 'song-1' },
    });

    await appendSyncEvents(testEnv, 1, [add]);
    await appendSyncEvents(testEnv, 1, [add]);

    const events = await testEnv.DB.prepare(
      'SELECT event_id, applied_at FROM sync_events WHERE user_id = 1',
    ).all<{ event_id: string; applied_at: string | null }>();
    const songs = await testEnv.DB.prepare(
      "SELECT songmid FROM playlist_songs WHERE user_id = 1 AND playlist_id = 'love'",
    ).all<{ songmid: string }>();
    const state = await testEnv.DB.prepare(
      'SELECT revision FROM user_sync_state WHERE user_id = 1',
    ).first<{ revision: number }>();
    expect(events.results).toHaveLength(1);
    expect(events.results[0].applied_at).not.toBeNull();
    expect(songs.results).toEqual([{ songmid: 'song-1' }]);
    expect(state?.revision).toBe(1);
  });

  it('preserves duplicate occurrences in normal playlists', async () => {
    await appendSyncEvents(testEnv, 1, [
      event('create-1', 'playlist.create', 'normal', { name: 'Normal' }),
      event('item-1', 'playlist_item.add', 'occurrence-1', {
        playlistId: 'normal',
        song: { name: 'Same', singer: 'Singer', source: 'tx', songmid: 'same' },
      }),
      event('item-2', 'playlist_item.add', 'occurrence-2', {
        playlistId: 'normal',
        song: { name: 'Same', singer: 'Singer', source: 'tx', songmid: 'same' },
      }),
    ]);

    const rows = await testEnv.DB.prepare(
      `SELECT songmid, playlist_item_id, position FROM playlist_songs
       WHERE user_id = 1 AND playlist_id = 'normal' ORDER BY position`,
    ).all<{ songmid: string; playlist_item_id: string; position: number }>();
    expect(rows.results).toEqual([
      { songmid: 'same', playlist_item_id: 'occurrence-1', position: 0 },
      { songmid: 'same', playlist_item_id: 'occurrence-2', position: 1 },
    ]);
  });

  it('does not resurrect a favorite when an old add is retried after removal', async () => {
    const song = { name: 'Song', singer: 'Singer', source: 'tx', songmid: 'song-1' };
    const add = event('favorite-add', 'favorite.add', 'favorite-item', { song });
    await appendSyncEvents(testEnv, 1, [add]);
    await appendSyncEvents(testEnv, 1, [
      event('favorite-remove', 'favorite.remove', 'favorite-item', { song }),
    ]);
    await appendSyncEvents(testEnv, 1, [add]);

    const songs = await testEnv.DB.prepare(
      "SELECT id FROM playlist_songs WHERE user_id = 1 AND playlist_id = 'love'",
    ).all<{ id: number }>();
    const tombstone = await testEnv.DB.prepare(
      `SELECT server_sequence FROM sync_tombstones
       WHERE user_id = 1 AND entity_type = 'favorite' AND entity_id = 'favorite-item'`,
    ).first<{ server_sequence: number }>();
    expect(songs.results).toEqual([]);
    expect(tombstone?.server_sequence).toBeGreaterThan(0);
  });

  it('keeps an idempotency receipt after compaction and never replays the event', async () => {
    const song = { name: 'Song', singer: 'Singer', source: 'tx', songmid: 'song-1' };
    const add = event('favorite-add-compacted', 'favorite.add', 'favorite-item', { song });
    await appendSyncEvents(testEnv, 1, [add]);
    await appendSyncEvents(testEnv, 1, [
      event('favorite-remove-compacted', 'favorite.remove', 'favorite-item', { song }),
    ]);
    await appendSyncEvents(testEnv, 1, [
      event('unrelated-setting', 'setting.set', 'theme', { value: 'dark' }),
    ]);
    await compactSyncEvents(testEnv, 1, 1);

    const compactedEvent = await testEnv.DB.prepare(
      'SELECT id FROM sync_events WHERE user_id = 1 AND event_id = ?',
    ).bind(add.eventId).first<{ id: number }>();
    const receipt = await testEnv.DB.prepare(
      'SELECT server_sequence FROM sync_event_receipts WHERE user_id = 1 AND event_id = ?',
    ).bind(add.eventId).first<{ server_sequence: number }>();
    expect(compactedEvent).toBeNull();
    expect(receipt?.server_sequence).toBeGreaterThan(0);

    await appendSyncEvents(testEnv, 1, [add]);
    const songs = await testEnv.DB.prepare(
      "SELECT id FROM playlist_songs WHERE user_id = 1 AND playlist_id = 'love'",
    ).all<{ id: number }>();
    expect(songs.results).toEqual([]);
  });

  it('rejects reuse of an event id for different content', async () => {
    const original = event('collision', 'setting.set', 'theme', { value: 'dark' });
    await appendSyncEvents(testEnv, 1, [original]);

    const request = new Request('https://worker.test/api/sync/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '203.0.113.212',
      },
      body: JSON.stringify({
        deviceId: original.deviceId,
        events: [{ ...original, payload: { value: 'light' } }],
      }),
    });
    const response = await handleSyncPush(request, testEnv);
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toEqual({
      error: 'sync_event_id_conflict',
      eventId: original.eventId,
    });
  });

  it('rolls back the event log, projection, and revision when apply fails', async () => {
    await testEnv.DB.prepare(
      `CREATE TRIGGER reject_setting_projection
       BEFORE INSERT ON sync_setting_projections
       BEGIN SELECT RAISE(FAIL, 'injected projection failure'); END`,
    ).run();

    await expect(appendSyncEvents(testEnv, 1, [
      event('setting-1', 'setting.set', 'theme', { value: 'dark' }),
    ])).rejects.toThrow();

    const logged = await testEnv.DB.prepare(
      'SELECT event_id FROM sync_events WHERE user_id = 1',
    ).all<{ event_id: string }>();
    const projected = await testEnv.DB.prepare(
      'SELECT key FROM sync_setting_projections WHERE user_id = 1',
    ).all<{ key: string }>();
    const state = await testEnv.DB.prepare(
      'SELECT revision FROM user_sync_state WHERE user_id = 1',
    ).first<{ revision: number }>();
    expect(logged.results).toEqual([]);
    expect(projected.results).toEqual([]);
    expect(state?.revision).toBe(0);
  });

  it('returns a snapshot-required conflict for a compacted cursor', async () => {
    await appendSyncEvents(testEnv, 1, [
      event('setting-1', 'setting.set', 'one', { value: '1' }),
      event('setting-2', 'setting.set', 'two', { value: '2' }),
      event('setting-3', 'setting.set', 'three', { value: '3' }),
      event('setting-4', 'setting.set', 'four', { value: '4' }),
    ]);
    await compactSyncEvents(testEnv, 1, 2);
    const watermark = await syncEventWatermark(testEnv, 1);

    const request = new Request('https://worker.test/api/sync/pull?cursor=0');
    const response = await handleSyncPull(request, new URL(request.url), testEnv);
    expect(response.status).toBe(409);
    await expect(response.json()).resolves.toMatchObject({
      error: 'sync_cursor_expired',
      snapshotRequired: true,
      compactedThrough: watermark,
    });
  });

  it('paginates from the exact compaction boundary without skipping retained events', async () => {
    await appendSyncEvents(testEnv, 1, [
      event('page-1', 'setting.set', 'theme', { value: 'one' }),
      event('page-2', 'setting.set', 'theme', { value: 'two' }),
      event('page-3', 'setting.set', 'theme', { value: 'three' }),
    ]);
    await compactSyncEvents(testEnv, 1, 2);
    const boundary = await syncEventWatermark(testEnv, 1);
    const first = await pullSyncEvents(testEnv, 1, boundary, 1);
    expect(first.expired).toBe(false);
    if (first.expired) throw new Error('boundary must remain readable');
    expect(first.hasMore).toBe(true);
    expect(first.events.map((row) => row.eventId)).toEqual(['page-2']);
    const second = await pullSyncEvents(testEnv, 1, first.cursor, 1);
    if (second.expired) throw new Error('next page must remain readable');
    expect(second.hasMore).toBe(false);
    expect(second.events.map((row) => row.eventId)).toEqual(['page-3']);
    await expect(pullSyncEvents(testEnv, 1, second.cursor, 1)).resolves.toEqual({
      expired: false, cursor: second.cursor, events: [], hasMore: false,
    });
  });

  it('enforces the sync push account/IP rate limit through the real Durable Object', async () => {
    const makeRequest = () => new Request('https://worker.test/api/sync/push', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'CF-Connecting-IP': '203.0.113.211',
      },
      body: JSON.stringify({ deviceId: 'rate-device', events: [] }),
    });

    for (let attempt = 0; attempt < 60; attempt += 1) {
      const response = await handleSyncPush(makeRequest(), testEnv);
      expect(response.status).toBe(200);
    }
    const denied = await handleSyncPush(makeRequest(), testEnv);
    expect(denied.status).toBe(429);
    expect(denied.headers.get('Retry-After')).toMatch(/^\d+$/);
    await expect(denied.json()).resolves.toMatchObject({ error: 'sync_rate_limited' });
  });
});
