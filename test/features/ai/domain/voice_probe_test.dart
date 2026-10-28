// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/voice_probe.dart';

void main() {
  test('探测音频是一段合法的 16 kHz 单声道 PCM wav', () {
    final bytes = buildProbeWav();
    final data = ByteData.sublistView(bytes);

    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(bytes.sublist(12, 16)), 'fmt ');
    expect(ascii.decode(bytes.sublist(36, 40)), 'data');

    // fmt 块：PCM、单声道、16 kHz、16 bit。
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);

    // 两个长度字段要自洽，否则解码器会读到一半就停。
    expect(data.getUint32(4, Endian.little), bytes.length - 8);
    expect(data.getUint32(40, Endian.little), bytes.length - 44);
    expect((bytes.length - 44) % 2, 0);
  });

  test('里面确实有波形，不是一段静音', () {
    final bytes = buildProbeWav();
    final data = ByteData.sublistView(bytes);
    var peak = 0;
    for (var i = 44; i + 1 < bytes.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).abs();
      if (sample > peak) peak = sample;
    }
    // 静音送过去模型听不见，判不出「接口丢了音频」还是「音频本来就是空的」。
    expect(peak, greaterThan(8000));
  });

  test('base64 能被解开且长度一致', () {
    final raw = buildProbeWav();
    final decoded = base64Decode(buildProbeWavBase64());
    expect(decoded.length, raw.length);
  });
}
