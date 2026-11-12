// Web 专用启动入口。UI 层（LxMusicApp）与全部 provider 完全复用原生版，
// 只把「浏览器里没有对应插件」的启动步骤替换掉：
//   - 不做便携模式 / SharedPreferences 文件覆盖
//   - 不调 path_provider / audio_session / AudioService.init
//   - 歌单仓库换成 SharedPreferences 版（浏览器无文件系统）
// 构建时由 build-web.sh 以 -t lib/main_web.dart 指定，主仓库 main.dart 不变。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/app.dart';
import 'package:koyze/core/audio/audio_handler.dart';
import 'package:koyze/core/audio/audio_runtime.dart';
import 'package:koyze/core/audio/playback_cache_service.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/core/network/play_url_result.dart';
import 'package:koyze/core/storage/cache_maintenance_service.dart';
import 'package:koyze/core/web/web_source_import.dart';
import 'package:koyze/features/custom_source/presentation/custom_source_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/data/web_playlist_repository.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/startup_lifecycle.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<StartupBootstrapState>(
    const StartupBootstrapState.loading(),
  );
  runApp(
    StartupBootstrapGate(
      status: status,
      onRetry: () {
        status.value = const StartupBootstrapState.loading();
        unawaited(_bootstrap(status));
      },
    ),
  );
  unawaited(_bootstrap(status));
}

Future<void> _bootstrap(
  ValueNotifier<StartupBootstrapState> status,
) async {
  try {
    // 浏览器用 shared_preferences_web（localStorage），不要覆盖成文件实现。
    final preferences = await SharedPreferences.getInstance();

    final repository = WebPlaylistRepository(preferences: preferences);
    final disposals = ResourceDisposalTracker();
    final container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(repository),
        resourceDisposalTrackerProvider.overrideWithValue(disposals),
        cacheMaintenanceProvider.overrideWithValue(CacheMaintenanceService()),
      ],
    );
    final lifecycle = StartupLifecycle(container, disposals);

    final persistedQuality = AudioQualityOption.values[
        (preferences.getInt('audio_quality') ?? AudioQualityOption.high.index)
            .clamp(0, AudioQualityOption.values.length - 1)];
    container
        .read(audioQualityProvider.notifier)
        .applyCommitted(persistedQuality);
    container
        .read(wifiOnlyDownloadProvider.notifier)
        .applyCommitted(preferences.getBool('wifi_only_download') ?? true);

    // 音源必须在播放链路装配前加载完。
    // `customSourceServiceProvider` 里的 `service.init()` 是 fire-and-forget，
    // 而 `enabledSources` 在 `_loadSources()` 跑完前一直是空列表 —— 结果就是
    // 解析器把「未启用任何音源」当成事实，点歌一律失败。原生版在 main.dart
    // 里显式 await 过，Web 入口漏了这一步。
    await container.read(customSourceServiceProvider).init();
    debugPrint('[web] sources loaded: '
        '${container.read(customSourceServiceProvider).enabledSources.length}');

    // 歌单持久化同样必须显式初始化。原生版在 main.dart:321 有这一步，
    // Web 入口漏了之后 `_initialized` 恒为 false，任何收藏 / 建歌单 / 拖拽
    // 排序都会抛 `StateError: PlaylistService is not initialized`——表现为
    // 点收藏没反应，控制台里是一个被混淆成 `Error` 的 pageerror。
    await container.read(playlistServiceProvider).init();
    debugPrint('[web] playlist service ready');

    // 浏览器里没有 audio_service 的后台 isolate / 通知通道，
    // 直接把 handler 挂到全局单例即可：UI 与 player_service 都读它。
    final handler = LxAudioHandler();
    handler.preferredQuality = audioQualityToken(persistedQuality);
    audioHandler = handler;
    await initializeOwnedAudioRuntime(
      registerDisposal: disposals.register,
      disposeHandler: handler.dispose,
      initialize: (_) async {},
    );

    _wirePlaybackResolver(container, handler);
    debugPrint('[web] playback resolver wired');

    status.value = StartupBootstrapState.ready(
      OwnedProviderScope(lifecycle: lifecycle, child: const LxMusicApp()),
    );
  } catch (error, stackTrace) {
    debugPrint('[web] bootstrap failed: $error\n$stackTrace');
    status.value = StartupBootstrapState.failed(error);
  }
}

/// 接上「音源取链 → 播放器」这条线。
///
/// 原生版在 `main.dart` 里装了完整的一套（含落盘缓存、租约、预取），
/// Web 入口是另一份 bootstrap，之前漏了这一步，于是 `urlResolver` 一直是
/// null，`audio_handler` 走到 `play()` 前就放弃，表现为「音源检测可用但点歌
/// 没反应」，页面上连 `<audio>` 元素都不会出现。
///
/// 浏览器没有文件系统，缓存层整条链路都用不上，所以这里直接退化成
/// 「解析出地址就流式播放」：`acquireOrDownload` 恒返回 null，让
/// `PlaybackUrlResolver` 走 `validateStream` 分支，校验通过后返回
/// `StreamingPlayback`（不落盘、无租约）。
/// 判断拿到的地址是不是**试听片段**。
///
/// 酷我 / 网易云对未登录、无版权、会员曲目会下发一个合法的短片段地址：
/// HTTP 200、能出音频字节，`validateStream` 完全放行，但只够播 10~30 秒。
/// 浏览器是流式播放，片段播完就断（原生版有落盘缓存，用户体感也一样）。
///
/// 判据：用 `Range: bytes=0-0` 拿总字节数，按码率估时长，和搜索结果里的
/// 标称时长（`music.duration`）比。
///
/// 码率必须按**最低可能值（128k）**估：估出来的时长最长，才不会把正常歌
/// 误判成片段。实测 QQ 的 `actualQuality` 会自称 320k，实际文件只有 ~192k，
/// 按 320k 估会把 218 秒的完整歌算成 132 秒，直接误杀。
///
/// 另外加 45 秒绝对门槛：正常歌曲极少短于 45 秒，试听片段基本都在 30 秒内。
/// 两个条件同时满足才判为片段——宁可漏判（继续播片段），不可误杀。
/// 拿不到总字节数时一律返回 false。
Future<bool> _rejectTrialClip(MusicItem music, PlayUrlResult? result) async {
  if (result == null) return false;
  final expected = music.duration;
  // 标称时长缺失或太短（铃声、试听曲）时没有可比基准，直接放行。
  if (expected < const Duration(seconds: 45)) return false;

  final totalBytes = await probeMediaTotalBytes(
    result.url,
    timeout: const Duration(seconds: 8),
  );
  if (totalBytes == null || totalBytes <= 0) return false;

  // 128kbps → 每秒 16000 字节。用最低码率算出的时长是上限。
  const bytesPerSecondAt128k = 128 * 1000 / 8;
  final estimatedSeconds = totalBytes / bytesPerSecondAt128k;

  const absoluteClipCeiling = 45;
  if (estimatedSeconds > absoluteClipCeiling) return false;
  if (estimatedSeconds * 100 >= expected.inSeconds * 60) return false;

  debugPrint(
    '[web/clip] 判定为试听片段: ${music.name} '
    'platform=${result.platform} q=${result.actualQuality} '
    'bytes=$totalBytes 估算上限=${estimatedSeconds.round()}s '
    '标称=${expected.inSeconds}s',
  );
  return true;
}

void _wirePlaybackResolver(ProviderContainer container, LxAudioHandler handler) {
  final sourceService = container.read(musicSourceServiceProvider);

  const qualityMap = {
    AudioQualityOption.low: '128k',
    AudioQualityOption.high: '320k',
    AudioQualityOption.lossless: 'flac',
    AudioQualityOption.lossless24: 'flac24bit',
    AudioQualityOption.hires: 'hires',
  };

  final resolver = PlaybackUrlResolver<MusicItem>(
    resolvePlayableUrl: (music, {required preferredQuality}) async {
      final result = await sourceService.resolvePlayableUrl(
        music,
        preferredQuality: preferredQuality,
        allowCrossPlatformFallback: false,
        allowQualityFallback: false,
      );
      // 拿不到地址，或者只拿到试听片段 → 返回 null，让 PlaybackUrlResolver
      // 走下面的 fallbackPlatforms 换源。原生版有落盘缓存，片段还能凑合播；
      // 浏览器里流式播放，片段播完就断，用户体感就是「点了没反应」。
      return await _rejectTrialClip(music, result) ? null : result;
    },
    fallbackPlatforms: MusicSourceService.fallbackPlatforms,
    resolveFallbackPlayableUrl:
        (music, {required platform, required preferredQuality}) async {
      final result = await sourceService.resolvePlayableUrl(
        music.copyWith(source: platform, platform: platform),
        preferredQuality: preferredQuality,
        allowCrossPlatformFallback: false,
        allowQualityFallback: false,
      );
      return await _rejectTrialClip(music, result) ? null : result;
    },
    // 浏览器不落盘：一律返回 null，交给下面的 validateStream 走流式分支。
    acquireOrDownload: ({
      required remoteUrl,
      required platform,
      required songId,
      required quality,
    }) async => null,
    // 用浏览器侧的 Range 探测确认这个地址真的能出音频字节
    // （自定义源常有防盗链 / 签名过期，不能拿到 URL 就直接塞给 <audio>）。
    validateStream: ({required remoteUrl, required platform, required quality}) =>
        probeMediaViaServer(
          remoteUrl,
          maxBytes: 16384,
          timeout: const Duration(seconds: 12),
        ).then((probed) => probed.error == null && probed.bytes.isNotEmpty),
    songIdFor: (music) {
      if (music.songmid?.isNotEmpty == true) return music.songmid!;
      if (music.hash?.isNotEmpty == true) return music.hash!;
      return music.id;
    },
    platformFor: (music) =>
        music.platform.isNotEmpty ? music.platform : music.source,
  );

  handler.urlResolver = (mediaId, [extras]) async {
    final rawExtras =
        extras ??
        (handler.mediaItem.value?.id == mediaId
            ? handler.mediaItem.value?.extras
            : null) ??
        () {
          // 只按 id 在队列里找，绝不回落到「当前曲」（会播错歌）。
          for (final item in handler.queueItems) {
            if (item.id == mediaId && item.extras != null) {
              return Map<String, dynamic>.from(item.extras!);
            }
          }
          return null;
        }();
    if (rawExtras == null) {
      debugPrint('[web/urlResolver] 缺少歌曲信息: mediaId=$mediaId');
      return null;
    }

    final music = MusicItem.fromJson(Map<String, dynamic>.from(rawExtras));
    final forced = rawExtras['requestedQuality']?.toString();
    final requested = (forced != null && forced.isNotEmpty)
        ? forced
        : (qualityMap[container.read(audioQualityProvider)] ?? '320k');
    handler.preferredQuality = requested;

    final generation = rawExtras['_playbackGeneration'];
    final resolution = await resolver.resolve(
      music,
      preferredQuality: requested,
      exclusive: generation is int,
    );
    if (resolution == null) {
      debugPrint(
        '[web/urlResolver] 源未返回可播地址: ${music.name} q=$requested',
      );
      if (!sourceService.hasEnabledCustomSource) {
        handler.onError?.call(
          '未启用任何音源，请先在「设置 → 高级 → 自定义源」导入并启用音源',
        );
      }
      return null;
    }
    if (generation is int) {
      final accepted = handler.acceptResolvedPlayback(
        mediaId: mediaId,
        generation: generation,
        resolution: resolution,
      );
      if (!accepted) return null;
    }
    return resolution.playableUrl;
  };

  handler.onError = (message) {
    container.read(playerMessageProvider.notifier).state = message;
  };
}
