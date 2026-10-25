import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/playback_cache_service.dart';
import 'package:koyze/core/audio/playback_lease_registry.dart';

/// Minimal lease double: records releases and can be made to fail.
class _Lease {
  _Lease(this.path, {this.failOnRelease = false});

  final String path;
  final bool failOnRelease;
  var releaseCount = 0;

  PlaybackCacheLease asLease() {
    final uri = PlaybackCacheService.toPlayableUri(path);
    return PlaybackCacheLease.test(path, uri, () async {
      releaseCount++;
      if (failOnRelease) throw StateError('release failed for $path');
    });
  }
}

PlaybackResolution _streaming(String url) =>
    StreamingPlayback(url, const <String, dynamic>{});

PlaybackResolution _cached(PlaybackCacheLease lease, {String? cacheKey}) =>
    CachedPlayback(lease, {
      if (cacheKey != null) 'cacheKey': cacheKey,
    });

void main() {
  group('PlaybackLeaseRegistry staging', () {
    test('stage keeps the newest resolution for an occurrence', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();

      registry.stage(1, _cached(lease), claimLease: false);
      expect(registry.pendingCount, 1);
      expect(registry.pendingLeaseFor(1), same(lease));

      registry.stage(1, _streaming('https://example.com/b.mp3'), claimLease: false);
      expect(registry.pendingCount, 1);
      expect(registry.pendingLeaseFor(1), isNull);
    });

    test('re-staging the identical resolution does not release its lease', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();
      final resolution = _cached(lease);

      registry.stage(1, resolution, claimLease: false);
      registry.stage(1, resolution, claimLease: false);

      expect(lease.isReleased, isFalse);
    });

    test('replacing a pending resolution releases the superseded lease', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final oldLease = _Lease('/tmp/old.mp3').asLease();
      final newLease = _Lease('/tmp/new.mp3').asLease();

      registry.stage(1, _cached(oldLease), claimLease: false);
      registry.stage(1, _cached(newLease), claimLease: false);

      expect(oldLease.isReleased, isTrue);
      expect(newLease.isReleased, isFalse);
    });

    test('claimLease records the foreground cache key', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();

      registry.stage(1, _cached(lease, cacheKey: 'abc123'), claimLease: true);

      expect(registry.foregroundCacheKey, 'abc123');
      expect(registry.takeForegroundCacheKey(), 'abc123');
      expect(registry.foregroundCacheKey, isNull, reason: 'take clears it');
    });

    test('preload staging does not claim the lease or the cache key', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();

      registry.stage(1, _cached(lease, cacheKey: 'abc123'), claimLease: false);

      expect(registry.foregroundCacheKey, isNull);
      expect(registry.pendingLeaseFor(1), same(lease));
    });
  });

  group('PlaybackLeaseRegistry release bookkeeping', () {
    test('trackRelease swallows a failure until drained', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final fake = _Lease('/tmp/bad.mp3', failOnRelease: true);
      final lease = fake.asLease();

      registry.trackRelease(lease);
      // Must not throw here: a failing release cannot abort the caller's state
      // transition.
      await Future<void>.delayed(Duration.zero);
      expect(fake.releaseCount, 1);

      await expectLater(registry.drainReleases(), throwsStateError);
    });

    test('drainReleases is a no-op when everything succeeded', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/ok.mp3').asLease();

      registry.trackRelease(lease);
      await registry.drainReleases();

      expect(lease.isReleased, isTrue);
    });

    test('drainReleases reports the failure only once', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      registry.trackRelease(_Lease('/tmp/bad.mp3', failOnRelease: true).asLease());

      await expectLater(registry.drainReleases(), throwsStateError);
      await registry.drainReleases(); // cleared, so no second throw
    });

    test('releaseAll releases pending resolutions and the session', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final leaked = _Lease('/tmp/leaked.mp3').asLease();

      registry.stage(1, _cached(leaked), claimLease: false);
      await registry.releaseAll();

      expect(leaked.isReleased, isTrue);
      expect(registry.pendingCount, 0);
      expect(registry.foregroundCacheKey, isNull);
    });

    test('releaseAll still throws after releasing everything else', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final good = _Lease('/tmp/good.mp3').asLease();
      final bad = _Lease('/tmp/bad.mp3', failOnRelease: true).asLease();

      registry.stage(1, _cached(good), claimLease: false);
      registry.stage(2, _cached(bad), claimLease: false);

      await expectLater(registry.releaseAll(), throwsStateError);
      expect(good.isReleased, isTrue, reason: 'one failure must not skip the rest');
      expect(bad.isReleased, isTrue);
    });
  });

  group('PlaybackLeaseRegistry discard', () {
    test('discard releases the pending lease through the tracker', () async {
      var tracked = 0;
      final registry = PlaybackLeaseRegistry(
        trackOperation: (op) {
          tracked++;
          return op();
        },
      );
      final lease = _Lease('/tmp/a.mp3').asLease();
      registry.stage(1, _cached(lease), claimLease: false);

      registry.discard(1);
      await Future<void>.delayed(Duration.zero);

      expect(tracked, 1);
      expect(lease.isReleased, isTrue);
      expect(registry.pendingCount, 0);
    });

    test('discardAll releases every staged lease and clears the pending slot', () {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final a = _Lease('/tmp/a.mp3').asLease();
      final b = _Lease('/tmp/b.mp3').asLease();
      registry.stage(1, _cached(a), claimLease: false);
      registry.stage(2, _cached(b), claimLease: false);

      registry.discardAll();
      // The release is fire-and-forget; the lease flips to released at once.
      expect(a.isReleased, isTrue);
      expect(b.isReleased, isTrue);
      expect(registry.pendingCount, 0);
    });
  });

  group('PlaybackLeaseRegistry.commitStaged', () {
    test('commits when the generation is still current', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();
      registry.stage(1, _cached(lease), claimLease: true);
      var generation = 5;

      await registry.commitStaged(
        occurrenceId: 1,
        generation: 5,
        lease: lease,
        currentGeneration: () => generation,
      );

      expect(lease.isReleased, isFalse);
      expect(registry.pendingCount, 0);
    });

    test('discards the lease when the generation moved on', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();
      registry.stage(1, _cached(lease), claimLease: true);
      final generation = () => 9;

      await registry.commitStaged(
        occurrenceId: 1,
        generation: 5,
        lease: lease,
        currentGeneration: generation,
      );

      expect(lease.isReleased, isTrue);
      expect(registry.pendingCount, 0);
    });
  });

  group('PlaybackLeaseRegistry.takeLeaseForUrl', () {
    test('returns the lease when the URL matches the lease path', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();
      registry.stage(1, _cached(lease), claimLease: false);

      final taken = await registry.takeLeaseForUrl(
        1,
        PlaybackCacheService.toPlayableUri('/tmp/a.mp3'),
      );

      expect(taken, same(lease));
      expect(registry.pendingCount, 1, reason: 'a match retains the entry');
    });

    test('discards and returns null when the URL points elsewhere', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      final lease = _Lease('/tmp/a.mp3').asLease();
      registry.stage(1, _cached(lease), claimLease: false);

      final taken = await registry.takeLeaseForUrl(
        1,
        PlaybackCacheService.toPlayableUri('/tmp/other.mp3'),
      );

      expect(taken, isNull);
      expect(lease.isReleased, isTrue);
      expect(registry.pendingCount, 0);
    });

    test('returns null for an unknown occurrence', () async {
      final registry = PlaybackLeaseRegistry(trackOperation: (op) => op());
      expect(
        await registry.takeLeaseForUrl(42, 'file:///tmp/a.mp3'),
        isNull,
      );
    });
  });

  group('PlaybackLeaseRegistry.cacheKeyFromLeasePath', () {
    test('extracts the 40-hex stable name', () {
      const key = '0123456789abcdef0123456789abcdef01234567';
      expect(
        PlaybackLeaseRegistry.cacheKeyFromLeasePath('/cache/$key.mp3'),
        key,
      );
    });

    test('returns null for a non-stable filename', () {
      expect(
        PlaybackLeaseRegistry.cacheKeyFromLeasePath('/cache/song.mp3'),
        isNull,
      );
    });
  });

  group('PlaybackLeaseRegistry.leaseMatchesUrl', () {
    test('is false for non-file URLs', () {
      final lease = _Lease('/tmp/a.mp3').asLease();
      expect(
        PlaybackLeaseRegistry.leaseMatchesUrl(lease, 'https://x/a.mp3'),
        isFalse,
      );
    });

    test('is true for the exact playable URI', () {
      final lease = _Lease('/tmp/a.mp3').asLease();
      expect(
        PlaybackLeaseRegistry.leaseMatchesUrl(lease, lease.playableUri),
        isTrue,
      );
    });
  });
}
