import { describe, expect, it } from 'vitest';
import type { Env } from '../src/lib/response';

import { insertStageSongs } from '../src/db/playlist-staging';

describe('playlist save integrity', () => {
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
});
