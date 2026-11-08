// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/services.dart';

/// 桌面端系统媒体集成（Windows SMTC / Linux MPRIS）的通道抽象。
///
/// 拆出接口而不是直接调 [MethodChannel]，是因为「什么时候推、推什么、收到命令
/// 怎么落到播放器」这三件事都需要能在单测里验证，而真机通道在测试里不存在。
abstract interface class DesktopMediaChannel {
  /// 调用原生方法。原生实现缺失时必须静默失败（老版本桌面包没有这个通道）。
  Future<void> invoke(String method, [Object? arguments]);

  /// 注册来自系统的控制命令（播放/暂停/上一首/下一首/拖动进度）。
  void setCommandHandler(DesktopMediaCommandHandler? handler);
}

/// 系统下发的控制命令。
typedef DesktopMediaCommand = ({String method, Object? arguments});

typedef DesktopMediaCommandHandler =
    Future<void> Function(DesktopMediaCommand command);

/// 通道名。原生侧 Windows 与 Linux 使用同一个名字、同一套方法语义。
const String kDesktopMediaChannelName = 'koyze/desktop_media';

/// [MethodChannel] 实现。
final class MethodChannelDesktopMediaChannel implements DesktopMediaChannel {
  MethodChannelDesktopMediaChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kDesktopMediaChannelName);

  final MethodChannel _channel;
  DesktopMediaCommandHandler? _handler;
  bool _listening = false;

  @override
  Future<void> invoke(String method, [Object? arguments]) {
    return _channel.invokeMethod<void>(method, arguments);
  }

  @override
  void setCommandHandler(DesktopMediaCommandHandler? handler) {
    _handler = handler;
    if (handler != null) {
      if (_listening) return;
      _channel.setMethodCallHandler(_dispatch);
      _listening = true;
      return;
    }
    if (!_listening) return;
    _channel.setMethodCallHandler(null);
    _listening = false;
  }

  Future<Object?> _dispatch(MethodCall call) async {
    final handler = _handler;
    if (handler == null) return null;
    await handler((method: call.method, arguments: call.arguments));
    return null;
  }
}

/// 一次推送所需的全部字段。
///
/// 位置不是「当前播放位置」而是「推送那一刻的位置」：系统侧会用时间戳自己外推，
/// 所以这里必须带上采样时间，否则播放器暂停后进度条还会继续走。
class DesktopMediaSnapshot {
  const DesktopMediaSnapshot({
    required this.identity,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.positionMs,
    required this.playing,
    required this.canGoNext,
    required this.canGoPrevious,
    this.artworkPath,
    this.positionSampledAtMs,
  });

  final String identity;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int positionMs;
  final bool playing;
  final bool canGoNext;
  final bool canGoPrevious;

  /// 本地封面文件路径。原生侧自行读文件，避免再走一次网络。
  final String? artworkPath;

  /// 采样时刻（epoch ms）。缺省由原生侧按收到时间处理。
  final int? positionSampledAtMs;

  Map<String, Object?> toMap() => {
    'identity': identity,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMs,
    'positionMs': positionMs,
    'playing': playing,
    'canGoNext': canGoNext,
    'canGoPrevious': canGoPrevious,
    if (artworkPath != null) 'artworkPath': artworkPath,
    if (positionSampledAtMs != null) 'sampledAtMs': positionSampledAtMs,
  };

  DesktopMediaSnapshot copyWith({
    String? identity,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    int? positionMs,
    bool? playing,
    bool? canGoNext,
    bool? canGoPrevious,
    String? artworkPath,
    int? positionSampledAtMs,
  }) {
    return DesktopMediaSnapshot(
      identity: identity ?? this.identity,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      positionMs: positionMs ?? this.positionMs,
      playing: playing ?? this.playing,
      canGoNext: canGoNext ?? this.canGoNext,
      canGoPrevious: canGoPrevious ?? this.canGoPrevious,
      artworkPath: artworkPath ?? this.artworkPath,
      positionSampledAtMs: positionSampledAtMs ?? this.positionSampledAtMs,
    );
  }
}
