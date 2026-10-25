import 'dart:async';
import 'dart:io';

import 'playback_cache_service.dart';

/// Runs an internal async operation under the handler's error-tracking scope.
///
/// The handler owns the "collect the first failure, rethrow it during
/// `dispose`" policy; the registry only needs somewhere to hand work off.
typedef AsyncOperationTracker =
    Future<void> Function(Future<void> Function() operation);

/// Owns every cache lease the audio handler has taken ownership of.
///
/// Extracted from `LxAudioHandler` to shrink it: a lease must stay alive from
/// the moment a resolver hands it over until the source playing from that file
/// is either committed or discarded, and that bookkeeping had grown into ~200
/// lines interleaved with queue logic. Nothing here knows about media items,
/// playback generations or the native player, which is what makes it testable
/// on its own.
///
/// Two independent things are tracked:
///
/// * **Pending resolutions** — the resolver result for a queue occurrence that
///   has not been committed to the native player yet. Keyed by occurrence, not
///   by media id, so a queue holding the same track twice cannot
///   cross-contaminate the two entries.
/// * **The active lease session** — at most one lease is authoritative (the
///   file the player is currently reading) plus at most one staged
///   replacement, managed by [PlaybackLeaseSession].
///
/// Leases dropped on the floor (superseded resolutions, generation bumps,
/// teardown) go through [trackRelease], which records the first failure rather
/// than throwing: a failing release must not abort the caller's state
/// transition. [drainReleases] surfaces that failure later, at a point where
/// it can still be reported.
class PlaybackLeaseRegistry {
  PlaybackLeaseRegistry({required this.trackOperation});

  final AsyncOperationTracker trackOperation;
  final PlaybackLeaseSession _session = PlaybackLeaseSession();
  final Map<int, PlaybackResolution> _pending = {};
  final Set<Future<void>> _inflightReleases = {};
  Object? _lateReleaseError;
  StackTrace? _lateReleaseStackTrace;

  String? _foregroundCacheKey;

  /// Cache key of the foreground resolution, used to evict a corrupt cache
  /// file after a failed source install.
  String? get foregroundCacheKey => _foregroundCacheKey;

  /// Clears and returns the foreground cache key, so the caller can cancel the
  /// in-flight download exactly once.
  String? takeForegroundCacheKey() {
    final key = _foregroundCacheKey;
    _foregroundCacheKey = null;
    return key;
  }

  int get pendingCount => _pending.length;

  PlaybackResolution? pendingFor(int occurrenceId) => _pending[occurrenceId];

  PlaybackCacheLease? pendingLeaseFor(int occurrenceId) =>
      _pending[occurrenceId]?.leaseOrNull;

  Map<String, String>? requestHeadersFor(int occurrenceId) =>
      _pending[occurrenceId]?.requestHeaders;

  /// Stores [resolution] as the pending result for [occurrenceId].
  ///
  /// Any resolution previously staged for the same occurrence is released
  /// unless it is literally the same object (re-accepting an identical result
  /// must not release the lease out from under it).
  ///
  /// [claimLease] moves the resolution's lease into the authoritative session,
  /// which is what the foreground path wants. Preloads pass `false`: their
  /// lease is held by the pending resolution alone so that committing a
  /// preloaded item later cannot silently displace the lease of the track that
  /// is currently playing.
  void stage(
    int occurrenceId,
    PlaybackResolution resolution, {
    required bool claimLease,
  }) {
    final previous = _pending.remove(occurrenceId);
    final previousLease = previous?.leaseOrNull;
    if (previousLease != null &&
        !identical(previousLease, resolution.leaseOrNull)) {
      trackRelease(previousLease);
    }
    _pending[occurrenceId] = resolution;
    final lease = resolution.leaseOrNull;
    if (claimLease && lease != null) {
      _session.holdPending(lease);
    }
    if (claimLease) {
      final key = resolution.qualityExtras['cacheKey']?.toString();
      if (key != null && key.isNotEmpty) {
        _foregroundCacheKey = key;
      }
    }
  }

  /// Drops the pending resolution for [occurrenceId], releasing its lease.
  void discard(int occurrenceId) {
    final resolution = _pending.remove(occurrenceId);
    final lease = resolution?.leaseOrNull;
    if (lease != null) {
      trackOperation(() => _session.discardPending(lease));
    }
  }

  /// Drops every pending resolution and clears the authoritative session's
  /// pending slot.
  void discardAll() {
    final resolutions = _pending.values.toList(growable: false);
    _pending.clear();
    for (final resolution in resolutions) {
      trackRelease(resolution.leaseOrNull);
    }
    _session.holdPending(null);
  }

  /// Makes [lease] the staged lease of the active session, or clears the
  /// staged slot when [lease] is null.
  void holdPending(PlaybackCacheLease? lease) => _session.holdPending(lease);

  /// Commits a staged lease only if [generation] is still current.
  ///
  /// [currentGeneration] is read at commit time rather than captured, so a
  /// generation bump that happens while the native player is being configured
  /// still discards the lease instead of installing a stale file.
  Future<void> commitStaged({
    required int occurrenceId,
    required int generation,
    required PlaybackCacheLease? lease,
    required int Function() currentGeneration,
  }) async {
    _pending.remove(occurrenceId);
    await _session.commitIfGeneration(
      generation: generation,
      currentGeneration: currentGeneration,
      lease: lease,
    );
  }

  /// Drops the pending resolution for [occurrenceId] plus [lease] if it is a
  /// different object, releasing both.
  Future<void> discardStaged(int occurrenceId, PlaybackCacheLease? lease) async {
    final resolution = _pending.remove(occurrenceId);
    final resolvedLease = resolution?.leaseOrNull;
    if (resolvedLease != null) {
      await _session.discardPending(resolvedLease);
    }
    if (lease != null && !identical(lease, resolvedLease)) {
      await _session.discardPending(lease);
    }
  }

  /// Returns the staged lease for [occurrenceId] if it points at [url],
  /// otherwise discards it and returns null.
  ///
  /// The lease path and the URL the player is about to open are produced by
  /// different code paths and disagree on Windows path spelling (drive-letter
  /// vs POSIX form), so the comparison has to normalise rather than string
  /// match. A mismatch means the staged file is not the one about to play, and
  /// keeping it alive would pin a cache entry for no reason.
  Future<PlaybackCacheLease?> takeLeaseForUrl(
    int occurrenceId,
    String url,
  ) async {
    final lease = _pending[occurrenceId]?.leaseOrNull;
    if (lease == null) return null;
    if (!lease.isReleased && leaseMatchesUrl(lease, url)) return lease;
    await discardStaged(occurrenceId, lease);
    return null;
  }

  /// Records a fire-and-forget lease release, keeping only the first failure.
  void trackRelease(PlaybackCacheLease? lease) {
    if (lease == null) return;
    final release = Future<void>.sync(lease.release);
    final tracked = release.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _lateReleaseError ??= error;
        _lateReleaseStackTrace ??= stackTrace;
      },
    );
    _inflightReleases.add(tracked);
    tracked.whenComplete(() => _inflightReleases.remove(tracked)).ignore();
  }

  /// Waits for in-flight releases and rethrows the first failure, if any.
  Future<void> drainReleases() async {
    while (_inflightReleases.isNotEmpty) {
      await Future.wait(_inflightReleases.toList(growable: false));
    }
    if (_lateReleaseError case final error?) {
      final stackTrace = _lateReleaseStackTrace!;
      _lateReleaseError = null;
      _lateReleaseStackTrace = null;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Releases the authoritative lease, the staged lease and every lease still
  /// held by a pending resolution.
  Future<void> releaseAll() async {
    final resolutionLeases = _pending.values
        .map((resolution) => resolution.leaseOrNull)
        .whereType<PlaybackCacheLease>()
        .toSet();
    _pending.clear();
    _foregroundCacheKey = null;
    Object? firstError;
    StackTrace? firstStackTrace;
    Future<void> release(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await release(_session.releaseAll);
    for (final lease in resolutionLeases) {
      await release(lease.release);
    }
    if (firstError case final error?) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  static final _stableCacheKey = RegExp(r'^([0-9a-f]{40})\.');

  /// Recovers the cache key from a lease path.
  ///
  /// Stable cache files are named `<40 hex>.<ext>`, which is the only place
  /// the key survives once a lease has been handed over — the resolution that
  /// created it may already be gone by the time a corrupted file needs
  /// evicting.
  static String? cacheKeyFromLeasePath(String path) {
    final name = path.contains('/')
        ? path.substring(path.lastIndexOf('/') + 1)
        : path;
    final match = _stableCacheKey.firstMatch(name);
    return match?.group(1);
  }

  /// Whether [lease] refers to the file at [url].
  static bool leaseMatchesUrl(PlaybackCacheLease lease, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'file') return false;
    // Resolver-owned leases normally return their own URI. Keep this exact
    // check first; it also preserves POSIX-style test paths on Windows, where
    // Uri.toFilePath() assigns the current drive to a leading slash path.
    if (url == lease.playableUri) return true;
    try {
      String comparablePath(String path) => path.replaceAll('\\', '/');

      var uriPath = comparablePath(uri.toFilePath());
      var leasePath = comparablePath(lease.path);
      final uriHasDrive = RegExp(r'^[A-Za-z]:/').hasMatch(uriPath);
      final leaseHasDrive = RegExp(r'^[A-Za-z]:/').hasMatch(leasePath);
      // A URI parsed from `/cache/song.mp3` becomes `C:/cache/song.mp3` on
      // Windows, while a lease created from the original POSIX spelling keeps
      // `/cache/song.mp3`. Remove the synthetic drive only for this mixed form;
      // real drive-qualified paths remain strict and cannot cross-match.
      if (Platform.isWindows && uriHasDrive != leaseHasDrive) {
        if (uriHasDrive) uriPath = uriPath.substring(2);
        if (leaseHasDrive) leasePath = leasePath.substring(2);
      }
      return Platform.isWindows
          ? uriPath.toLowerCase() == leasePath.toLowerCase()
          : uriPath == leasePath;
    } on FormatException {
      return false;
    }
  }
}
