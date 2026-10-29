import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../../core/audio/audio_handler.dart';
import '../../../core/audio/playback_command_coordinator.dart';
import '../../../core/state/buildless_notifier.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/audio/replay_gain.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../sync/presentation/sync_phase1_provider.dart';
import '../domain/music_item.dart';
import '../domain/playback_session.dart';
import '../domain/playback_session_store.dart';
import '../domain/player_service.dart';
import 'fire_and_forget_observer.dart';

/// Keeps the native player loudness aligned with [playbackVolumeProvider].
final playbackVolumeBindingProvider = Provider<void>((ref) {
  ref.listen<double>(playbackVolumeProvider, (_, volume) {
    final handler = audioHandler;
    if (handler is LxAudioHandler) {
      handler.applyPlaybackVolume(volume);
    }
  }, fireImmediately: true);
});

/// 把倍速同步到当前（以及重建后的）原生播放器。
///
/// 播放器被重建时新实例的速率会回到 1.0，所以这里既要跟随设置变化，
/// 也要跟随 [LxAudioHandler.playerStream]——只监听设置的话，一次自动恢复
/// 就会悄悄把用户调好的 1.5× 变回正常速度。
final playbackSpeedBindingProvider = Provider<void>((ref) {
  void apply(double speed) {
    try {
      final handler = audioHandler;
      if (handler is LxAudioHandler) {
        unawaited(handler.setPlaybackSpeed(speed));
      }
    } catch (_) {
      // 启动引导还没完成，audioHandler 仍是未初始化的 late 变量。
    }
  }

  ref.listen<double>(playbackSpeedProvider, (_, speed) => apply(speed));
  try {
    final handler = audioHandler;
    if (handler is LxAudioHandler) {
      apply(ref.read(playbackSpeedProvider));
      final subscription = handler.playerStream.listen(
        (_) => apply(ref.read(playbackSpeedProvider)),
      );
      ref.onDispose(subscription.cancel);
    }
  } catch (_) {
    // 同上：引导完成前没有处理器可用。
  }
});

/// 音调 / 跳过静音 / 淡入淡出。
///
/// 三者都是「设置项 → 原生播放器」的即时同步，且都在播放器重建后需要重新
/// 施加（重建时的恢复在 `_replaceNativePlayer` 里做，这里只负责设置变更）。
final playbackTuningBindingProvider = Provider<void>((ref) {
  void apply() {
    try {
      final handler = audioHandler;
      if (handler is! LxAudioHandler) return;
      handler.playbackFade = ref.read(playbackFadeEnabledProvider);
      unawaited(
        handler.setPlaybackPitch(
          pitchFactorForSemitones(ref.read(pitchSemitonesProvider)),
        ),
      );
      unawaited(handler.setSkipSilence(ref.read(skipSilenceEnabledProvider)));
    } catch (_) {
      // 启动引导还没完成，audioHandler 仍是未初始化的 late 变量。
    }
  }

  ref.listen<double>(pitchSemitonesProvider, (_, _) => apply());
  ref.listen<bool>(skipSilenceEnabledProvider, (_, _) => apply());
  ref.listen<bool>(playbackFadeEnabledProvider, (_, _) => apply());
  apply();
});

/// 把当前曲目的 ReplayGain 应用到音量上。
///
/// 只对本地文件生效：在线音源的响度由服务端归一，我们没有它们的标签。
/// 查库是异步的，用 generation 防止切换过快时旧结果覆盖新歌。
final replayGainBindingProvider = Provider<void>((ref) {
  var generation = 0;

  Future<void> apply(MusicItem? music) async {
    final current = ++generation;
    final handler = audioHandler;
    if (handler is! LxAudioHandler) return;
    if (music == null || music.source != 'local') {
      handler.applyTrackGain(1);
      return;
    }
    try {
      final library = await ref.read(localMusicLibraryProvider.future);
      await library.init();
      if (current != generation) return;
      final db = ref.read(replayGainEnabledProvider)
          ? library.replayGainForSongId(music.id)
          : null;
      if (current != generation) return;
      handler.applyTrackGain(db == null ? 1 : replayGainFactor(db));
    } catch (_) {
      if (current != generation) return;
      handler.applyTrackGain(1);
    }
  }

  ref.listen<MusicItem?>(currentMusicProvider, (_, next) {
    unawaited(apply(next));
  }, fireImmediately: true);
});

final playerServiceProvider = Provider<PlayerService>((ref) {
  return PlayerService(
    isDisliked: (song) async {
      final ratings = await ref.read(ratingServiceProvider).store.load();
      return ratings[song.identityKey] == PlayerService.dislikedRating;
    },
  );
});

final playbackSessionStoreProvider = Provider<PlaybackSessionStore>((ref) {
  return PlaybackSessionStore(() => StorageService.instance);
});

// 监听当前的 MediaItem (来自 audio_service)
final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return audioHandler.mediaItem;
});

/// Keep iOS Now Playing artwork in lockstep with skip / auto-next. Playlist
/// start only warms the first window; preloaded tracks otherwise publish a
/// remote `artUri` without `artCacheFile`.
final queueArtworkWarmerProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<MediaItem?>>(currentMediaItemProvider, (
    previous,
    next,
  ) {
    final nextId = next.value?.id;
    if (nextId == null || previous?.value?.id == nextId) return;
    unawaited(ref.read(playerServiceProvider).warmCurrentAndUpcomingArtwork());
  }, fireImmediately: true);
});

// 转换 MediaItem 为项目通用的 MusicItem
final currentMusicProvider = Provider<MusicItem?>((ref) {
  final mediaItem = ref.watch(currentMediaItemProvider).value;
  if (mediaItem == null) return null;

  // 从 extras 中恢复 MusicItem 对象（含 actualQuality 等扩展字段）
  if (mediaItem.extras != null) {
    final item = MusicItem.fromJson(mediaItem.extras!);
    // 保证 platform 字段可用
    final p = mediaItem.extras!['platform']?.toString();
    if (p != null && p.isNotEmpty && item.platform != p) {
      return item.copyWith(platform: p);
    }
    return item;
  }

  // 如果没有 extras，手动构建
  return MusicItem(
    id: mediaItem.id,
    name: mediaItem.title,
    singer: mediaItem.artist ?? '未知歌手',
    album: mediaItem.album ?? '',
    duration: mediaItem.duration ?? Duration.zero,
    source: 'unknown',
    artwork: mediaItem.artUri?.toString(),
  );
});

// 监听播放状态
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return audioHandler.playbackState;
});

// 实时进度：用 Timer 轮询 just_audio 的 position（比 StreamProvider 更可靠）
final playerPositionProvider = NotifierProvider<PositionNotifier, Duration>(
  PositionNotifier.new,
);

// 适配 MiniPlayer 的别名提供者
final positionProvider = playerPositionProvider;

// 播放状态简化
final isPlayingProvider = Provider<AsyncValue<bool>>((ref) {
  final state = ref.watch(playbackStateProvider);
  return state.whenData((s) => s.playing);
});

// 播放器实际音频时长（从 just_audio 获取）
final audioDurationProvider = StreamProvider<Duration?>((ref) {
  if (audioHandler is LxAudioHandler) {
    return (audioHandler as LxAudioHandler).playerStream.switchMap(
      (player) => player.durationStream,
    );
  }
  return Stream.value(null);
});

// 当前歌曲时长：优先使用播放器实际时长，回退到元数据时长
final durationProvider = Provider<AsyncValue<Duration>>((ref) {
  final audioDuration = ref.watch(audioDurationProvider).value;
  if (audioDuration != null && audioDuration > Duration.zero) {
    return AsyncValue.data(audioDuration);
  }
  final music = ref.watch(currentMusicProvider);
  return AsyncValue.data(music?.duration ?? Duration.zero);
});

// 播放模式枚举
enum PlayMode {
  repeatOne, // 单曲循环
  sequential, // 顺序播放
  shuffle, // 随机播放
}

PlayMode playModeFromPlaybackState(PlaybackState state) {
  if (state.shuffleMode == AudioServiceShuffleMode.all) {
    return PlayMode.shuffle;
  }
  if (state.repeatMode == AudioServiceRepeatMode.one) {
    return PlayMode.repeatOne;
  }
  return PlayMode.sequential;
}

/// 点击播放模式按钮时循环切换的下一个模式。
///
/// 这个状态机放在模块级而不是 Widget 私有方法里，是为了能被单元测试直接覆盖：
/// 它是最容易被"顺手改一下顺序"改坏、却只有在真机上点三下才能发现的地方。
PlayMode nextPlayMode(PlayMode current) {
  switch (current) {
    case PlayMode.repeatOne:
      return PlayMode.sequential;
    case PlayMode.sequential:
      return PlayMode.shuffle;
    case PlayMode.shuffle:
      return PlayMode.repeatOne;
  }
}

/// 每种播放模式对应的图标。
///
/// 图标本身就是用户唯一能看到的模式指示，因此单独暴露以便测试钉住
/// 「哪个模式配哪个图标」这一映射关系。
IconData playModeIcon(PlayMode mode) {
  switch (mode) {
    case PlayMode.repeatOne:
      return Icons.repeat_one;
    case PlayMode.sequential:
      return Icons.repeat;
    case PlayMode.shuffle:
      return Icons.shuffle;
  }
}

// 播放模式只读 handler 已发布的 repeat/shuffle 状态。
final playModeProvider = Provider<PlayMode>((ref) {
  final state = ref.watch(playbackStateProvider).value;
  return state == null ? PlayMode.sequential : playModeFromPlaybackState(state);
});

/// 播放位置唯一真相：just_audio position + seek 不连续事件。
/// 进度条 / 时间 / 歌词全部只读这里，禁止各自维护另一套时钟。
class PositionNotifier extends BuildlessNotifier<Duration>
    implements ScrubPosition {
  /// The handler is injected by tests. Provider-hosted instances pass nothing
  /// and pick up the global [audioHandler] from [build].
  PositionNotifier([LxAudioHandler? handler])
    : _injectedHandler = handler,
      super(Duration.zero) {
    // Direct instantiation (tests) has no provider to build, so tracking
    // starts here; provider-hosted instances start it from [build].
    if (handler != null) _startTracking(handler);
  }

  final LxAudioHandler? _injectedHandler;
  AudioPlayer? _player;
  Timer? _timer;
  StreamSubscription<AudioPlayer>? _playerSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PositionDiscontinuity>? _discSub;
  bool _frozen = false;
  bool _trackingStarted = false;
  int _playerBindingGeneration = 0;

  @override
  Duration build() {
    if (!_trackingStarted && _injectedHandler == null) {
      // `audioHandler` is a `late` global; reading it before bootstrap throws.
      // A widget test that overrides this provider has no handler at all.
      try {
        final handler = audioHandler;
        if (handler is LxAudioHandler) _startTracking(handler);
      } catch (_) {
        // No handler yet: stay at zero until the provider is rebuilt.
      }
    }
    return super.build();
  }

  void _startTracking(LxAudioHandler handler) {
    if (_trackingStarted) return;
    _trackingStarted = true;
    _bindPlayer(handler.player);
    _playerSub = handler.playerStream.listen(_bindPlayer);

    // 兜底轮询，覆盖部分 iOS 场景下 positionStream 间歇停更。
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _frozen) return;
      final player = _player;
      if (player == null) return;
      final p = player.position;
      if ((p - value).inMilliseconds.abs() >= 30) update(p);
    });
  }

  void _bindPlayer(AudioPlayer player) {
    if (!mounted || identical(_player, player)) return;
    final bindingGeneration = ++_playerBindingGeneration;
    final oldPositionSubscription = _posSub;
    final oldDiscontinuitySubscription = _discSub;
    _posSub = null;
    _discSub = null;
    _player = player;
    if (oldPositionSubscription != null) {
      unawaited(oldPositionSubscription.cancel());
    }
    if (oldDiscontinuitySubscription != null) {
      unawaited(oldDiscontinuitySubscription.cancel());
    }
    update(player.position);
    _posSub = player.positionStream.listen((position) {
      if (!mounted ||
          _frozen ||
          bindingGeneration != _playerBindingGeneration) {
        return;
      }
      if ((position - value).inMilliseconds.abs() >= 16) update(position);
    });
    _discSub = player.positionDiscontinuityStream.listen((_) {
      if (!mounted ||
          _frozen ||
          bindingGeneration != _playerBindingGeneration) {
        return;
      }
      update(player.position);
    });
  }

  Duration get position => value;

  void update(Duration next) {
    if (!mounted || next == value) return;
    publish(next);
  }

  @override
  void freeze() {
    _frozen = true;
  }

  @override
  void unfreeze(Duration position) {
    update(position);
    _frozen = false;
  }

  void jumpTo(Duration position) {
    if (_frozen) return;
    update(position);
  }

  @override
  void onTeardown() {
    _playerBindingGeneration++;
    _timer?.cancel();
    _playerSub?.cancel();
    _posSub?.cancel();
    _discSub?.cancel();
  }
}

// 监听当前歌曲变化，保存可恢复的播放会话（歌单/队列 + 歌曲，不含进度）
final playbackSessionRecorderProvider = Provider<void>((ref) {
  final music = ref.watch(currentMusicProvider);
  if (music == null) return;
  final playerService = ref.read(playerServiceProvider);
  final store = ref.read(playbackSessionStoreProvider);
  final mediaItem = audioHandler.mediaItem.value;
  final lazyIndex = mediaItem?.extras?['_lazyPlaylistIndex'];
  final playlistId = playerService.currentLazyPlaylistId;
  final currentIndex = lazyIndex is int
      ? lazyIndex
      : playerService.currentIndex >= 0
      ? playerService.currentIndex
      : 0;
  final fullQueue = <MusicItem>[];
  if (playlistId == null) {
    for (final item in playerService.queue) {
      final extras = item.extras;
      if (extras == null) continue;
      fullQueue.add(MusicItem.fromJson(extras));
    }
  }
  final queue = <MusicItem>[];
  var startIndex = currentIndex;
  if (fullQueue.length > 300) {
    final windowStart = (currentIndex - 150)
        .clamp(0, fullQueue.length - 300)
        .toInt();
    queue.addAll(fullQueue.sublist(windowStart, windowStart + 300));
    startIndex = currentIndex - windowStart;
  } else {
    queue.addAll(fullQueue);
  }
  final session = PlaybackSession(
    playlistId: playlistId,
    startIndex: startIndex,
    song: music,
    queue: List.unmodifiable(queue),
  );
  unawaited(store.save(session));
});

/// 启动时恢复上次播放会话：默认只加载队列并暂停，autoplay 由设置控制。
Future<void> restorePlaybackSession({
  required ProviderContainer container,
  required bool autoplay,
}) async {
  final store = container.read(playbackSessionStoreProvider);
  final playerService = container.read(playerServiceProvider);
  final queueGeneration = playerService.beginQueueReplacement();
  final session = await store.load();
  if (session == null || !playerService.ownsQueueReplacement(queueGeneration)) {
    return;
  }
  final playlistService = container.read(playlistServiceProvider);
  try {
    final playlistId = session.playlistId;
    if (playlistId != null) {
      final songCount = playlistService.getPlaylist(playlistId)?.songCount ?? 0;
      if (songCount <= 0) {
        await store.clear();
        return;
      }
      final startIndex = session.startIndex.clamp(0, songCount - 1).toInt();
      await playerService.playPagedPlaylist(
        songCount: songCount,
        startIndex: startIndex,
        playlistId: playlistId,
        autoplay: autoplay,
        userInitiated: false,
        loadPage: (offset, limit) async {
          final page = await playlistService.getSongsPage(
            playlistId,
            offset: offset,
            limit: limit,
          );
          return page.songs;
        },
        queueGeneration: queueGeneration,
      );
      return;
    }
    final queue = session.queue;
    if (queue.isEmpty) {
      await playerService.playPlaylist(
        [session.song],
        index: 0,
        autoplay: autoplay,
        userInitiated: false,
        queueGeneration: queueGeneration,
      );
    } else {
      final startIndex = session.startIndex.clamp(0, queue.length - 1).toInt();
      await playerService.playPlaylist(
        queue,
        index: startIndex,
        autoplay: autoplay,
        userInitiated: false,
        queueGeneration: queueGeneration,
      );
    }
  } catch (_) {
    if (playerService.ownsQueueReplacement(queueGeneration)) {
      await store.clear();
    }
  }
}

// 监听当前歌曲变化，自动记录到最近播放
final recentPlayRecorderProvider = Provider<void>((ref) {
  final music = ref.watch(currentMusicProvider);
  if (music != null) {
    final playlistService = ref.read(playlistServiceProvider);
    unawaited(playlistService.addToRecent(music));
  }
});

// 定时停止播放
sealed class SleepTimerState {
  const SleepTimerState();

  DateTime? get endTime => null;
}

final class SleepTimerIdle extends SleepTimerState {
  const SleepTimerIdle();
}

final class SleepTimerRunning extends SleepTimerState {
  const SleepTimerRunning(
    this.duration,
    this.scheduledEndTime, {
    this.fadeOut = true,
  });

  final Duration duration;
  final DateTime scheduledEndTime;

  /// 结束前是否渐弱，避免在安静的段落里突然静音。
  final bool fadeOut;

  @override
  DateTime get endTime => scheduledEndTime;
}

/// 播完当前这首就停。没有结束时间，界面不显示倒计时。
final class SleepTimerUntilTrackEnd extends SleepTimerState {
  const SleepTimerUntilTrackEnd({this.fadeOut = true});

  final bool fadeOut;
}

enum SleepTimerFailureReason { pauseFailed }

final class SleepTimerFailed extends SleepTimerState {
  const SleepTimerFailed(this.reason, this.duration);

  final SleepTimerFailureReason reason;
  final Duration duration;
}

class SleepTimerNotifier extends BuildlessNotifier<SleepTimerState> {
  /// The pause callback is injected by tests. Provider-hosted instances pass
  /// nothing and use the global [audioHandler] from [build].
  SleepTimerNotifier([Future<void> Function()? pause])
    : _pauseOverride = pause,
      _pause = pause ?? (() async {}),
      super(const SleepTimerIdle());

  /// 渐弱时长。太短听不出来，太长会掐掉整段副歌。
  static const Duration fadeDuration = Duration(seconds: 10);

  final Future<void> Function()? _pauseOverride;
  Future<void> Function() _pause;
  Timer? _timer;
  Timer? _fadeTimer;
  int _generation = 0;
  int _fadeGeneration = 0;
  bool _awaitingTrackEnd = false;
  bool _fadeStarted = false;

  /// 最近一次启动时的渐弱选择。`SleepTimerFailed` 里不带这个字段，
  /// 重试时若不记住它，用户关掉的渐弱会悄悄回弹成开启。
  bool _lastFadeOut = true;

  @override
  SleepTimerState build() {
    if (_pauseOverride != null) {
      _pause = _pauseOverride;
    } else {
      // `audioHandler` is a `late` global; a widget test can mount the sleep
      // timer sheet before bootstrap has assigned it.
      try {
        _pause = audioHandler.pause;
      } catch (_) {
        // Leave the no-op pause in place.
      }
    }
    // 「播完这首就停」只能靠曲目切换来判断：引擎在播放结束时会立刻续上
    // 下一首，等不到 completed 状态。代价是下一首可能已经播了几十毫秒。
    ref.listen<AsyncValue<MediaItem?>>(currentMediaItemProvider, (
      previous,
      next,
    ) {
      if (!_awaitingTrackEnd) return;
      final previousId = previous?.value?.id;
      final nextId = next.value?.id;
      if (previousId == null || nextId == null || previousId == nextId) return;
      unawaited(_finish());
    });
    ref.listen<Duration>(playerPositionProvider, (_, position) {
      if (!_awaitingTrackEnd || _fadeStarted) return;
      final music = ref.read(currentMusicProvider);
      final total = music?.duration;
      if (total == null || total == Duration.zero) return;
      if (total - position <= fadeDuration) _beginFade();
    });
    return super.build();
  }

  void startTimer(Duration duration, {bool fadeOut = true}) {
    _timer?.cancel();
    _lastFadeOut = fadeOut;
    _stopFade(restore: true);
    _awaitingTrackEnd = false;
    final generation = ++_generation;
    publish(
      SleepTimerRunning(
        duration,
        DateTime.now().add(duration),
        fadeOut: fadeOut,
      ),
    );
    if (fadeOut && duration > fadeDuration * 2) {
      final delay = duration - fadeDuration;
      // 渐弱本身用独立的一次性定时器，到点才开始压音量。
      _fadeTimer?.cancel();
      _fadeTimer = Timer(delay, () {
        if (!mounted || generation != _generation) return;
        _beginFade();
      });
    }

    _timer = Timer(duration, () async {
      try {
        await _pause();
        if (!mounted || generation != _generation) return;
        _timer = null;
        _stopFade(restore: true);
        publish(const SleepTimerIdle());
      } catch (_) {
        if (!mounted || generation != _generation) return;
        _timer = null;
        _stopFade(restore: true);
        publish(
          SleepTimerFailed(SleepTimerFailureReason.pauseFailed, duration),
        );
      }
    });
  }

  /// 播完当前曲目后暂停。切歌、手动跳转都会终止定时。
  void startUntilTrackEnd({bool fadeOut = true}) {
    _timer?.cancel();
    _lastFadeOut = fadeOut;
    _timer = null;
    _stopFade(restore: true);
    _generation++;
    _awaitingTrackEnd = true;
    _fadeStarted = false;
    publish(SleepTimerUntilTrackEnd(fadeOut: fadeOut));
  }

  void retryTimer() {
    switch (value) {
      case SleepTimerFailed(:final duration):
        startTimer(duration, fadeOut: _lastFadeOut);
      case SleepTimerRunning(:final duration, :final fadeOut):
        startTimer(duration, fadeOut: fadeOut);
      case _:
        break;
    }
  }

  void cancelTimer() {
    _generation++;
    _awaitingTrackEnd = false;
    _timer?.cancel();
    _timer = null;
    _stopFade(restore: true);
    publish(const SleepTimerIdle());
  }

  bool get _shouldFade => switch (value) {
    SleepTimerRunning(:final fadeOut) => fadeOut,
    SleepTimerUntilTrackEnd(:final fadeOut) => fadeOut,
    _ => false,
  };

  void _beginFade() {
    if (!_shouldFade || _fadeStarted) return;
    _fadeStarted = true;
    final generation = ++_fadeGeneration;
    const steps = 20;
    final interval = fadeDuration ~/ steps;
    var step = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(interval, (timer) {
      if (!mounted || generation != _fadeGeneration) {
        timer.cancel();
        return;
      }
      step++;
      _applyTemporaryGain((1 - step / steps).clamp(0.0, 1.0).toDouble());
      if (step >= steps) timer.cancel();
    });
  }

  void _stopFade({required bool restore}) {
    _fadeGeneration++;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeStarted = false;
    if (restore) _applyTemporaryGain(1);
  }

  void _applyTemporaryGain(double gain) {
    try {
      final handler = audioHandler;
      if (handler is LxAudioHandler) handler.applyTemporaryGain(gain);
    } catch (_) {
      // 引导还没完成，没有处理器可写。
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    _awaitingTrackEnd = false;
    _generation++;
    try {
      await _pause();
      if (!mounted) return;
      _stopFade(restore: true);
      publish(const SleepTimerIdle());
    } catch (_) {
      if (!mounted) return;
      _stopFade(restore: true);
      publish(
        const SleepTimerFailed(
          SleepTimerFailureReason.pauseFailed,
          Duration.zero,
        ),
      );
    }
  }

  @override
  void onTeardown() {
    _generation++;
    _awaitingTrackEnd = false;
    _timer?.cancel();
    _timer = null;
    _stopFade(restore: true);
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
      SleepTimerNotifier.new,
    );

/// 睡眠定时结束前是否渐弱。会话内有效，不落盘——它只是一个夜间开关，
/// 没有跨设备同步的价值。
final sleepTimerFadeProvider = StateProvider<bool>((ref) => true);

// 全局播放消息通知（用于展示顶部通知）
final playerMessageProvider = StateProvider<String?>((ref) => null);

abstract interface class ScrubPlayback {
  bool get playing;
  Duration get position;
  int get sourceGeneration;
  int get userIntentGeneration;
  int get interruptionGeneration;
  int get playbackStartBlockGeneration;

  Future<PreservingPauseOwner?> pauseForScrub({
    required int sourceGeneration,
    required int userIntentGeneration,
    required bool Function() stillOwnsScrub,
  });
  Future<Duration?> seekConfirmed(Duration position);
  Future<void> releaseAfterScrub(
    PreservingPauseOwner? owner, {
    required bool resumeAfter,
    required int sourceGeneration,
    required int userIntentGeneration,
    required int interruptionGeneration,
    required int startBlockGeneration,
  });
}

abstract interface class ScrubPosition {
  void freeze();
  void unfreeze(Duration position);
}

class ScrubCoordinator {
  final ScrubPlayback _playback;
  final ScrubPosition _position;
  int _generation = 0;
  final Map<int, _ScrubTransaction> _transactions = {};

  ScrubCoordinator(this._playback, this._position);

  Future<int> begin() async {
    final previousTransactions = _transactions.values.toList();
    final generation = ++_generation;
    final sourceGeneration = _playback.sourceGeneration;
    final userIntentGeneration = _playback.userIntentGeneration;
    final interruptionGeneration = _playback.interruptionGeneration;
    final startBlockGeneration = _playback.playbackStartBlockGeneration;
    _position.freeze();

    final shouldPause =
        _playback.playing ||
        previousTransactions.any(
          (transaction) =>
              transaction.pauseRequested && transaction.owns(_playback),
        );
    final pauseFuture = shouldPause
        ? _playback.pauseForScrub(
            sourceGeneration: sourceGeneration,
            userIntentGeneration: userIntentGeneration,
            stillOwnsScrub: () => generation == _generation,
          )
        : Future<PreservingPauseOwner?>.value();
    _transactions[generation] = _ScrubTransaction(
      generation: generation,
      sourceGeneration: sourceGeneration,
      userIntentGeneration: userIntentGeneration,
      interruptionGeneration: interruptionGeneration,
      startBlockGeneration: startBlockGeneration,
      pauseFuture: pauseFuture,
      pauseRequested: shouldPause,
    );
    for (final transaction in previousTransactions) {
      unawaited(
        _releaseTransaction(
          transaction,
          resumeAfter: true,
        ).catchError((Object _, StackTrace __) {}),
      );
    }
    try {
      await pauseFuture;
    } catch (_) {
      if (generation == _generation) {
        _position.unfreeze(_playback.position);
      }
      _transactions.remove(generation);
      rethrow;
    }
    return generation;
  }

  Future<void> finish(
    int generation,
    Duration position, {
    required bool resumeAfter,
  }) async {
    final transaction = _transactions[generation];
    if (transaction == null) return;
    if (generation != _generation) {
      await _releaseTransaction(transaction, resumeAfter: true);
      return;
    }
    Duration? confirmed;
    try {
      await transaction.pauseFuture;
      if (generation != _generation) return;
      if (!transaction.owns(_playback)) return;
      confirmed = await _playback.seekConfirmed(position);
      if (generation != _generation) return;
    } finally {
      await _releaseTransaction(
        transaction,
        resumeAfter:
            confirmed != null && resumeAfter && transaction.owns(_playback),
      );
      if (generation == _generation) {
        final actual =
            transaction.sourceGeneration == _playback.sourceGeneration
            ? confirmed ?? _playback.position
            : _playback.position;
        _position.unfreeze(actual);
      }
    }
  }

  Future<void> cancel(int generation) async {
    final transaction = _transactions[generation];
    if (transaction == null) return;
    final ownsCurrent = generation == _generation;
    if (ownsCurrent) _generation++;
    await _releaseTransaction(transaction, resumeAfter: true);
    if (ownsCurrent && _generation == generation + 1) {
      _position.unfreeze(_playback.position);
    }
  }

  Future<void> cancelAll() async {
    final transactions = _transactions.values.toList(growable: false);
    if (transactions.isEmpty) return;
    final cancelledGeneration = _generation;
    _generation++;
    await Future.wait(
      transactions.map(
        (transaction) => _releaseTransaction(transaction, resumeAfter: true),
      ),
    );
    if (_generation == cancelledGeneration + 1) {
      _position.unfreeze(_playback.position);
    }
  }

  Future<void> _releaseTransaction(
    _ScrubTransaction transaction, {
    required bool resumeAfter,
  }) {
    return transaction.releaseFuture ??= () async {
      try {
        final owner = await transaction.pauseFuture;
        await _playback.releaseAfterScrub(
          owner,
          resumeAfter: resumeAfter,
          sourceGeneration: transaction.sourceGeneration,
          userIntentGeneration: transaction.userIntentGeneration,
          interruptionGeneration: transaction.interruptionGeneration,
          startBlockGeneration: transaction.startBlockGeneration,
        );
      } finally {
        if (identical(_transactions[transaction.generation], transaction)) {
          _transactions.remove(transaction.generation);
        }
      }
    }();
  }
}

class _ScrubTransaction {
  final int generation;
  final int sourceGeneration;
  final int userIntentGeneration;
  final int interruptionGeneration;
  final int startBlockGeneration;
  final Future<PreservingPauseOwner?> pauseFuture;
  final bool pauseRequested;
  Future<void>? releaseFuture;

  _ScrubTransaction({
    required this.generation,
    required this.sourceGeneration,
    required this.userIntentGeneration,
    required this.interruptionGeneration,
    required this.startBlockGeneration,
    required this.pauseFuture,
    required this.pauseRequested,
  });

  bool owns(ScrubPlayback playback) =>
      sourceGeneration == playback.sourceGeneration &&
      userIntentGeneration == playback.userIntentGeneration;
}

class _HandlerScrubPlayback implements ScrubPlayback {
  final LxAudioHandler? _handler;
  final PlayerService _fallback;
  final PositionNotifier _position;

  _HandlerScrubPlayback(this._handler, this._fallback, this._position);

  @override
  bool get playing => _handler?.player.playing ?? false;

  @override
  Duration get position => _handler?.player.position ?? _position.position;

  @override
  int get sourceGeneration => _handler?.sourceGeneration ?? 0;

  @override
  int get userIntentGeneration => _handler?.userIntentGeneration ?? 0;

  @override
  int get interruptionGeneration => _handler?.interruptionGeneration ?? 0;

  @override
  int get playbackStartBlockGeneration =>
      _handler?.playbackStartBlockGeneration ?? 0;

  @override
  Future<PreservingPauseOwner?> pauseForScrub({
    required int sourceGeneration,
    required int userIntentGeneration,
    required bool Function() stillOwnsScrub,
  }) =>
      _handler?.pauseForScrub(
        sourceGeneration: sourceGeneration,
        userIntentGeneration: userIntentGeneration,
        stillOwnsScrub: stillOwnsScrub,
      ) ??
      Future<PreservingPauseOwner?>.value();

  @override
  Future<Duration?> seekConfirmed(Duration position) async {
    final handler = _handler;
    if (handler != null) return handler.seekConfirmed(position);
    await _fallback.seek(position);
    return null;
  }

  @override
  Future<void> releaseAfterScrub(
    PreservingPauseOwner? owner, {
    required bool resumeAfter,
    required int sourceGeneration,
    required int userIntentGeneration,
    required int interruptionGeneration,
    required int startBlockGeneration,
  }) =>
      _handler?.releaseAfterScrub(
        owner,
        resumeAfter: resumeAfter,
        sourceGeneration: sourceGeneration,
        userIntentGeneration: userIntentGeneration,
        interruptionGeneration: interruptionGeneration,
        startBlockGeneration: startBlockGeneration,
      ) ??
      Future<void>.value();
}

final scrubCoordinatorProvider = Provider<ScrubCoordinator>((ref) {
  final observe = FireAndForgetObserver();
  final position = ref.read(playerPositionProvider.notifier);
  final handler = audioHandler is LxAudioHandler
      ? audioHandler as LxAudioHandler
      : null;
  final coordinator = ScrubCoordinator(
    _HandlerScrubPlayback(handler, ref.read(playerServiceProvider), position),
    position,
  );
  ref.onDispose(() => observe(coordinator.cancelAll()));
  return coordinator;
});

final beginScrubProvider = Provider<Future<int> Function()>((ref) {
  return ref.read(scrubCoordinatorProvider).begin;
});

final finishScrubProvider =
    Provider<Future<void> Function(int, Duration, {required bool resumeAfter})>(
      (ref) {
        return ref.read(scrubCoordinatorProvider).finish;
      },
    );

final cancelScrubProvider = Provider<Future<void> Function(int)>((ref) {
  return ref.read(scrubCoordinatorProvider).cancel;
});

/// 点击歌词行：使用同一 seek 事务，避免另一套时钟。
final seekProvider = Provider<Future<void> Function(Duration)>((ref) {
  return (Duration position) async {
    final h = audioHandler is LxAudioHandler
        ? audioHandler as LxAudioHandler
        : null;
    final wasPlaying = h?.player.playing ?? false;
    final generation = await ref.read(beginScrubProvider)();
    await ref.read(finishScrubProvider)(
      generation,
      position,
      resumeAfter: wasPlaying,
    );
  };
});
