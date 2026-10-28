// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 录好的一段语音。
///
/// 只带文件路径，不把几百 KB 的字节留在状态里——真正需要 base64 的地方
/// 是发请求那一刻，由 `AiChatNotifier` 读一次就丢掉。
@immutable
class AiVoiceClip {
  const AiVoiceClip({
    required this.path,
    required this.duration,
    required this.format,
    required this.bytes,
  });

  final String path;
  final Duration duration;

  /// 送给接口时声明的格式名。OpenAI 兼容接口的 `input_audio.format` 认
  /// `wav` 和 `mp3`，这里固定录 wav（无外部编码依赖，各平台一致）。
  final String format;

  /// 文件字节数，用来在发出去之前挡住过大的一整段。
  final int bytes;

  /// 展示用的秒数，向上取整：录了 0.2 秒也算 1 秒，不要显示 0。
  int get seconds => duration.inMilliseconds <= 0
      ? 0
      : (duration.inMilliseconds / 1000).ceil();

  /// `0:07` 这种计时显示。
  String get clock {
    final total = duration.inSeconds;
    final minutes = total ~/ 60;
    final rest = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}

/// 录音能力的抽象。
///
/// 这里**不做语音识别**：录到的 wav 原样交给模型，识别由模型自己完成。
/// 有了这层，界面不直接依赖插件，鸿蒙 / Linux 这类没有实现的平台也能照常
/// 编译，只是不显示麦克风。
abstract interface class AiVoiceRecorder {
  /// 当前平台是否装了录音实现；false 时界面不显示麦克风。
  bool get isSupported;

  bool get isRecording;

  /// 申请权限并开始录音。返回 false 表示没能开始（没权限、没有设备、正忙）。
  Future<bool> start();

  /// 结束录音。返回 null 表示这次没录到有效内容（误触、太短），
  /// 这时临时文件已经删掉，界面直接回到未录音状态即可。
  Future<AiVoiceClip?> stop();

  /// 放弃这次录音，不产生结果。
  Future<void> cancel();

  Future<void> dispose();
}

/// 没有录音能力的平台用的空实现。
class AiVoiceUnavailable implements AiVoiceRecorder {
  const AiVoiceUnavailable();

  @override
  bool get isSupported => false;

  @override
  bool get isRecording => false;

  @override
  Future<bool> start() async => false;

  @override
  Future<AiVoiceClip?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

/// 用系统麦克风录音，输出 16 kHz 单声道 wav。
///
/// 单声道 16 kHz 是语音接口的通用档位：一分钟约 1.9 MB，base64 之后
/// 2.6 MB 左右，大多数网关都能收；再高就没有意义了——模型听的是内容，
/// 不是采样率。
class DeviceVoiceRecorder implements AiVoiceRecorder {
  AudioRecorder? _engine;
  Stopwatch? _watch;
  String? _path;
  bool _recording = false;

  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  /// 太短的录音基本都是误触，发出去只会浪费一次请求。
  static const Duration _minimum = Duration(milliseconds: 400);

  @override
  bool get isSupported => true;

  @override
  bool get isRecording => _recording;

  AudioRecorder get _recorder => _engine ??= AudioRecorder();

  @override
  Future<bool> start() async {
    if (_recording) return true;
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}${Platform.pathSeparator}'
          'koyze-voice-${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(_config, path: path);
      _path = path;
      _watch = Stopwatch()..start();
      _recording = true;
      return true;
    } catch (error) {
      debugPrint('[ai.voice] start failed: $error');
      _recording = false;
      return false;
    }
  }

  @override
  Future<AiVoiceClip?> stop() async {
    if (!_recording) return null;
    _recording = false;
    final elapsed = _watch?.elapsed ?? Duration.zero;
    _watch?.stop();
    final fallback = _path;
    _path = null;
    String? saved;
    try {
      saved = await _recorder.stop() ?? fallback;
    } catch (error) {
      debugPrint('[ai.voice] stop failed: $error');
      saved = fallback;
    }
    if (saved == null) return null;
    final file = File(saved);
    if (!await file.exists()) return null;
    final bytes = await file.length();
    // wav 头就有 44 字节，只剩下头说明麦克风压根没进数据。
    if (elapsed < _minimum || bytes <= 44) {
      await _delete(saved);
      return null;
    }
    return AiVoiceClip(
      path: saved,
      duration: elapsed,
      format: 'wav',
      bytes: bytes,
    );
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    _watch?.stop();
    _watch = null;
    final path = _path;
    _path = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (path != null) await _delete(path);
  }

  @override
  Future<void> dispose() async {
    await cancel();
    try {
      await _engine?.dispose();
    } catch (_) {}
    _engine = null;
  }

  static Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 删掉一段不再需要的录音。发送完成、用户取消、页面退出都走这里，
/// 避免临时 wav 在缓存目录里越积越多。
Future<void> discardVoiceClip(AiVoiceClip? clip) async {
  if (clip == null) return;
  try {
    final file = File(clip.path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// 哪些平台有可用的录音实现：插件覆盖 Android / iOS / macOS / Windows。
/// Web 需要额外的脚本注入，Linux 依赖系统装的 parecord/ffmpeg，
/// 这两个先当作没有——按钮不出现，也就不会有半截功能。
bool platformSupportsVoiceInput() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}

/// 供测试替换的构造入口。
AiVoiceRecorder createVoiceRecorder() => platformSupportsVoiceInput()
    ? DeviceVoiceRecorder()
    : const AiVoiceUnavailable();

final aiVoiceRecorderProvider = Provider<AiVoiceRecorder>((ref) {
  final recorder = createVoiceRecorder();
  ref.onDispose(() {
    // 页面被销毁时别把麦克风留着。
    unawaited(recorder.dispose());
  });
  return recorder;
});
