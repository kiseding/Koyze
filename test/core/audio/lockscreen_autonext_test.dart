import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:koyze/core/audio/audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    AudioHandlerPlatformDefaults.current = AudioHandlerPlatformDefaults.posix;
  });
  tearDownAll(AudioHandlerPlatformDefaults.resetCurrent);

  late LxAudioHandler handler;
  late _CompletionAudioPlayer player;

  setUp(() {
    player = _CompletionAudioPlayer();
    handler = LxAudioHandler(player: player);
  });

  tearDown(() async {
    await handler.dispose();
  });

  MediaItem item(String id) => MediaItem(
    id: id,
    title: id,
    extras: {'url': 'file:///tmp/$id.mp3', 'requestedQuality': '320k'},
  );

  test('completion reactivates audio session before auto-next', () async {
    await handler.dispose();
    final prepares = <int>[];
    player = _CompletionAudioPlayer();
    handler = LxAudioHandler(
      player: player,
      prepareForPlayback: () async => prepares.add(player.sourceLoadCalls),
    );
    await handler.setPlaylist([item('A'), item('B')]);
    final loadsBefore = player.sourceLoadCalls;
    final rateRestoresBefore = player.nativeRateRestores;
    prepares.clear();

    handler.debugEmitTrackCompleted();
    await pumpEventQueue();

    expect(prepares, isNotEmpty);
    expect(prepares.first, loadsBefore);
    expect(handler.mediaItem.value?.id, 'B');
    expect(player.playing, isTrue);
    expect(player.pauseCalls, 0);
    expect(
      player.nativeRateRestores,
      greaterThan(rateRestoresBefore),
      reason:
          'iOS background pause ends the audio session; auto-next must '
          'poke AVPlayer.rate via setSpeed instead of pause+play',
    );
  });

  test('completion still advances after a cancelled manual skip', () async {
    await handler.setPlaylist([item('A'), item('B')]);
    handler.configureLazyQueue(
      loadMore: (_) async => const <MediaItem>[],
      rebuildForShuffle: (current, shuffle, minimumItems) async =>
          const <MediaItem>[],
    );
    player.gateNextPause();
    final switching = handler.skipToNext();
    await player.pauseStarted.future;
    await handler.updateQueue([handler.queueItems.first]);
    player.releasePause.complete();
    await switching;
    expect(handler.mediaItem.value?.id, 'A');
    expect(player.playing, isTrue);
    await handler.addQueueItem(item('C'));

    player.emitCompleted();
    player.emitCompleted();
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, 'C');
    expect(handler.currentQueueIndex, 1);
  });

  test('duplicate completion advances only once', () async {
    await handler.setPlaylist([item('A'), item('B'), item('C')]);
    final loadsBeforeCompletion = player.sourceLoadCalls;

    player.emitCompleted();
    player.emitCompleted();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 1);
    expect(handler.mediaItem.value?.id, 'B');
    expect(player.sourceLoadCalls, greaterThan(loadsBeforeCompletion));
  });

  test('sequential completion wraps from the last song to the first', () async {
    await handler.setPlaylist([item('A'), item('B'), item('C')]);

    player.emitCompleted();
    await pumpEventQueue();
    player.emitCompleted();
    await pumpEventQueue();
    expect(handler.mediaItem.value?.id, 'C');

    player.emitCompleted();
    await pumpEventQueue();

    expect(handler.mediaItem.value?.id, 'A');
    expect(handler.currentQueueIndex, 0);
    expect(handler.playbackState.value.playing, isTrue);
  });

  test('lazy queue natural end does not stay buffering as playing', () async {
    await handler.setPlaylist([item('A')]);
    handler.configureLazyQueue(
      loadMore: (_) async => const <MediaItem>[],
      rebuildForShuffle: (current, shuffle, minimumItems) async =>
          const <MediaItem>[],
    );

    player.emitCompleted();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.id, 'A');
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.completed,
    );
    expect(handler.playbackState.value.playing, isFalse);
    expect(player.playing, isFalse);
  });

  test(
    'completion from replaced source cannot advance newly installed item',
    () async {
      await handler.setPlaylist([item('A'), item('B')]);
      await handler.updateQueue([item('B'), item('C')]);
      final loadsBeforeCompletion = player.sourceLoadCalls;

      handler.debugEmitTrackCompleted();
      await pumpEventQueue();

      expect(handler.currentQueueIndex, 0);
      expect(handler.mediaItem.value?.id, 'B');
      expect((player.loadedSource as ProgressiveAudioSource).tag.id, 'B');
      expect(player.sourceLoadCalls, loadsBeforeCompletion + 1);
    },
  );

  test('explicit pause wins after completion is claimed', () async {
    await handler.setPlaylist([item('A'), item('B')]);
    final loadsBeforeCompletion = player.sourceLoadCalls;

    handler.debugEmitTrackCompleted();
    await handler.pause();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.id, 'A');
    expect(player.sourceLoadCalls, loadsBeforeCompletion);
    expect(player.playing, isFalse);
  });

  test('explicit pause wins during seamless completion load', () async {
    await handler.setPlaylist([item('A'), item('B')]);
    player.gateNextSourceLoad();

    handler.debugEmitTrackCompleted();
    await player.sourceLoadStarted.future;
    await handler.pause();
    player.releaseSourceLoad.complete();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 1);
    expect(handler.mediaItem.value?.id, 'B');
    expect(player.playing, isFalse);
  });

  test(
    'completion keeps a tagged native source alive while resolving next',
    () async {
      final resolverStarted = Completer<void>();
      final releaseResolver = Completer<void>();
      final next = MediaItem(id: 'B', title: 'B');
      handler.urlResolver = (id, [extras]) async {
        if (id == 'B') {
          resolverStarted.complete();
          await releaseResolver.future;
        }
        return 'file:///tmp/$id.mp3';
      };
      await handler.setPlaylist([item('A'), next]);
      final rateRestoresBefore = player.nativeRateRestores;

      handler.debugEmitTrackCompleted();
      await resolverStarted.future;

      expect(handler.currentQueueIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');
      expect(player.playing, isTrue);
      expect(player.loadedSource, isA<SilenceAudioSource>());
      expect((player.loadedSource as SilenceAudioSource).tag.id, 'B');
      expect(player.pauseCalls, 0);

      releaseResolver.complete();
      await pumpEventQueue();

      expect((player.loadedSource as ProgressiveAudioSource).tag.id, 'B');
      expect(player.playing, isTrue);
      expect(player.pauseCalls, 0);
      expect(
        player.nativeRateRestores,
        greaterThan(rateRestoresBefore),
        reason:
            'silence keepalive leaves playing=true; the real source must '
            'restore AVPlayer.rate without pausing the iOS session',
      );
    },
  );

  test('repeat one completion reloads the current item', () async {
    await handler.setPlaylist([item('A'), item('B')]);
    await handler.setRepeatMode(AudioServiceRepeatMode.one);

    handler.debugEmitTrackCompleted();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.id, 'A');
    expect((player.loadedSource as ProgressiveAudioSource).tag.id, 'A');
  });

  test('pending quality source request makes old completion inert', () async {
    await handler.setPlaylist([item('A'), item('B')]);
    handler.urlResolver = (id, [extras]) async =>
        'file:///tmp/$id-${extras?['requestedQuality']}.mp3';
    player.gateNextPause();

    final reload = handler.applyPreferredQuality('flac');
    await player.pauseStarted.future;
    final loadsBeforeCompletion = player.sourceLoadCalls;
    player.emitCompleted();
    await pumpEventQueue();

    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.id, 'A');
    expect(player.sourceLoadCalls, loadsBeforeCompletion);

    player.releasePause.complete();
    await reload;

    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.id, 'A');
  });

  test('playback errors keep the lock screen session alive while skipping', () {
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    final handler = source.substring(
      source.indexOf('void _handleAuthoritativePlaybackError('),
      source.indexOf('int _publishPlaybackState('),
    );
    expect(handler, contains('playingOverride: true'));
    expect(handler, contains('AudioProcessingState.buffering'));
    expect(handler, isNot(contains('playingOverride: false')));
    expect(handler, isNot(contains('AudioProcessingState.idle')));
  });

  test('completion uses one native signal and no position threshold', () {
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    expect(source, contains('state != EngineProcessingState.completed'));
    expect(
      RegExp(r'processingStateStream\.listen').allMatches(source),
      hasLength(1),
    );
    expect(source, isNot(contains('_player.positionStream.listen')));
    expect(source, isNot(contains('_player.currentIndexStream.listen')));
    expect(source, isNot(contains("_onTrackCompleted('position-end')")));
    expect(source, contains('restartPlayAfterSourceChange: true'));
    expect(source, contains('pauseToRestartNativePlay: Platform.isAndroid'));
    expect(
      source,
      isNot(contains('restartPlayAfterSourceChange: Platform.isAndroid')),
    );
  });

  test('自动连播诊断必须能到达 hilog，而不只是 debugPrint', () {
    // 「播完不自动切下一首」的根因定位全靠这条链上的日志。上一版把它们写进
    // `debugPrint` + `AppLog.record`，结果两个通道在真机上都是瞎的：
    //   * 鸿蒙 HAP 进程的 stdout 没有接收方，`debugPrint` 直接丢弃；
    //   * `AppLog.instance` 是 `AppLog()`，`startRecording` 默认 false，
    //     `record()` 在诊断面板没打开时立刻 return。
    // 于是真机复现时一行日志都没有，只能继续猜。这里把「必须同时写
    // hilog」钉死，避免以后有人把诊断退回成看不见的形式。
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    expect(
      source,
      contains("ohosLog('KoyzeMpv'"),
      reason: '自动连播诊断必须走 hilog，否则鸿蒙真机上完全看不到',
    );
    expect(source, contains('void _logAutoNext('));
    expect(source, contains('void _logCompletionRejected('));

    // 引擎侧的状态迁移同样要靠 hilog：如果 mpv 根本没发 completed，
    // handler 的日志一个字都不会出现，必须能从引擎侧分辨出来。
    final engine = File('lib/core/audio/mpv_engine.dart').readAsStringSync();
    expect(engine, contains("ohosLog('KoyzeMpv'"));
    expect(engine, contains('autonext:'));

    // hilog 通道自己必须是 Web 安全的：它被 audio_handler 引用，而后者在
    // Web 编译图里可达。直接 import dart:ffi 会让 dart2js 整条构建失败。
    final hilog = File('lib/core/logging/ohos_hilog.dart').readAsStringSync();
    expect(hilog, isNot(contains("import 'dart:ffi'")));
    expect(hilog, contains("if (dart.library.io) 'ohos_hilog_native.dart'"));
    expect(
      File('lib/core/logging/ohos_hilog_web.dart').existsSync(),
      isTrue,
      reason: 'Web 分支必须存在，否则 dart2js 会撞上 ffi',
    );
  });

  test('seamless queue-item command remains available for background use', () {
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    expect(source, contains('Duration initialPosition = Duration.zero'));
    expect(source, contains('bool playAfterLoad = true'));
    expect(source, isNot(contains('_skipToNextInternal(seamless: true)')));
    // 拖进度 pause 不清除播放意图
    expect(source, contains('pauseInternal({bool clearIntent = true})'));
  });

  test('default player starts darwin playback without waiting for buffer', () {
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    expect(source, contains('automaticallyWaitsToMinimizeStalling: false'));
    // The eager-start configuration must reach the player constructor, not
    // sit on a detached factory nobody calls. It is scoped to Apple platforms:
    // just_audio forwards automaticallyWaitsToMinimizeStalling to every
    // platform and the OpenHarmony player does not implement
    // setAutomaticallyWaitsToMinimizeStalling.
    expect(
      source,
      contains('audioLoadConfiguration: (Platform.isIOS || Platform.isMacOS)'),
    );
    expect(source, contains('? const AudioLoadConfiguration('));
  });

  test(
    'published playback state never leaks engine idle while media exists',
    () {
      final source = File(
        'lib/core/audio/audio_handler.dart',
      ).readAsStringSync();
      final publish = source.substring(
        source.indexOf('int _publishPlaybackState('),
        // 用方法签名而不是完整箭头体做锚点：play() 现在带淡入逻辑，
        // 早已不是单行表达式了。
        source.indexOf('  Future<void> play()'),
      );
      expect(publish, contains('suppressed engine idle'));
      expect(publish, contains('mediaItem.value != null'));
      expect(publish, contains('AudioProcessingState.buffering'));
      expect(publish, contains('AudioProcessingState.ready'));
    },
  );

  test(
    'repeat is owned by completion policy rather than native source loop',
    () {
      final source = File(
        'lib/core/audio/audio_handler.dart',
      ).readAsStringSync();
      final repeatMode = source.substring(
        source.indexOf('Future<void> setRepeatMode('),
        source.indexOf('Future<void> setShuffleMode('),
      );
      expect(repeatMode, contains('setLoopMode(EngineLoopMode.off)'));
      expect(repeatMode, isNot(contains('setLoopMode(EngineLoopMode.one)')));
      expect(repeatMode, isNot(contains('setLoopMode(EngineLoopMode.all)')));
    },
  );

  test('lock screen duration backfill only happens after source installation '
      'completes and never replaces mediaItem mid-transaction', () {
    final source = File('lib/core/audio/audio_handler.dart').readAsStringSync();
    final backfill = source.substring(
      source.indexOf('_publishKnownDurationIfChanged()'),
      source.indexOf('/// 把 just_audio 解析出的真实时长回填'),
    );
    expect(backfill, contains('_publishKnownDurationIfChanged()'));
    final method = source.substring(
      source.indexOf('void _publishKnownDurationIfChanged()'),
      source.indexOf('bool _ownsOutputRouteRecovery({'),
    );
    expect(
      method,
      contains('_commands.installedSourceIsAuthoritative'),
      reason: '回填必须在源安装完成（authoritative）后才允许',
    );
    expect(
      method,
      contains('_installedPlaybackGeneration != _playGeneration'),
      reason: '过期安装世代不得回填',
    );
    expect(
      method,
      contains('_installedMediaId != _activeItemId'),
      reason: '媒体项必须与当前安装一致才允许回填',
    );
    expect(
      method,
      contains('mediaItem.add(updated)'),
      reason: '回填必须同步发布媒体项，锁屏才能拿到新时长',
    );
  });
}

class _CompletionAudioPlayer extends AudioPlayer {
  final _processingStates = StreamController<ProcessingState>.broadcast();
  AudioSource? loadedSource;
  bool _playing = false;
  bool _shuffleModeEnabled = false;
  int sourceLoadCalls = 0;
  int nativePlayStarts = 0;
  int nativeRateRestores = 0;
  int pauseCalls = 0;
  Completer<void>? _sourceLoadStarted;
  Completer<void>? _releaseSourceLoad;
  Completer<void>? _pauseStarted;
  Completer<void>? _releasePause;

  void emitCompleted() => _processingStates.add(ProcessingState.completed);

  Completer<void> get sourceLoadStarted => _sourceLoadStarted!;
  Completer<void> get releaseSourceLoad => _releaseSourceLoad!;
  Completer<void> get pauseStarted => _pauseStarted!;
  Completer<void> get releasePause => _releasePause!;

  void gateNextSourceLoad() {
    _sourceLoadStarted = Completer<void>();
    _releaseSourceLoad = Completer<void>();
  }

  void gateNextPause() {
    _pauseStarted = Completer<void>();
    _releasePause = Completer<void>();
  }

  @override
  Stream<ProcessingState> get processingStateStream => _processingStates.stream;

  @override
  AudioSource? get audioSource => loadedSource;

  @override
  bool get playing => _playing;

  @override
  bool get shuffleModeEnabled => _shuffleModeEnabled;

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleModeEnabled = enabled;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    sourceLoadCalls++;
    loadedSource = source;
    final started = _sourceLoadStarted;
    final release = _releaseSourceLoad;
    if (started != null && release != null) {
      started.complete();
      await release.future;
      _sourceLoadStarted = null;
      _releaseSourceLoad = null;
    }
    return null;
  }

  @override
  Future<void> play() async {
    // Mirror just_audio: play() is a no-op while playing is still true.
    if (_playing) return;
    nativePlayStarts++;
    _playing = true;
  }

  @override
  Future<void> setSpeed(double speed) async {
    nativeRateRestores++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    final started = _pauseStarted;
    final release = _releasePause;
    if (started != null && release != null) {
      if (!started.isCompleted) started.complete();
      await release.future;
      _pauseStarted = null;
      _releasePause = null;
    }
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    await _processingStates.close();
    await super.dispose();
  }
}
