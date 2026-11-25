import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../features/lyric/domain/lyric.dart';
import '../../features/lyric/data/lyric_parser.dart';
import '../../features/player/domain/music_item.dart';
import '../../features/custom_source/domain/custom_source_service.dart';
import '../../features/source_check/domain/source_check_policy.dart';
import '../../features/nas/domain/nas_kind.dart';
import '../../features/nas/domain/nas_service.dart';
import '../../features/nas/domain/nas_url.dart';
import '../../features/subsonic/domain/subsonic_service.dart';
import '../../features/subsonic/domain/subsonic_url.dart';
import '../music_source/platform/built_in_source_manager.dart';
import 'play_url_result.dart';
import 'outbound_url.dart';
import '../logging/app_log.dart';

typedef QualityResolver =
    Future<PlayUrlResult?> Function(
      MusicItem music,
      String quality,
      CancelToken? cancelToken,
    );
typedef CustomSourceQualityResolver =
    Future<PlayUrlResult?> Function(
      String sourceId,
      MusicItem music,
      String quality,
      CancelToken? cancelToken,
    );

class _QualityAttempt {
  final PlayUrlResult result;
  final int sourceIndex;
  final int candidateIndex;
  final String songId;

  const _QualityAttempt({
    required this.result,
    required this.sourceIndex,
    required this.candidateIndex,
    this.songId = '',
  });
}

class MusicSourceService {
  static const fallbackPlatforms = ['tx', 'kw', 'wy', 'kg'];
  static const _customFailureCooldown = Duration(seconds: 5);
  final Duration lyricSourceTimeout;

  final CustomSourceService _customSourceService;

  /// 音源检测结论，用来决定选源顺序；为空时按脚本启用顺序尝试。
  final SourceCheckPolicy? sourceCheckPolicy;
  final BuiltInSourceManager _builtInSources;
  final bool Function()? _hasEnabledCustomSources;
  final List<String> Function()? _enabledCustomSourceIds;
  final QualityResolver? _customQualityResolver;
  final CustomSourceQualityResolver? _customSourceQualityResolver;
  final SubsonicService? _subsonicService;
  final Map<NasKind, NasService> _nasServices;
  final Duration playUrlResolutionTimeout;
  final Map<String, Future<({String url, String? type})?>> _customUrlRequests =
      {};
  final Map<String, DateTime> _customFailureUntil = {};

  MusicSourceService(
    this._customSourceService, {
    this.sourceCheckPolicy,
    bool Function()? hasEnabledCustomSources,
    List<String> Function()? enabledCustomSourceIds,
    QualityResolver? customQualityResolver,
    CustomSourceQualityResolver? customSourceQualityResolver,
    BuiltInSourceManager? builtInSources,
    SubsonicService? subsonicService,
    Map<NasKind, NasService>? nasServices,
    this.playUrlResolutionTimeout = const Duration(seconds: 30),
    this.lyricSourceTimeout = const Duration(seconds: 18),
  }) : _hasEnabledCustomSources = hasEnabledCustomSources,
       _enabledCustomSourceIds = enabledCustomSourceIds,
       _customQualityResolver = customQualityResolver,
       _customSourceQualityResolver = customSourceQualityResolver,
       _builtInSources = builtInSources ?? BuiltInSourceManager(),
       _subsonicService = subsonicService,
       _nasServices = nasServices ?? const {};

  BuiltInSourceManager get builtInSources => _builtInSources;

  /// 是否有用户启用的音源。
  ///
  /// 本项目不内置任何音频地址解析，这里为 false 时所有在线歌曲都无法播放。
  bool get hasEnabledCustomSource =>
      _hasEnabledCustomSources?.call() ??
      _customSourceService.enabledSources.isNotEmpty;

  /// 从高到低的音质降级链。优先 preferred，再依次更低档。
  static const qualityRank = [
    'hires',
    'flac24bit',
    'flac',
    '320k',
    '192k',
    '128k',
  ];

  static const _fallbackQualityRank = [
    'hires',
    'flac24bit',
    'flac',
    '320k',
    '128k',
  ];

  static List<String> qualityChain(String preferred) {
    final p = preferred.isEmpty ? '320k' : preferred;
    if (p == '192k') return ['192k', '128k'];
    final start = _fallbackQualityRank.indexOf(p);
    if (start < 0) {
      return [p, ..._fallbackQualityRank.where((q) => q != p)];
    }
    return _fallbackQualityRank.sublist(start);
  }

  static int qualityRankIndex(String q) {
    final i = qualityRank.indexOf(q);
    return i < 0 ? qualityRank.length : i;
  }

  static List<String> uniqueQualityCandidates(
    String preferred, {
    required String? Function(String quality) attemptKey,
    List<String>? candidates,
  }) {
    final seen = <String>{};
    return (candidates ?? qualityChain(preferred)).where((quality) {
      final key = attemptKey(quality);
      return key != null && seen.add(key);
    }).toList();
  }

  /// actual 是否明显低于 requested（用于拒绝“假成功”低码率 URL）
  static bool isQualityBelow(String actual, String requested) {
    return qualityRankIndex(actual) > qualityRankIndex(requested);
  }

  Future<List<MusicItem>> search(
    String keyword, {
    String? customSourceId,
    int page = 1,
    int limit = 20,
    String type = 'music',
  }) async {
    final platform = customSourceId ?? 'kw';
    final enabledCustomSources = _customSourceService.enabledSources;

    if (enabledCustomSources.isNotEmpty) {
      try {
        final results = await _customSourceService
            .searchWithSource(
              enabledCustomSources.first.id,
              keyword,
              source: platform,
              page: page,
              limit: limit,
              type: type,
            )
            .timeout(const Duration(seconds: 15));
        if (results.isNotEmpty) {
          return results;
        }
      } catch (e) {
        // Custom source search error, continue to built-in
      }
    }

    if (platform == 'all') {
      return _searchAllPlatforms(keyword, page: page, limit: limit);
    }

    if (type == 'songlist') {
      final builtInResult = await _builtInSources.searchSongLists(
        platform,
        keyword,
        page: page,
        limit: limit,
      );
      if (builtInResult.isNotEmpty) return builtInResult;
    } else {
      final builtInResult = await _builtInSources.search(
        platform,
        keyword,
        page: page,
        limit: limit,
      );
      if (builtInResult.isNotEmpty) return builtInResult;
    }

    if (enabledCustomSources.isNotEmpty) {
      return await _customSourceService
          .searchWithSource(
            enabledCustomSources.first.id,
            keyword,
            source: platform,
            page: page,
            limit: limit,
            type: type,
          )
          .catchError((e) {
            return <MusicItem>[];
          });
    }

    return [];
  }

  Future<List<MusicItem>> _searchAllPlatforms(
    String keyword, {
    int page = 1,
    int limit = 20,
  }) async {
    final platforms = _builtInSources.allIds;
    final results = await Future.wait(
      platforms.map(
        (p) => _builtInSources
            .search(p, keyword, page: page, limit: limit)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => <MusicItem>[],
            )
            .catchError((_) => <MusicItem>[]),
      ),
    );

    final List<MusicItem> combined = [];
    int maxLen = results
        .map((r) => r.length)
        .fold(0, (max, len) => len > max ? len : max);
    for (int i = 0; i < maxLen; i++) {
      for (var list in results) {
        if (i < list.length) {
          combined.add(list[i]);
        }
      }
    }
    return combined;
  }

  String resolvePlatform(MusicItem music) {
    var platform = music.platform;
    if (!_isScriptPlatform(platform)) {
      final metaSrc = music.meta?['source']?.toString();
      if (_isScriptPlatform(metaSrc)) {
        platform = metaSrc!;
      } else if (_isScriptPlatform(music.source)) {
        platform = music.source;
      } else {
        platform = '';
      }
    }
    return platform;
  }

  bool _isScriptPlatform(String? platform) =>
      platform == 'kw' ||
      platform == 'tx' ||
      platform == 'wy' ||
      platform == 'kg' ||
      platform == 'mg' ||
      platform == 'local';

  Future<String?> getPlayUrl(MusicItem music, {String quality = '320k'}) async {
    final result = await resolvePlayableUrl(music, preferredQuality: quality);
    return result?.url;
  }

  Future<PlayUrlResult?> getPlayUrlDetailed(
    MusicItem music, {
    String quality = '320k',
  }) {
    return resolvePlayableUrl(music, preferredQuality: quality);
  }

  Future<PlayUrlResult?> resolvePlayableUrl(
    MusicItem music, {
    required String preferredQuality,
    CancelToken? cancelToken,
    bool allowCrossPlatformFallback = true,
    bool allowSamePlatformRefresh = true,
    bool allowQualityFallback = true,
  }) {
    final resolutionToken = cancelToken ?? CancelToken();
    return _resolvePlayableUrl(
      music,
      preferredQuality: preferredQuality,
      cancelToken: resolutionToken,
      allowCrossPlatformFallback: allowCrossPlatformFallback,
      allowSamePlatformRefresh: allowSamePlatformRefresh,
      allowQualityFallback: allowQualityFallback,
    ).timeout(
      playUrlResolutionTimeout,
      onTimeout: () {
        if (!resolutionToken.isCancelled) {
          resolutionToken.cancel('Playback URL resolution timed out');
        }
        debugPrint('[getPlayUrl] 解析超时: $playUrlResolutionTimeout');
        return null;
      },
    );
  }

  Future<PlayUrlResult?> _resolvePlayableUrl(
    MusicItem music, {
    required String preferredQuality,
    required CancelToken cancelToken,
    required bool allowCrossPlatformFallback,
    required bool allowSamePlatformRefresh,
    required bool allowQualityFallback,
  }) async {
    final resolvedQuality = preferredQuality.isEmpty
        ? '320k'
        : preferredQuality;
    if (isSubsonicMusic(music.source, music.platform)) {
      return _resolveSubsonicUrl(music, resolvedQuality);
    }
    final nasKind = nasKindOf(music.source, music.platform);
    if (nasKind != null) {
      return _resolveNasUrl(nasKind, music, resolvedQuality);
    }
    final songId = songIdOf(music);
    final platform = resolvePlatform(music);
    debugPrint(
      '[getPlayUrl] 开始解析: platform=$platform, songId=$songId, quality=$resolvedQuality, source=${music.source}',
    );

    final hasCustom =
        _enabledCustomSourceIds != null ||
        _customSourceQualityResolver != null ||
        (_hasEnabledCustomSources?.call() ??
            _customSourceService.enabledSources.isNotEmpty);
    if (!hasCustom) {
      // 本项目不内置任何音频地址解析。没有用户启用的音源时，这里必须
      // 直接失败，而不是回落到任何内置通道。
      debugPrint('[getPlayUrl] 未启用任何音源，无法解析音频地址');
      return null;
    }

    final customAttemptKeys = <String>{};
    final qualities = allowQualityFallback
        ? qualityChain(resolvedQuality)
        : [resolvedQuality];
    final customResult = await _resolveQualityChain(
      music,
      resolvedQuality,
      qualities,
      (music, quality, cancelToken, {required candidateIndex}) =>
          _resolveCustomQuality(
            music,
            quality,
            cancelToken,
            candidateIndex: candidateIndex,
            attemptKeys: customAttemptKeys,
          ),
      cancelToken,
      acceptDowngradeImmediately: true,
    );
    if (customResult != null) return customResult;

    if (platform != 'kw' &&
        platform != 'tx' &&
        platform != 'wy' &&
        platform != 'kg') {
      return null;
    }

    // 内置平台只提供元数据。以下两条路径补的是 songmid / hash 这类定位
    // 字段，或在另一个平台找到同一首歌再试一次；音频地址始终由用户音源
    // 解析，不会走任何内置实现。
    if (allowSamePlatformRefresh) {
      _throwIfCancelled(cancelToken);
      final matches = await _builtInSources
          .search(platform, music.name, page: 1, limit: 10)
          .catchError((_) => <MusicItem>[]);
      final candidate = _bestSongMatch(music, matches);
      if (candidate != null && !identical(candidate, music)) {
        debugPrint('[getPlayUrl] 使用同平台搜索结果补全播放元数据: $platform');
        final refreshed = await _resolvePlayableUrl(
          candidate,
          preferredQuality: resolvedQuality,
          cancelToken: cancelToken,
          allowCrossPlatformFallback: false,
          allowSamePlatformRefresh: false,
          allowQualityFallback: false,
        );
        if (refreshed != null) return refreshed;
      }
    }

    if (allowCrossPlatformFallback) {
      final fallback = await _resolveCrossPlatformFallback(
        music,
        resolvedQuality,
        cancelToken,
      );
      if (fallback != null) return fallback;
    }

    debugPrint(
      allowCrossPlatformFallback
          ? '[getPlayUrl] 用户音源未能解析该歌曲，跨平台换源后仍失败'
          : '[getPlayUrl] 用户音源未能解析该歌曲',
    );
    return null;
  }

  Future<PlayUrlResult?> _resolveCrossPlatformFallback(
    MusicItem music,
    String quality,
    CancelToken cancelToken,
  ) async {
    final sourcePlatform = resolvePlatform(music);
    final platforms = fallbackPlatforms
        .where(
          (platform) =>
              platform != sourcePlatform &&
              _builtInSources.get(platform) != null,
        )
        .toList(growable: false);
    for (final platform in platforms) {
      _throwIfCancelled(cancelToken);
      final candidate = await matchPlaybackFallback(
        music,
        platform,
        cancelToken,
      );
      if (candidate == null) continue;
      final result = await _resolvePlayableUrl(
        candidate,
        preferredQuality: quality,
        cancelToken: cancelToken,
        allowCrossPlatformFallback: false,
        allowSamePlatformRefresh: false,
        allowQualityFallback: false,
      );
      if (result != null) return result;
    }
    return null;
  }

  Future<MusicItem?> matchPlaybackFallback(
    MusicItem original,
    String platform,
    CancelToken? cancelToken,
  ) async {
    _throwIfCancelled(cancelToken);
    final title = _normalizeMatchText(original.name);
    final singer = _normalizeMatchText(original.singer);
    if (title.isEmpty ||
        singer.isEmpty ||
        original.duration <= Duration.zero ||
        platform == resolvePlatform(original) ||
        _builtInSources.get(platform) == null) {
      return null;
    }
    final search = _builtInSources
        .search(platform, original.name, page: 1, limit: 10)
        .timeout(const Duration(seconds: 4))
        .catchError((_) => <MusicItem>[]);
    final matches = cancelToken == null
        ? await search
        : await Future.any<List<MusicItem>>([
            search,
            cancelToken.whenCancel.then((_) => <MusicItem>[]),
          ]);
    _throwIfCancelled(cancelToken);
    final album = _normalizeMatchText(original.album);
    final candidates = <String, MusicItem>{};
    for (final match in matches) {
      final id = songIdOf(match);
      final targetAlbum = _normalizeMatchText(match.album);
      if (id.isEmpty ||
          resolvePlatform(match) != platform ||
          _normalizeMatchText(match.name) != title ||
          _normalizeMatchText(match.singer) != singer ||
          match.duration <= Duration.zero ||
          (match.duration - original.duration).inMilliseconds.abs() > 2000 ||
          (album.isNotEmpty &&
              targetAlbum.isNotEmpty &&
              album != targetAlbum)) {
        continue;
      }
      candidates[id] = match;
    }
    if (candidates.length != 1) return null;
    final candidate = candidates.values.single;
    debugPrint(
      '[getPlayUrl] 跨平台同曲: ${resolvePlatform(original)} -> '
      '$platform ${candidate.name} / ${candidate.singer} id=${songIdOf(candidate)}',
    );
    return candidate;
  }

  MusicItem? _bestSongMatch(MusicItem original, List<MusicItem> matches) {
    final name = _normalizeMatchText(original.name);
    final singer = _normalizeMatchText(original.singer);
    MusicItem? best;
    var bestScore = 0;
    for (final candidate in matches) {
      final candidateName = _normalizeMatchText(candidate.name);
      final candidateSinger = _normalizeMatchText(candidate.singer);
      var score = 0;
      if (candidateName == name) score += 2;
      if (singer.isNotEmpty && candidateSinger.contains(singer)) score += 2;
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return bestScore >= 4 ? best : null;
  }

  String _normalizeMatchText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[()（）\[\]【】]'), '');

  Future<PlayUrlResult?> _resolveQualityChain(
    MusicItem music,
    String requestedQuality,
    List<String> qualities,
    Future<_QualityAttempt?> Function(
      MusicItem music,
      String quality,
      CancelToken? cancelToken, {
      required int candidateIndex,
    })
    resolver,
    CancelToken? cancelToken, {
    required bool acceptDowngradeImmediately,
  }) async {
    final songId = songIdOf(music);
    _QualityAttempt? bestBelow;

    final attemptedQualities = <String>{};
    for (
      var candidateIndex = 0;
      candidateIndex < qualities.length;
      candidateIndex++
    ) {
      final quality = qualities[candidateIndex];
      if (!attemptedQualities.add(quality)) continue;
      _throwIfCancelled(cancelToken);
      final attempt = await resolver(
        music,
        quality,
        cancelToken,
        candidateIndex: candidateIndex,
      );
      _throwIfCancelled(cancelToken);
      if (attempt == null || !isPlayableMediaUrl(attempt.result.url)) continue;

      final normalized = PlayUrlResult(
        url: attempt.result.url,
        requestedQuality: requestedQuality,
        actualQuality: attempt.result.actualQuality,
        platform: attempt.result.platform,
        songId: attempt.songId.isNotEmpty ? attempt.songId : songId,
        headers: attempt.result.headers,
        trustedNetwork: attempt.result.trustedNetwork,
        validUntil:
            attempt.result.validUntil ??
            DateTime.now().add(const Duration(hours: 3)),
        fromCustomSource: attempt.result.fromCustomSource,
      );
      final normalizedAttempt = _QualityAttempt(
        result: normalized,
        sourceIndex: attempt.sourceIndex,
        candidateIndex: candidateIndex,
      );
      if (isQualityBelow(normalized.actualQuality, quality)) {
        if (acceptDowngradeImmediately) return normalized;
        bestBelow = _betterProvisional(bestBelow, normalizedAttempt);
        continue;
      }
      return _betterProvisional(bestBelow, normalizedAttempt)?.result;
    }

    if (bestBelow != null) {
      debugPrint(
        '[getPlayUrl] 使用偏低但可播结果 actual=${bestBelow.result.actualQuality}',
      );
      return bestBelow.result;
    }
    return null;
  }

  Future<_QualityAttempt?> _resolveCustomQuality(
    MusicItem music,
    String quality,
    CancelToken? cancelToken, {
    required int candidateIndex,
    required Set<String> attemptKeys,
  }) async {
    if (_customSourceQualityResolver == null &&
        _customQualityResolver != null) {
      final result = await _customQualityResolver(music, quality, cancelToken);
      return result == null
          ? null
          : _QualityAttempt(
              result: PlayUrlResult(
                url: result.url,
                requestedQuality: result.requestedQuality,
                actualQuality: result.actualQuality,
                platform: resolvePlatform(music),
                songId: result.songId,
                fromCustomSource: true,
              ),
              sourceIndex: 0,
              candidateIndex: candidateIndex,
              songId: result.songId,
            );
    }
    final platform = resolvePlatform(music);
    final musicForScript = music.copyWith(platform: platform);
    final candidateSourceIds =
        _enabledCustomSourceIds?.call() ??
        _customSourceService.enabledSources.map((source) => source.id).toList();
    // 音源检测结论：这个平台上明确取不到链的脚本直接跳过，只有超时的排到最后。
    final sourceIds =
        sourceCheckPolicy?.order(candidateSourceIds, platform) ??
        candidateSourceIds;
    _QualityAttempt? bestBelow;
    for (var sourceIndex = 0; sourceIndex < sourceIds.length; sourceIndex++) {
      final sourceId = sourceIds[sourceIndex];
      _throwIfCancelled(cancelToken);
      try {
        if (_customSourceQualityResolver != null) {
          final result = await _customSourceQualityResolver(
            sourceId,
            musicForScript,
            quality,
            cancelToken,
          );
          _throwIfCancelled(cancelToken);
          if (result == null || !isPlayableMediaUrl(result.url)) continue;
          final normalized = PlayUrlResult(
            url: result.url,
            requestedQuality: quality,
            actualQuality: result.actualQuality,
            platform: platform,
            songId: result.songId,
            fromCustomSource: true,
          );
          if (!isQualityBelow(normalized.actualQuality, quality)) {
            return _QualityAttempt(
              result: normalized,
              sourceIndex: sourceIndex,
              candidateIndex: candidateIndex,
              songId: normalized.songId,
            );
          }
          bestBelow = _betterProvisional(
            bestBelow,
            _QualityAttempt(
              result: normalized,
              sourceIndex: sourceIndex,
              candidateIndex: candidateIndex,
              songId: normalized.songId,
            ),
          );
          continue;
        }
        final effectiveQuality = await _customSourceService
            .effectiveMusicQuality(sourceId, platform, quality);
        if (effectiveQuality == null ||
            !attemptKeys.add('$sourceId|$effectiveQuality')) {
          continue;
        }
        final detailed = await _getCustomUrlOnce(
          sourceId,
          musicForScript,
          quality,
        );
        _throwIfCancelled(cancelToken);
        final rawUrl = detailed?.url;
        final url = rawUrl == null ? null : normalizeMediaUrl(rawUrl);
        if (!isPlayableMediaUrl(url)) {
          debugPrint(
            '[getPlayUrl] 自定义源 $sourceId q=$quality 返回不可播放URL '
            'host=${Uri.tryParse(rawUrl ?? '')?.host}',
          );
          continue;
        }
        final result = PlayUrlResult(
          url: url!,
          requestedQuality: quality,
          actualQuality:
              normalizeScriptQuality(detailed?.type) ??
              correctQualityFromUrl(url, quality),
          platform: platform,
          fromCustomSource: true,
        );
        if (!isQualityBelow(result.actualQuality, quality)) {
          return _QualityAttempt(
            result: result,
            sourceIndex: sourceIndex,
            candidateIndex: candidateIndex,
            songId: result.songId,
          );
        }
        bestBelow = _betterProvisional(
          bestBelow,
          _QualityAttempt(
            result: result,
            sourceIndex: sourceIndex,
            candidateIndex: candidateIndex,
            songId: result.songId,
          ),
        );
      } catch (error) {
        if (error is DioException && CancelToken.isCancel(error)) rethrow;
        debugPrint('[getPlayUrl] 自定义源 $sourceId q=$quality 失败: $error');
      }
    }
    return bestBelow;
  }

  Future<({String url, String? type})?> _getCustomUrlOnce(
    String sourceId,
    MusicItem music,
    String quality,
  ) async {
    final songId = music.songmid?.isNotEmpty == true
        ? music.songmid!
        : (music.hash?.isNotEmpty == true ? music.hash! : music.id);
    final platform = resolvePlatform(music);
    final key = '$sourceId|$platform|$songId|$quality';
    final now = DateTime.now();
    final failureUntil = _customFailureUntil[key];
    if (failureUntil != null && failureUntil.isAfter(now)) return null;
    if (failureUntil != null) _customFailureUntil.remove(key);

    final existing = _customUrlRequests[key];
    if (existing != null) return existing;

    final request = _customSourceService
        .getMusicUrlDetailed(sourceId, music, quality: quality)
        .timeout(const Duration(seconds: 20));
    _customUrlRequests[key] = request;
    try {
      final result = await request;
      if (result == null) {
        _customFailureUntil[key] = DateTime.now().add(_customFailureCooldown);
      }
      return result;
    } catch (_) {
      _customFailureUntil[key] = DateTime.now().add(_customFailureCooldown);
      rethrow;
    } finally {
      if (identical(_customUrlRequests[key], request)) {
        _customUrlRequests.removeWhere((requestKey, _) => requestKey == key);
      }
    }
  }

  String songIdOf(MusicItem music) {
    if (music.songmid?.isNotEmpty == true) return music.songmid!;
    if (music.hash?.isNotEmpty == true) return music.hash!;
    return music.id;
  }

  void _throwIfCancelled(CancelToken? cancelToken) {
    final error = cancelToken?.cancelError;
    if (error != null) throw error;
  }

  _QualityAttempt? _betterProvisional(
    _QualityAttempt? current,
    _QualityAttempt candidate,
  ) {
    if (current == null) return candidate;
    final actualComparison = qualityRankIndex(
      candidate.result.actualQuality,
    ).compareTo(qualityRankIndex(current.result.actualQuality));
    if (actualComparison < 0 ||
        (actualComparison == 0 &&
            (candidate.sourceIndex < current.sourceIndex ||
                (candidate.sourceIndex == current.sourceIndex &&
                    candidate.candidateIndex < current.candidateIndex)))) {
      return candidate;
    }
    return current;
  }

  Future<PlayUrlResult?> _resolveSubsonicUrl(
    MusicItem music,
    String quality,
  ) async {
    final service = _subsonicService;
    if (service == null) {
      debugPrint('[getPlayUrl] Subsonic 服务未注入');
      return null;
    }
    await service.init();
    if (!service.isConnected) {
      debugPrint('[getPlayUrl] 尚未连接 NAS 音乐服务器');
      return null;
    }
    final url = await service.getPlayUrl(music, quality: quality);
    if (url == null || !isPlayableMediaUrl(url)) return null;
    return PlayUrlResult(
      url: normalizeMediaUrl(url),
      requestedQuality: quality,
      actualQuality: nasActualQuality(
        requested: quality,
        bitRate: music.meta?['bitRate'],
        suffix: music.meta?['suffix'],
        contentType: music.meta?['contentType'],
        container: music.meta?['container'],
        codec: music.meta?['codec'],
      ),
      platform: 'subsonic',
      songId: music.songmid ?? music.id,
      trustedNetwork: _sameOrigin(service.config.baseUrl, url),
    );
  }

  bool _sameOrigin(String configuredUrl, String mediaUrl) {
    final configured = Uri.tryParse(configuredUrl);
    final media = Uri.tryParse(mediaUrl);
    if (configured == null || media == null || media.userInfo.isNotEmpty) {
      return false;
    }
    return configured.scheme.toLowerCase() == media.scheme.toLowerCase() &&
        configured.host.toLowerCase() == media.host.toLowerCase() &&
        configured.port == media.port;
  }

  Future<PlayUrlResult?> _resolveNasUrl(
    NasKind kind,
    MusicItem music,
    String quality,
  ) async {
    final service = _nasServices[kind];
    if (service == null) {
      debugPrint('[getPlayUrl] ${kind.title} 服务未注入');
      return null;
    }
    await service.init();
    if (!service.isConnected) {
      debugPrint('[getPlayUrl] 尚未连接 ${kind.title}');
      return null;
    }
    final resolved = await service.getPlayUrlResult(music, quality: quality);
    if (resolved == null || !isPlayableMediaUrl(resolved.url)) return null;
    return PlayUrlResult(
      url: normalizeMediaUrl(resolved.url),
      requestedQuality: quality,
      actualQuality: nasActualQuality(
        requested: quality,
        bitRate: music.meta?['bitRate'],
        suffix: music.meta?['suffix'],
        contentType: music.meta?['contentType'],
        container: music.meta?['container'],
        codec: music.meta?['codec'],
      ),
      platform: kind.id,
      songId: music.songmid ?? music.id,
      headers: resolved.headers,
      trustedNetwork: resolved.trustedNetwork,
    );
  }

  Future<String?> getLyric(MusicItem music) async {
    final payload = await getLyricPayload(music);
    return payload?.main;
  }

  /// 取歌词，保留翻译 / 音译。
  ///
  /// NAS 与 Subsonic 仍优先直接返回；在线来源并行采集后，优先选择
  /// 逐字时间完整的候选，再比较行数和附加翻译。同分时保持来源配置顺序。
  Future<LyricPayload?> getLyricPayload(MusicItem music) async {
    debugPrint(
      '[MusicSourceService] getLyric: platform=${music.platform}, source=${music.source}, songmid=${music.songmid}',
    );

    final subsonic = _subsonicService;
    if (isSubsonicMusic(music.source, music.platform)) {
      if (subsonic != null) {
        try {
          final payload = await (() async {
            await subsonic.init();
            final lyric = await subsonic.getLyric(music);
            return lyric == null || lyric.isEmpty
                ? null
                : LyricPayload(main: lyric);
          })().timeout(lyricSourceTimeout);
          if (payload != null) return payload;
        } catch (error) {
          debugPrint('[MusicSourceService] Subsonic 歌词失败: $error');
        }
      }
    } else {
      final nasKind = nasKindOf(music.source, music.platform);
      if (nasKind != null) {
        final nas = _nasServices[nasKind];
        if (nas != null) {
          try {
            final payload = await (() async {
              await nas.init();
              final lyric = await nas.getLyric(music);
              return lyric == null || lyric.isEmpty
                  ? null
                  : LyricPayload(main: lyric);
            })().timeout(lyricSourceTimeout);
            if (payload != null) return payload;
          } catch (error) {
            debugPrint('[MusicSourceService] ${nasKind.title} 歌词失败: $error');
          }
        }
      }
    }

    final platform = music.platform.isNotEmpty ? music.platform : music.source;
    final tasks = <Future<LyricPayload?>>[];
    if (platform.isNotEmpty && platform != 'custom' && platform != 'test') {
      tasks.add(
        _tryLyricSource(
          '内置源 $platform',
          () => _builtInSources.getLyricPayload(platform, music),
        ),
      );
    }
    for (final source in _customSourceService.enabledSources) {
      tasks.add(
        _tryLyricSource('自定义源 ${source.id}', () async {
          final lyric = await _customSourceService.getLyric(source.id, music);
          return lyric == null || lyric.trim().isEmpty
              ? null
              : LyricPayload(main: lyric);
        }),
      );
    }

    if (_isUsableSongMatchInput(music)) {
      for (final pid in MusicSourceService.fallbackPlatforms) {
        if (pid == platform || _builtInSources.get(pid) == null) continue;
        tasks.add(
          _tryLyricSource('跨平台源 $pid', () async {
            final matches = await _builtInSources
                .search(pid, music.name, page: 1, limit: 10)
                .timeout(const Duration(seconds: 4));
            final candidate = _bestSongMatch(music, matches);
            if (candidate == null) return null;
            return _builtInSources.getLyricPayload(pid, candidate);
          }),
        );
      }
    }

    final result = _bestLyricPayload(await Future.wait(tasks));
    if (result != null) return result;

    debugPrint('[MusicSourceService] 所有源均未返回歌词');
    return null;
  }

  Future<LyricPayload?> _tryLyricSource(
    String source,
    Future<LyricPayload?> Function() load,
  ) async {
    try {
      final payload = await load().timeout(lyricSourceTimeout);
      if (payload == null || payload.main.trim().isEmpty) return null;
      return payload;
    } catch (error) {
      debugPrint('[MusicSourceService] $source 歌词失败: $error');
      return null;
    }
  }

  LyricPayload? _bestLyricPayload(List<LyricPayload?> candidates) {
    LyricPayload? best;
    for (final candidate in candidates) {
      if (candidate == null || _parseLyricPayload(candidate).isEmpty) continue;
      if (best == null || _compareLyricPayloads(candidate, best) > 0) {
        best = candidate;
      }
    }
    return best;
  }

  bool _isUsableSongMatchInput(MusicItem music) =>
      _normalizeMatchText(music.name).isNotEmpty &&
      _normalizeMatchText(music.singer).isNotEmpty &&
      music.duration > Duration.zero;

  int _compareLyricPayloads(LyricPayload left, LyricPayload right) {
    final leftLyrics = _parseLyricPayload(left);
    final rightLyrics = _parseLyricPayload(right);
    final leftWords = leftLyrics.lines
        .where((line) => line.hasWordTiming)
        .length;
    final rightWords = rightLyrics.lines
        .where((line) => line.hasWordTiming)
        .length;
    final leftTranslated = leftLyrics.lines
        .where((line) => line.translation?.trim().isNotEmpty == true)
        .length;
    final rightTranslated = rightLyrics.lines
        .where((line) => line.translation?.trim().isNotEmpty == true)
        .length;

    var result = (leftWords > 0 ? 1 : 0).compareTo(rightWords > 0 ? 1 : 0);
    if (result != 0) return result;
    result = leftWords.compareTo(rightWords);
    if (result != 0) return result;
    result = leftLyrics.lines.length.compareTo(rightLyrics.lines.length);
    if (result != 0) return result;
    return leftTranslated.compareTo(rightTranslated);
  }

  Lyrics _parseLyricPayload(LyricPayload payload) {
    final isTencentQrc = RegExp(
      r'^\s*\[\d+\s*,\s*\d+\]',
      multiLine: true,
    ).hasMatch(payload.main);
    final hasLrcLineTime = RegExp(
      r'^\s*\[(?:\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?|\d+)\]',
      multiLine: true,
    ).hasMatch(payload.main);
    final isClockQrc = RegExp(
      r'^\[\d{2}:\d{2}\.\d{2,3}\]\s*<\d{2}:\d{2}\.\d{2,3}',
      multiLine: true,
    ).hasMatch(payload.main);
    final lyrics = isTencentQrc || isClockQrc || !hasLrcLineTime
        ? LyricParser.parseQrc(payload.main)
        : LyricParser.parseLrc(payload.main);
    if (!payload.hasExtras) return lyrics;
    return LyricParser.attachParallelText(
      lyrics,
      translation: payload.translation,
    );
  }

  Future<List<MusicItem>> getSongListDetail(
    String platformId,
    String songListId, {
    int page = 1,
    int limit = 50,
  }) async {
    final enabledSources = _customSourceService.enabledSources;
    for (final source in enabledSources) {
      try {
        final songs = await _customSourceService.getSongListDetail(
          source.id,
          songListId,
          source: platformId,
          page: page,
        );
        if (songs.isNotEmpty) return songs;
      } catch (error) {
        AppLog.instance.record(
          'source.fallback',
          'playlist fetch via $platformId failed, trying next source: $error',
          level: AppLogLevel.warning,
        );
      }
    }
    return _builtInSources.getSongListDetail(
      platformId,
      songListId,
      page: page,
      limit: limit,
    );
  }

  void dispose() {
    _builtInSources.dispose();
  }
}
