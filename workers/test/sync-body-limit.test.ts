import { describe, expect, it } from 'vitest';
import {
  MAX_SYNC_BODY_BYTES,
  MAX_SYNC_STATE_BODY_BYTES,
  readJsonRequest,
} from '../src/lib/response';

/**
 * Custom-source events carry the whole script and the client allows a 2 MiB
 * script, so a single sync event can be far larger than the 256 KiB default
 * body limit. These tests pin the widened ceilings so a future refactor cannot
 * silently reintroduce the 413 that stalled every device.
 */

function jsonRequest(payload: unknown, contentType = 'application/json'): Request {
  return new Request('https://example.com/api/user/sync/events', {
    method: 'POST',
    headers: { 'Content-Type': contentType },
    body: JSON.stringify(payload),
  });
}

/** Roughly a 1.5 MiB custom-source upsert — the client's per-event budget. */
function oversizedEventBody(scriptBytes = 1536 * 1024): Record<string, unknown> {
  return {
    deviceId: 'device_1',
    events: [
      {
        eventId: 'evt_huge',
        eventType: 'custom_source.upsert',
        entityId: 'src_huge',
        payload: { source: { id: 'src_huge', script: 'a'.repeat(scriptBytes) } },
      },
    ],
  };
}

describe('sync body limits', () => {
  it('accepts a 1.5 MiB event under the sync ceiling', async () => {
    const result = await readJsonRequest(
      jsonRequest(oversizedEventBody()),
      MAX_SYNC_BODY_BYTES,
    );

    expect(result).not.toBeInstanceOf(Response);
    expect('body' in result).toBe(true);
  });

  it('still rejects the same event under the default ceiling', async () => {
    // Proves the per-route override is what makes the sync path work, and that
    // every other endpoint keeps the 256 KiB default.
    const result = await readJsonRequest(jsonRequest(oversizedEventBody()));

    expect(result).toBeInstanceOf(Response);
    expect((result as Response).status).toBe(413);
  });

  it('gives the full-state upload more room than a single event', async () => {
    const manySources = {
      deviceId: 'device_1',
      sources: Array.from({ length: 4 }, (_, index) => ({
        id: `src_${index}`,
        script: 'a'.repeat(1024 * 1024),
      })),
    };
    const request = jsonRequest(manySources);

    expect(MAX_SYNC_STATE_BODY_BYTES).toBeGreaterThan(MAX_SYNC_BODY_BYTES);
    expect(
      await readJsonRequest(request, MAX_SYNC_BODY_BYTES),
    ).toBeInstanceOf(Response);
    const result = await readJsonRequest(
      jsonRequest(manySources),
      MAX_SYNC_STATE_BODY_BYTES,
    );
    expect(result).not.toBeInstanceOf(Response);
    expect('body' in result).toBe(true);
  });

  it('keeps the JSON content-type requirement on the widened path', async () => {
    const result = await readJsonRequest(
      jsonRequest(oversizedEventBody(), 'text/plain'),
      MAX_SYNC_BODY_BYTES,
    );

    expect(result).toBeInstanceOf(Response);
    expect((result as Response).status).toBe(400);
  });
});
