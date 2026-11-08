// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';

import '../audio/audio_handler.dart';
import '../logging/app_log.dart';
import '../widgets/artwork_disk_cache.dart';
import 'desktop_media_channel.dart';

/// 会话只需要播放器的这一小撮能力。
///
/// 直接依赖 `LxAudioHandler` 会让单测必须拉起整套音频栈；换成窄接口后，
/// 「推什么、什么时候推、命令落到哪」都能用假实现验证。
abstract interface class DesktopMediaSource {
  Stream<MediaItem?> get mediaItemStream;
  Stream<PlaybackState> get playbackStateStream;

  /// 用户拖进度、跳转、换源造成的播放位置不连续。
  Stream<void> get positionJumpStream;

  MediaItem? get currentItem;
  PlaybackState? get currentState;
  Duration get position;
  Duration? get duration;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> skipToNext();
  Future<void> skipToPrevious();
}

/// 把 [LxAudioHandler] 适配成 [DesktopMediaSource]。
final class AudioHandlerMediaSource implements DesktopMediaSource {
  AudioHandlerMediaSource(this._handler, {BehaviorSubject<Duration>? duration})
    : _durationSubject = duration;

  final LxAudioHandler _handler;
  final BehaviorSubject<Duration>? _durationSubject;

  @override
  Stream<MediaItem?> get mediaItemStream => _handler.mediaItem;

  @override
  Stream<PlaybackState> get playbackStateStream => _handler.playbackState;

  @override
  Stream<void> get positionJumpStream => _handler.playerStream.switchMap(
    (player) => player.positionDiscontinuityStream,
  );

  @override
  MediaItem? get currentItem => _handler.mediaItem.value;

  @override
  PlaybackState? get currentState => _handler.playbackState.value;

  @override
  Duration get position => _handler.player.position;

  @override
  Duration? get duration =>
      _durationSubject?.value ?? _handler.player.duration;

  @override
  Future<void> play() => _handler.play();

  @override
  Future<void> pause() => _handler.pause();

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> skipToNext() => _handler.skipToNext();

  @override
  Future<void> skipToPrevious() => _handler.skipToPrevious();
}

/// 把播放状态持续推给操作系统的媒体面板，并把系统命令送回播放器。
///
/// 上层只需要 [init] / [dispose]，其余全自动。所有原生调用失败都只记日志：
/// 老版本桌面包、精简发行版没装 D-Bus、SMTC 被策略禁用，都不该影响播放。
final class DesktopMediaSession {
  DesktopMediaSession({
    required DesktopMediaSource source,
    required DesktopMediaChannel channel,
    Duration positionTick = const Duration(seconds: 1),
  }) : _mediaSource = source,
       _transport = channel,
       _tickInterval = positionTick;

  /// 目前只有这两个平台的系统媒体面板值得接：Android/iOS 走 audio_service，
  /// macOS 走 MPNowPlayingInfoCenter（尚未接入），其余平台没有对应实现。
  static bool get supported =>
      Platform.isWindows || Platform.isLinux;

  final DesktopMediaSource _mediaSource;
  final DesktopMediaChannel _transport;
  final Duration _tickInterval;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, String> _artworkPaths = <String, String>{};
  final Set<String> _artworkRequests = <String>{};

  MediaItem? _item;
  PlaybackState? _state;
  Timer? _ticker;
  bool _initialized = false;
  bool _disposed = false;
  bool _pushing = false;
  bool _dirty = false;

  Future<void> init() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _item = _mediaSource.currentItem;
    _state = _mediaSource.currentState;
    _transport.setCommandHandler(_handleCommand);
    _subscriptions.addAll([
      _mediaSource.mediaItemStream.listen((item) {
        _item = item;
        if (item == null) _artworkPaths.clear();
        unawaited(_requestSync());
      }),
      _mediaSource.playbackStateStream.listen((state) {
        _state = state;
        _syncTicker();
        unawaited(_requestSync());
      }),
      _mediaSource.positionJumpStream.listen((_) => unawaited(_requestSync())),
    ]);
    _syncTicker();
    try {
      await _transport.invoke('initialize');
    } on Object catch (error) {
      AppLog.instance.record(
        'desktop.media',
        'system media panel unavailable: $error',
        level: AppLogLevel.warning,
      );
      return;
    }
    await _requestSync();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _transport.setCommandHandler(null);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _transport.invoke('clear');
    } on Object {
      // 释放阶段不再打扰用户：进程可能已经在退出。
    }
  }

  bool get _playing => _state?.playing ?? false;

  void _syncTicker() {
    if (_disposed) return;
    if (!_playing) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(_tickInterval, (_) => unawaited(_requestSync()));
  }

  /// 合并连续事件：同一个事件循环里来十次，只推最后一次。
  Future<void> _requestSync() async {
    if (_disposed) return;
    _dirty = true;
    if (_pushing) return;
    _pushing = true;
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        await _push();
      }
    } finally {
      _pushing = false;
    }
  }

  Future<void> _push() async {
    final item = _item;
    if (item == null) {
      await _invokeQuietly('clear');
      return;
    }
    final snapshot = _snapshotFor(item);
    await _invokeQuietly('update', snapshot.toMap());
    _resolveArtwork(item);
  }

  DesktopMediaSnapshot _snapshotFor(MediaItem item) {
    final controls = _state?.controls ?? const <MediaControl>[];
    return DesktopMediaSnapshot(
      identity: item.id,
      title: item.title,
      artist: item.artist ?? '',
      album: item.album ?? '',
      durationMs: _durationMs(item),
      positionMs: _positionMs(item),
      playing: _playing,
      canGoNext: controls.contains(MediaControl.skipToNext),
      canGoPrevious: controls.contains(MediaControl.skipToPrevious),
      artworkPath: _artworkPaths[item.id],
      positionSampledAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  int _durationMs(MediaItem item) {
    final playerDuration = _mediaSource.duration;
    if (playerDuration != null && playerDuration > Duration.zero) {
      return playerDuration.inMilliseconds;
    }
    return item.duration?.inMilliseconds ?? 0;
  }

  int _positionMs(MediaItem item) {
    final position = _mediaSource.position;
    final duration = _durationMs(item);
    final clamped = duration > 0
        ? position.inMilliseconds.clamp(0, duration)
        : position.inMilliseconds.clamp(0, 1 << 40);
    return clamped.toInt();
  }

  /// 封面只在内存里查已有缓存；没有就让它在后台落盘，落好后再补推一次。
  void _resolveArtwork(MediaItem item) {
    final url = item.artUri?.toString();
    if (url == null || url.isEmpty) return;
    if (_artworkPaths.containsKey(item.id)) return;
    if (!_artworkRequests.add(item.id)) return;
    unawaited(() async {
      try {
        final file = await ArtworkDiskCache.instance.fileForUrl(url);
        final resolved = file ?? await ArtworkDiskCache.instance.ensureLocalFile(url);
        if (resolved == null || _disposed) return;
        _artworkPaths[item.id] = resolved.path;
        if (_item?.id == item.id) await _requestSync();
      } on Object catch (error) {
        AppLog.instance.record(
          'desktop.media',
          'artwork resolve failed: $error',
          level: AppLogLevel.warning,
        );
      }
    }());
  }

  Future<void> _invokeQuietly(String method, [Object? arguments]) async {
    try {
      await _transport.invoke(method, arguments);
    } on MissingPluginException {
      // 未实现该系统集成的构建：后续调用不必再试。
      _ticker?.cancel();
      _ticker = null;
    } on Object catch (error) {
      AppLog.instance.record(
        'desktop.media',
        '$method failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  Future<void> _handleCommand(DesktopMediaCommand command) async {
    if (_disposed) return;
    try {
      switch (command.method) {
        case 'play':
          await _mediaSource.play();
        case 'pause':
          await _mediaSource.pause();
        case 'playPause':
          if (_playing) {
            await _mediaSource.pause();
          } else {
            await _mediaSource.play();
          }
        case 'next':
          await _mediaSource.skipToNext();
        case 'previous':
          await _mediaSource.skipToPrevious();
        case 'stop':
          await _mediaSource.pause();
          await _mediaSource.seek(Duration.zero);
        case 'seek':
          await _seekBy(_intArgument(command.arguments));
        case 'setPosition':
          final target = _intArgument(command.arguments);
          if (target != null) {
            await _mediaSource.seek(Duration(milliseconds: target));
          }
        default:
          AppLog.instance.record(
            'desktop.media',
            'unsupported command: ${command.method}',
            level: AppLogLevel.warning,
          );
      }
    } on Object catch (error) {
      AppLog.instance.record(
        'desktop.media',
        'command ${command.method} failed: $error',
        level: AppLogLevel.warning,
      );
    }
    await _requestSync();
  }

  Future<void> _seekBy(int? deltaMs) async {
    if (deltaMs == null) return;
    final item = _item;
    if (item == null) return;
    final duration = _durationMs(item);
    var target = _positionMs(item) + deltaMs;
    if (target < 0) target = 0;
    if (duration > 0 && target > duration) target = duration;
    await _mediaSource.seek(Duration(milliseconds: target));
  }

  static int? _intArgument(Object? arguments) {
    if (arguments is int) return arguments;
    if (arguments is double) return arguments.round();
    if (arguments is Map) {
      final value = arguments['positionMs'];
      if (value is int) return value;
      if (value is double) return value.round();
    }
    return null;
  }
}
