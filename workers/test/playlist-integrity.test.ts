import { describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/lib/response';

vi.mock('../src/utils/auth', () => ({
  getUserId: async () => 1,
}));

import { insertStageSongs } from '../src/db/playlist-staging';
import { handleUserPlaylistSave } from '../src/routes/user/playlist';

function request(body: Record<string, unknown>): Request {
  return new Request('https://worker.test/api/user/list', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

const context = {
  waitUntil: () => undefined,
  passThroughOnException: () => undefined,
  props: {},
} as unknown as ExecutionContext;

describe('playlist save integrity', () => {
  it('does not clear favorites when loveList is omitted', async () => {
    const prepare = vi.fn(() => {
      throw new Error('playlist storage must not be touched');
    });
    const response = await handleUserPlaylistSave(
      request({}),
      { DB: { prepare } } as unknown as Env,
      context,
    );

    expect(response.status).toBe(200);
    expect(prepare).not.toHaveBeenCalled();
  });

  it('clears favorites only for an explicit empty loveList', async () => {
    const run = vi.fn(async () => undefined);
    const bind = vi.fn(() => ({ run, first: async () => ({ revision: 1 }) }));
    const prepare = vi.fn(() => ({ bind }));
    const response = await handleUserPlaylistSave(
      request({ loveList: [] }),
      {
        DB: { prepare },
        CACHE: { delete: async () => undefined },
      } as unknown as Env,
      context,
    );

    expect(response.status).toBe(200);
    expect(prepare).toHaveBeenCalledWith(
      'DELETE FROM playlist_songs WHERE playlist_id = ? AND user_id = ?',
    );
    expect(run).toHaveBeenCalledTimes(3);
  });

  it('preserves duplicate occurrences in normal playlist staging', async () => {
    const statements: unknown[] = [];
    const env = {
      DB: {
        prepare: () => ({ bind: (...values: unknown[]) => values }),
        batch: async (batch: unknown[]) => { statements.push(...batch); },
      },
    } as unknown as Env;
    const duplicate = { name: 'Song', songmid: 'same', source: 'tx' };

    await insertStageSongs(env, 'stage', 1, [duplicate, duplicate]);

    expect(statements).toHaveLength(2);
  });

  it('deduplicates favorite playlist staging', async () => {
    const statements: unknown[] = [];
    const env = {
      DB: {
        prepare: () => ({ bind: (...values: unknown[]) => values }),
        batch: async (batch: unknown[]) => { statements.push(...batch); },
      },
    } as unknown as Env;
    const duplicate = { name: 'Song', songmid: 'same', source: 'tx' };

    await insertStageSongs(env, 'stage', 1, [duplicate, duplicate], 0, true);

    expect(statements).toHaveLength(1);
  });

  it('appends after the current playlist tail when mode is append', async () => {
    const sqlCalls: string[] = [];
    const env = {
      DB: {
        prepare: (sql: string) => {
          sqlCalls.push(sql);
          const runnable = async () => ({ meta: { changes: 1 } });
          return {
            bind: (...values: unknown[]) => ({
              all: async () => ({ results: [] }),
              first: async () => ({ m: 4 }),
              run: runnable,
            }),
            run: runnable,
          };
        },
        batch: async () => [],
      },
      CACHE: { delete: async () => undefined },
    } as unknown as Env;

    const response = await handleUserPlaylistSave(
      request({
        userList: [
          {
            id: 'road-trip',
            name: 'Road Trip',
            mode: 'append',
            position: 1,
            list: [{ name: 'N', singer: 'S', source: 'tx', songmid: 'm1' }],
          },
        ],
      }),
      env,
      context,
    );

    expect(response.status).toBe(200);
    expect(sqlCalls.some((sql) => sql.includes('MAX(position)'))).toBe(true);
  });
});
