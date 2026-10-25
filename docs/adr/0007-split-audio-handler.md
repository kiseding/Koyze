# ADR 0007 — Splitting `audio_handler.dart`

- **Status:** Accepted
- **Date:** 2026-10-26
- **Context:** review item #7, "拆分 audio_handler.dart 上帝对象"

## Problem

`lib/core/audio/audio_handler.dart` had reached **4,085 lines / 196 members**.
`LxAudioHandler` performed, in one class:

1. `AudioHandler` protocol implementation (audio_service)
2. Native player lifecycle and rebuild
3. Queue bookkeeping (items, occurrence ids, current index)
4. URL resolution and cache-lease ownership
5. Interruption policy
6. Output-route recovery
7. Preload scheduling
8. Lazy/paged queue loading
9. Volume and ducking

Every one of those is a legitimate responsibility. The problem was not that the
class did too many *unrelated* things — it is an audio handler, they are all
audio-related — but that **no part of it could be read, tested or changed
without holding the other eight in your head at the same time**. A change to
lease release ordering required reasoning about the queue, the preload window
and the native player all at once.

## Decision

Extract **cohesive collaborators with narrow contracts**, not arbitrary slices.
Aim for units whose entire public surface can be described in one sentence and
which do not need to know about `MediaItem`, `AudioPlayer` or the handler's
generation counters.

Extracted so far:

| File | Lines | Responsibility |
| --- | --- | --- |
| `playback_volume_controller.dart` | 78 | App volume + duck state; writes the effective volume to a bound player |
| `playback_lease_registry.dart` | 284 | Ownership of every cache lease: pending resolutions, commit/discard, release tracking |
| `queue_occurrence_ledger.dart` | 99 | Monotonic queue-slot identity and `setQueue` reconciliation |
| `playback_interruption.dart` | 99 | Nested-interruption state machine (was already pure) |

`audio_handler.dart` is now **3,854 lines**. The line count is the least
interesting number here; what changed is that:

- The volume/duck state machine has 9 unit tests and no longer requires an
  `AudioHandler` to exercise.
- Lease ownership has 21 unit tests. Previously the only way to test a lease
  release was to drive a full playback session.
- Queue identity has 12 unit tests, including the duplicate-item case that the
  inlined loop got right by accident and nothing pinned down.
- The interruption policy can be read end to end without scrolling past 3,000
  lines of player plumbing.

## Alternatives considered

### Split by "layer" — `AudioHandlerQueue`, `AudioHandlerPlayback`, …

Rejected. These would be arbitrary horizontal slices of the same state, and
every method would still need access to `_queue`, `_player` and `_commands`.
The resulting classes would be as coupled as the original, just spread across
files, which makes the coupling harder rather than easier to see.

### Full rewrite around a state machine / event bus

Rejected for now. The handler's ordering invariants (generation bumps, source
request ownership, interruption gating) are load-bearing and were arrived at by
fixing real races — the test suite has ~1,600 tests pinning them. A rewrite
would discard that knowledge and take weeks to re-establish. Extraction is
incremental and each step is verified by the existing suite.

### Leave it alone

Rejected. 4,085 lines is past the point where a reviewer can hold the file in
working memory, which is exactly when the invariants start getting broken.

## What is deliberately *not* extracted

- **Output-route recovery.** It reads and writes `_commands`, `_player`,
  `mediaItem` and three generation counters, and its correctness is defined by
  how those interleave. Pulling it out today would require a 7-callback
  interface whose contract is harder to verify than the inlined code. Candidate
  for a later pass, once the player lifecycle is behind a smaller interface.
- **The queue itself.** 115 references to `_queue` across the file. Extracting
  the list without also extracting the index/current-item invariants would
  create two owners of the same state. The `QueueOccurrenceLedger` extraction is
  a first step: it takes the part of queue state that has a genuinely separate
  invariant (identity) and leaves the rest in place.

## Consequences

- `audio_handler.dart` re-exports the moved public types
  (`PlaybackStartProvenance`, `AudioInterruptionPolicy`, `InterruptionAction`,
  `duckedPlaybackVolumeFactor`) so the ~14 test files importing
  `audio_handler.dart` did not need to change. This is a compatibility shim;
  new code should import the specific file.
- Further extraction is now cheap: each collaborator added is a template for
  the next.
- The suite went from 1,586 to 1,628 tests, all passing, with no behavioural
  change.
