// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:typed_data';

/// 从文件头认出来的音频容器。
enum VoiceContainer {
  wav('wav'),
  mp3('mp3'),
  m4a('m4a'),
  ogg('ogg'),
  flac('flac'),
  unknown('wav');

  const VoiceContainer(this.wireName);

  /// 报文里 `input_audio.format` 用的名字。接口只认 wav / mp3，
  /// 其余容器会被当成 wav 报上去——至少不会假装成另一种格式。
  final String wireName;
}

/// 按魔数判断这段字节到底是什么容器。
///
/// 不需要完整解析：`record` 在各平台产出的容器不完全一致（Android 的 wav 是
/// 自己封的 WaveContainer，iOS 走 AVAudioRecorder），一旦实际容器和报文里声明的
/// `format` 对不上，服务端解码失败后通常**不报错、直接丢掉音频**，模型于是只能
/// 看到文字。先认出真身再声明，比事后猜要省事。
VoiceContainer sniffVoiceContainer(Uint8List bytes) {
  if (bytes.length < 4) return VoiceContainer.unknown;
  final head = String.fromCharCodes(bytes.sublist(0, 4));

  // RIFF....WAVE——这条要看到第 12 个字节才能确认。
  if (bytes.length >= 12 &&
      head == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE') {
    return VoiceContainer.wav;
  }
  // OggS
  if (head == 'OggS') return VoiceContainer.ogg;
  // fLaC
  if (head == 'fLaC') return VoiceContainer.flac;
  // ID3 开头的 mp3
  if (head.startsWith('ID3')) return VoiceContainer.mp3;
  // ....ftyp 的 m4a / mp4
  if (bytes.length >= 8 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    return VoiceContainer.m4a;
  }
  // 没有 ID3 的裸 mp3：同步字 0xFF 0xEx/0xFx。
  if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
    return VoiceContainer.mp3;
  }
  return VoiceContainer.unknown;
}
