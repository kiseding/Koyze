import { describe, expect, it, vi } from 'vitest';
import type { Env } from '../src/lib/response';
import { requireSyncRevision } from '../src/db/sync-state';

describe('sync revision claims', () => {
  it('accepts exactly the expected revision', async () => {
    const run = vi.fn(async () => ({ meta: { changes: 1 } }));
    const env = {
      DB: {
        prepare: () => ({ bind: () => ({ run, first: async () => ({ revision: 7 }) }) }),
      },
    } as unknown as Env;

    await expect(requireSyncRevision(env, 1, 7)).resolves.toEqual({
      ok: true,
      revision: 7,
      claimed: false,
    });
  });

  it('reports the current revision for a stale writer', async () => {
    const env = {
      DB: {
        prepare: (sql: string) => ({
          bind: () => ({
            run: async () => ({ meta: { changes: 1 } }),
            first: async () => ({ revision: 9 }),
          }),
        }),
      },
    } as unknown as Env;

    await expect(requireSyncRevision(env, 1, 7)).resolves.toEqual({
      ok: false,
      revision: 9,
      claimed: false,
    });
  });
});
