import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/replay_gain.dart';

/// 造一个最小的 FLAC 头 + VORBIS_COMMENT 块。
Uint8List _flacWithVorbis(List<String> comments) {
  final vendor = 'reference libFLAC';
  final body = <int>[];
  void pushLe32(int value) {
    body.addAll([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }

  pushLe32(vendor.length);
  body.addAll(vendor.codeUnits);
  pushLe32(comments.length);
  for (final comment in comments) {
    pushLe32(comment.length);
    body.addAll(comment.codeUnits);
  }
  final header = <int>[
    0x84, // last block + type 4
    (body.length >> 16) & 0xFF,
    (body.length >> 8) & 0xFF,
    body.length & 0xFF,
  ];
  return Uint8List.fromList([...'fLaC'.codeUnits, ...header, ...body]);
}

/// 造一个只有 TXXX 帧的 ID3v2 头。
Uint8List _id3WithTxxx(String description, String value) {
  final frameBody = <int>[
    0x00, // ISO-8859-1
    ...description.codeUnits,
    0x00,
    ...value.codeUnits,
  ];
  final frame = <int>[
    ...'TXXX'.codeUnits,
    (frameBody.length >> 24) & 0xFF,
    (frameBody.length >> 16) & 0xFF,
    (frameBody.length >> 8) & 0xFF,
    frameBody.length & 0xFF,
    0x00,
    0x00,
    ...frameBody,
  ];
  final size = frame.length;
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    0x03,
    0x00,
    0x00, // 无扩展头
    (size >> 21) & 0x7F,
    (size >> 14) & 0x7F,
    (size >> 7) & 0x7F,
    size & 0x7F,
    ...frame,
  ]);
}

void main() {
  group('readReplayGainDb', () {
    test('reads the FLAC vorbis comment', () {
      final bytes = _flacWithVorbis([
        'TITLE=Song',
        'REPLAYGAIN_TRACK_GAIN=-7.23 dB',
      ]);
      expect(readReplayGainDb(bytes), closeTo(-7.23, 0.0001));
    });

    test('is case insensitive about the key', () {
      final bytes = _flacWithVorbis(['replaygain_track_gain=+2.5 dB']);
      expect(readReplayGainDb(bytes), closeTo(2.5, 0.0001));
    });

    test('returns null when the comment is absent', () {
      final bytes = _flacWithVorbis(['TITLE=Song', 'ARTIST=Someone']);
      expect(readReplayGainDb(bytes), isNull);
    });

    test('skips a leading picture block', () {
      // 第一块是 PICTURE（type 6），不带 last 位，长度为 3。
      final picture = <int>[0x06, 0x00, 0x00, 0x03, 1, 2, 3];
      final vorbis = _flacWithVorbis([
        'REPLAYGAIN_TRACK_GAIN=-1.5 dB',
      ]).sublist(4);
      expect(
        readReplayGainDb(
          Uint8List.fromList([...'fLaC'.codeUnits, ...picture, ...vorbis]),
        ),
        closeTo(-1.5, 0.0001),
      );
    });

    test('reads an ID3v2 TXXX frame', () {
      final bytes = _id3WithTxxx('REPLAYGAIN_TRACK_GAIN', '-3.40 dB');
      expect(readReplayGainDb(bytes), closeTo(-3.4, 0.0001));
    });

    test('ignores unrelated TXXX frames', () {
      final bytes = _id3WithTxxx('MusicBrainz Album Id', '-3.40 dB');
      expect(readReplayGainDb(bytes), isNull);
    });

    test('rejects obviously broken values', () {
      expect(
        readReplayGainDb(_flacWithVorbis(['REPLAYGAIN_TRACK_GAIN=999 dB'])),
        isNull,
      );
      expect(
        readReplayGainDb(_flacWithVorbis(['REPLAYGAIN_TRACK_GAIN=abc'])),
        isNull,
      );
    });

    test('never throws on truncated or unknown data', () {
      expect(readReplayGainDb(Uint8List(0)), isNull);
      expect(readReplayGainDb(Uint8List.fromList([1, 2, 3])), isNull);
      expect(readReplayGainDb(Uint8List.fromList('fLaC'.codeUnits)), isNull);
      expect(
        readReplayGainDb(
          Uint8List.fromList([...'fLaC'.codeUnits, 0x84, 0, 0, 200]),
        ),
        isNull,
      );
    });
  });

  group('replayGainFactor', () {
    test('maps dB to a linear multiplier', () {
      expect(replayGainFactor(0), closeTo(1, 1e-9));
      expect(replayGainFactor(-6), closeTo(0.5011, 1e-3));
      expect(replayGainFactor(6), closeTo(1.9952, 1e-3));
    });

    test('falls back to unity for non-finite input', () {
      expect(replayGainFactor(double.nan), 1);
      expect(replayGainFactor(double.infinity), 1);
    });
  });
}
