// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 一句识别结果。[isFinal] 为真表示这句话不会再变。
typedef VoiceResultCallback = void Function(String words, bool isFinal);

/// 语音输入的抽象。
///
/// 真正的识别在系统里（Android 的 SpeechRecognizer、iOS 的 SFSpeechRecognizer），
/// 这里只负责把它收成三个动作：开始、结束、取消。有了这层，[AiAssistantScreen]
/// 不直接依赖插件，桌面 Linux 之类没有实现的平台也能照常编译。
abstract interface class AiVoiceInput {
  /// 当前平台是否有语音识别能力；false 时界面不显示麦克风。
  bool get isSupported;

  bool get isListening;

  /// 开始聆听。[onResult] 会多次回调中间结果，最后回调一次最终结果。
  /// [onEnd] 在系统自己结束这次聆听时回调（超时、说完、出错），界面据此
  /// 把麦克风按钮改回未按下状态；用户主动停用时不会重复回调。
  /// 返回 false 表示没能启动（没权限、系统没有识别服务、正忙）。
  Future<bool> start(
    VoiceResultCallback onResult, {
    String? localeId,
    VoidCallback? onEnd,
  });

  /// 结束聆听，系统会补一个最终结果。
  Future<void> stop();

  /// 放弃这次聆听，不产生结果。
  Future<void> cancel();
}

/// 没有语音能力的平台用的空实现。
class AiVoiceUnavailable implements AiVoiceInput {
  const AiVoiceUnavailable();

  @override
  bool get isSupported => false;

  @override
  bool get isListening => false;

  @override
  Future<bool> start(
    VoiceResultCallback onResult, {
    String? localeId,
    VoidCallback? onEnd,
  }) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {}
}

/// 系统语音识别。
class SystemVoiceInput implements AiVoiceInput {
  SpeechToText? _speech;
  bool? _ready;
  bool _listening = false;

  @override
  bool get isSupported => true;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> start(
    VoiceResultCallback onResult, {
    String? localeId,
    VoidCallback? onEnd,
  }) async {
    if (_listening) return true;
    final speech = _speech ??= SpeechToText();
    try {
      if (_ready != true) {
        _ready = await speech.initialize(
          onError: (error) {
            if (error.permanent) {
              _listening = false;
              onEnd?.call();
            }
          },
          onStatus: (status) {
            if (status == 'done' || status == 'notListening') {
              _listening = false;
              onEnd?.call();
            }
          },
        );
      }
      if (_ready != true) return false;
      final resolved = await _resolveLocale(speech, localeId);
      await speech.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
          if (result.finalResult) _listening = false;
        },
        listenOptions: SpeechListenOptions(
          localeId: resolved,
          listenFor: const Duration(seconds: 90),
          pauseFor: const Duration(seconds: 6),
          partialResults: true,
          cancelOnError: true,
          // 说一整句话，不是报一个词。
          listenMode: ListenMode.dictation,
        ),
      );
      _listening = true;
      return true;
    } catch (error) {
      debugPrint('[ai.voice] start failed: $error');
      _listening = false;
      return false;
    }
  }

  /// 优先用应用当前语言；系统没装这个语言包时退回系统默认。
  Future<String?> _resolveLocale(SpeechToText speech, String? wanted) async {
    if (wanted == null || wanted.isEmpty) return null;
    try {
      final locales = await speech.locales();
      final normalized = wanted.replaceAll('-', '_').toLowerCase();
      final language = normalized.split('_').first;
      for (final locale in locales) {
        if (locale.localeId.toLowerCase() == normalized) {
          return locale.localeId;
        }
      }
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('${language}_')) {
          return locale.localeId;
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> stop() async {
    _listening = false;
    try {
      await _speech?.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    _listening = false;
    try {
      await _speech?.cancel();
    } catch (_) {}
  }
}

/// 哪些平台有可用的识别实现：插件覆盖 Android / iOS / macOS / Windows。
/// Web 需要额外的脚本注入，这里先当作没有，按钮不出现，也不会有半截功能。
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
AiVoiceInput createVoiceInput() =>
    platformSupportsVoiceInput() ? SystemVoiceInput() : const AiVoiceUnavailable();

final aiVoiceInputProvider = Provider<AiVoiceInput>((ref) {
  final input = createVoiceInput();
  ref.onDispose(() {
    // 页面被销毁时别把麦克风留着。
    input.cancel();
  });
  return input;
});
