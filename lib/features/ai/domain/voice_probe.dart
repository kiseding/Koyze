// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';
import 'dart:typed_data';

/// 一段用来探测「接口到底有没有把音频交给模型」的合成 wav。
///
/// 不读麦克风：探测要的是可重复、可判定，用一段固定的方波最省事——录真人的
/// 声音反而引入「模型听不清」这种噪声，分不清是没收到还是听不明白。
///
/// 16 kHz 单声道 16 bit，1.2 秒：三段「响—停—响」，模型真收到音频时能说出
/// 「有声音 / 几声」，没收到时只能照着文字回。
Uint8List buildProbeWav() {
  const sampleRate = 16000;
  const seconds = 1.2;
  final frames = (sampleRate * seconds).round();
  final samples = Int16List(frames);

  // 三段 220 Hz 方波，每段 0.18 秒，间隔 0.22 秒。
  const toneFrames = 2880;
  const gapFrames = 3520;
  var cursor = 0;
  for (var burst = 0; burst < 3 && cursor < frames; burst++) {
    for (var i = 0; i < toneFrames && cursor < frames; i++, cursor++) {
      final period = sampleRate ~/ 220; // 72 帧一个周期
      final high = (cursor % period) < period ~/ 2;
      samples[cursor] = high ? 12000 : -12000;
    }
    cursor += gapFrames;
  }

  final dataLength = frames * 2;
  final file = BytesBuilder(copy: false)
    ..add(_ascii('RIFF'))
    ..add(_uint32(36 + dataLength))
    ..add(_ascii('WAVE'))
    ..add(_ascii('fmt '))
    ..add(_uint32(16)) // PCM 头长度
    ..add(_uint16(1)) // PCM
    ..add(_uint16(1)) // 单声道
    ..add(_uint32(sampleRate))
    ..add(_uint32(sampleRate * 2)) // 每秒字节数
    ..add(_uint16(2)) // 每帧字节数
    ..add(_uint16(16)) // 位深
    ..add(_ascii('data'))
    ..add(_uint32(dataLength));

  final body = ByteData(dataLength);
  for (var i = 0; i < frames; i++) {
    body.setInt16(i * 2, samples[i], Endian.little);
  }
  file.add(body.buffer.asUint8List());
  return file.toBytes();
}

/// 探测用的 wav，直接给到 [AiClient] 需要的 base64。
String buildProbeWavBase64() => base64Encode(buildProbeWav());

List<int> _ascii(String text) => text.codeUnits;

List<int> _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.little);
  return data.buffer.asUint8List();
}

List<int> _uint16(int value) {
  final data = ByteData(2)..setUint16(0, value, Endian.little);
  return data.buffer.asUint8List();
}
