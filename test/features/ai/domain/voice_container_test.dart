// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/voice_container.dart';
import 'package:koyze/features/ai/domain/voice_probe.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  test('认出 RIFF/WAVE', () {
    expect(sniffVoiceContainer(buildProbeWav()), VoiceContainer.wav);
  });

  test('认出带 ID3 的 mp3', () {
    final head = _bytes([...ascii.encode('ID3'), 4, 0, 0, 0, 0, 0, 0])
      ..[5] = 0x04;
    expect(sniffVoiceContainer(head), VoiceContainer.mp3);
  });

  test('认出裸 mp3 的同步字', () {
    expect(
      sniffVoiceContainer(_bytes([0xFF, 0xFB, 0x90, 0x00, 0, 0, 0, 0, 0, 0])),
      VoiceContainer.mp3,
    );
  });

  test('认出 m4a 的 ftyp', () {
    final head = <int>[...ascii.encode('....'), ...ascii.encode('ftyp')]
      ..[0] = 0
      ..[1] = 0
      ..[2] = 0
      ..[3] = 0x20;
    expect(sniffVoiceContainer(_bytes(head)), VoiceContainer.m4a);
  });

  test('认出 OggS 与 fLaC', () {
    expect(
      sniffVoiceContainer(_bytes([...ascii.encode('OggS'), 0, 0, 0, 0, 0, 0])),
      VoiceContainer.ogg,
    );
    expect(
      sniffVoiceContainer(_bytes([...ascii.encode('fLaC'), 0, 0, 0, 0, 0, 0])),
      VoiceContainer.flac,
    );
  });

  test('太短或认不出来时退回 wav，至少不改坏报文', () {
    expect(sniffVoiceContainer(_bytes([1, 2, 3])), VoiceContainer.unknown);
    expect(sniffVoiceContainer(_bytes(List<int>.filled(32, 0))).wireName, 'wav');
    expect(VoiceContainer.m4a.wireName, 'm4a');
  });
}
