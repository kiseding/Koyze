import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';

void main() {
  test('verdict tokens round-trip and unknown tokens fall back to hard', () {
    for (final verdict in SourceCheckVerdict.values) {
      expect(verdictFromToken(verdictToToken(verdict)), equals(verdict));
    }
    expect(verdictFromToken(null), equals(SourceCheckVerdict.hardFail));
    expect(verdictFromToken('nonsense'), equals(SourceCheckVerdict.hardFail));
  });

  test('a report survives a JSON round-trip', () {
    final book = SourceCheckBook.empty
        .withReport(_report('s1', {
          'tx': {
            'flac': SourceCheckVerdict.ok,
            '320k': SourceCheckVerdict.softFail,
          },
        }, coldStart: true))
        .withReport(_report('s2', {
          'kw': {'128k': SourceCheckVerdict.hardFail},
        }, skipped: ['mg']));

    final restored = SourceCheckBook.fromJson(book.toJson());

    expect(restored.bySource.keys, equals(['s1', 's2']));
    final tx = restored.forSource('s1')!.forPlatform('tx')!;
    expect(tx.qualities['flac']!.verdict, SourceCheckVerdict.ok);
    expect(tx.qualities['flac']!.coldStart, isTrue);
    expect(tx.qualities['320k']!.verdict, SourceCheckVerdict.softFail);
    expect(restored.forSource('s2')!.skippedPlatforms, equals(['mg']));
  });

  test('platform aggregates distinguish "broken" from "slow"', () {
    final broken = _platform('tx', {
      'flac': SourceCheckVerdict.hardFail,
      '320k': SourceCheckVerdict.hardFail,
    });
    expect(broken.allHardFail, isTrue);
    expect(broken.hasSoftFail, isFalse);

    final slow = _platform('tx', {
      'flac': SourceCheckVerdict.softFail,
      '320k': SourceCheckVerdict.hardFail,
    });
    expect(slow.allHardFail, isFalse);
    expect(slow.hasSoftFail, isTrue);

    final mixed = _platform('tx', {
      'flac': SourceCheckVerdict.hardFail,
      '320k': SourceCheckVerdict.ok,
    });
    expect(mixed.allHardFail, isFalse);
    expect(mixed.hasSoftFail, isFalse);
    expect(mixed.anyOk, isTrue);
    expect(mixed.bestLatencyMs, equals(121));
  });

  test('an untested platform never counts as failed', () {
    final empty = SourceCheckPlatformReport(
      platform: 'tx',
      qualities: const {},
      testedAt: DateTime.utc(2026, 10, 27),
    );
    expect(empty.tested, isFalse);
    expect(empty.allHardFail, isFalse);
    expect(empty.hasSoftFail, isFalse);
    expect(empty.bestLatencyMs, isNull);
  });

  test('retainOnly drops reports for scripts that are gone', () {
    final book = SourceCheckBook.empty
        .withReport(_report('s1', {}))
        .withReport(_report('s2', {}));

    expect(book.retainOnly(['s1', 's2']), same(book));
    final pruned = book.retainOnly(['s1']);
    expect(pruned.bySource.keys, equals(['s1']));
  });

  test('malformed JSON reads as an empty book instead of throwing', () {
    expect(SourceCheckBook.fromJson(const {}).bySource, isEmpty);
    expect(
      SourceCheckBook.fromJson(const {
        'sources': {'s1': 'not-a-map'},
      }).bySource,
      isEmpty,
    );
    final partial = SourceCheckBook.fromJson(const {
      'sources': {
        's1': {
          'perPlatform': {
            'tx': {'qualities': 'oops'},
          },
        },
      },
    });
    expect(partial.forSource('s1')!.perPlatform['tx']!.tested, isFalse);
  });
}

SourceCheckPlatformReport _platform(
  String platform,
  Map<String, SourceCheckVerdict> verdicts,
) {
  var latency = 120;
  return SourceCheckPlatformReport(
    platform: platform,
    testedAt: DateTime.utc(2026, 10, 27),
    qualities: {
      for (final entry in verdicts.entries)
        entry.key: SourceCheckResult(
          platform: platform,
          quality: entry.key,
          verdict: entry.value,
          latencyMs: latency++,
        ),
    },
  );
}

SourceCheckReport _report(
  String sourceId,
  Map<String, Map<String, SourceCheckVerdict>> platforms, {
  bool coldStart = false,
  List<String> skipped = const [],
}) {
  return SourceCheckReport(
    sourceId: sourceId,
    sourceName: '源 $sourceId',
    testedAt: DateTime.utc(2026, 10, 27),
    skippedPlatforms: skipped,
    perPlatform: {
      for (final entry in platforms.entries)
        entry.key: SourceCheckPlatformReport(
          platform: entry.key,
          testedAt: DateTime.utc(2026, 10, 27),
          qualities: {
            for (final quality in entry.value.entries)
              quality.key: SourceCheckResult(
                platform: entry.key,
                quality: quality.key,
                verdict: quality.value,
                latencyMs: 100,
                sizeBytes: 5 * 1024 * 1024,
                coldStart: coldStart,
              ),
          },
        ),
    },
  );
}
