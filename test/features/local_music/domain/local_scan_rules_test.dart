import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';
import 'package:koyze/features/local_music/domain/local_scan_rules.dart';

LocalTrack _track({
  required String title,
  String artist = 'Artist',
  Duration duration = const Duration(seconds: 200),
  int size = 4 * 1024 * 1024,
}) {
  return LocalTrack(
    path: '/music/$title.mp3',
    fileName: '$title.mp3',
    extension: 'mp3',
    size: size,
    modifiedAt: DateTime(2026, 1, 1),
    title: title,
    artist: artist,
    album: 'Album',
    duration: duration,
  );
}

void main() {
  group('LocalScanRules defaults', () {
    test('keeps everything by default', () {
      const rules = LocalScanRules();
      expect(rules.isDefault, isTrue);
      expect(rules.allows(sizeBytes: 1, duration: Duration.zero), isTrue);
      expect(rules.excludes('/anything/at/all'), isFalse);
    });

    test('round-trips through JSON', () {
      const rules = LocalScanRules(
        minDuration: Duration(seconds: 30),
        minSizeBytes: 512 * 1024,
        skipDuplicates: true,
        excludedFolders: ['/music/audiobooks', '/music/samples'],
      );
      final restored = LocalScanRules.fromJson(rules.toJson());
      expect(restored.minDuration, const Duration(seconds: 30));
      expect(restored.minSizeBytes, 512 * 1024);
      expect(restored.skipDuplicates, isTrue);
      expect(restored.excludedFolders, ['/music/audiobooks', '/music/samples']);
      expect(restored.isDefault, isFalse);
    });

    test('negative or corrupt values fall back to permissive defaults', () {
      final rules = LocalScanRules.fromJson({
        'minDurationSeconds': -5,
        'minSizeBytes': -1,
        'skipDuplicates': 'yes',
        'excludedFolders': ['  ', 42, null],
      });
      expect(rules.minDuration, Duration.zero);
      expect(rules.minSizeBytes, 0);
      expect(rules.skipDuplicates, isFalse);
      expect(rules.excludedFolders, ['42']);
    });
  });

  group('excludes', () {
    const rules = LocalScanRules(excludedFolders: ['/Music/Audiobooks']);

    test('matches the folder itself and its subtree', () {
      expect(rules.excludes('/Music/Audiobooks'), isTrue);
      expect(rules.excludes('/Music/Audiobooks/Book 1'), isTrue);
    });

    test('ignores case, separators and trailing slashes', () {
      expect(rules.excludes('/music/audiobooks/'), isTrue);
      const windowsRules = LocalScanRules(
        excludedFolders: [r'C:\Music\Audiobooks'],
      );
      expect(windowsRules.excludes(r'C:\Music\Audiobooks\Book 1'), isTrue);
    });

    test('does not match sibling folders sharing a prefix', () {
      expect(rules.excludes('/Music/Audiobooks2'), isFalse);
      expect(rules.excludes('/Music/Albums'), isFalse);
    });

    test('empty entries are ignored', () {
      const empty = LocalScanRules(excludedFolders: ['', '   ']);
      expect(empty.excludes('/anywhere'), isFalse);
    });
  });

  group('allows', () {
    test('rejects files below the size floor', () {
      const rules = LocalScanRules(minSizeBytes: 1000);
      expect(rules.allows(sizeBytes: 999, duration: Duration.zero), isFalse);
      expect(rules.allows(sizeBytes: 1000, duration: Duration.zero), isTrue);
    });

    test('rejects short clips but keeps unknown durations', () {
      const rules = LocalScanRules(minDuration: Duration(seconds: 30));
      expect(
        rules.allows(sizeBytes: 0, duration: const Duration(seconds: 12)),
        isFalse,
      );
      expect(
        rules.allows(sizeBytes: 0, duration: const Duration(seconds: 30)),
        isTrue,
      );
      // 时长未知（0）时不做判断：否则「探测失败」会被当成「太短」。
      expect(rules.allows(sizeBytes: 0, duration: Duration.zero), isTrue);
    });
  });

  group('duplicateKeyOf', () {
    test('groups by title, artist and whole seconds', () {
      final a = _track(title: 'Song', duration: const Duration(seconds: 201));
      final b = _track(
        title: ' song ',
        artist: ' artist ',
        duration: const Duration(milliseconds: 201900),
      );
      expect(duplicateKeyOf(a), duplicateKeyOf(b));
    });

    test('differs when the duration differs', () {
      final a = _track(title: 'Song', duration: const Duration(seconds: 200));
      final b = _track(title: 'Song', duration: const Duration(seconds: 260));
      expect(duplicateKeyOf(a), isNot(duplicateKeyOf(b)));
    });

    test('returns null when the duration or title is unknown', () {
      expect(
        duplicateKeyOf(_track(title: 'Song', duration: Duration.zero)),
        isNull,
      );
      expect(
        duplicateKeyOf(
          _track(title: '   ', duration: const Duration(seconds: 9)),
        ),
        isNull,
      );
    });
  });
}
