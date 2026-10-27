import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/source_check/domain/source_check_policy.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  test('an empty book leaves the order untouched', () {
    final policy = SourceCheckPolicy();
    expect(policy.order(['a', 'b'], 'tx', now: now), equals(['a', 'b']));
  });

  test('hard failures are dropped, soft failures sink to the end', () {
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty
          .withReport(
            _report('a', 'tx', ['flac'], SourceCheckVerdict.hardFail, now),
          )
          .withReport(
            _report('b', 'tx', ['flac'], SourceCheckVerdict.softFail, now),
          )
          .withReport(
            _report('c', 'tx', ['flac'], SourceCheckVerdict.ok, now),
          ),
    );

    expect(
      policy.order(['a', 'b', 'c'], 'tx', now: now),
      equals(['c', 'b']),
    );
    expect(policy.isHardFail('a', 'tx', now: now), isTrue);
    expect(policy.isSoftFail('b', 'tx', now: now), isTrue);
  });

  test('a report older than maxAge stops influencing playback', () {
    final stale = now.subtract(const Duration(days: 8));
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty.withReport(
        _report('a', 'tx', ['flac'], SourceCheckVerdict.hardFail, stale),
      ),
    );

    expect(policy.isHardFail('a', 'tx', now: now), isFalse);
    expect(policy.order(['a', 'b'], 'tx', now: now), equals(['a', 'b']));
  });

  test('one good quality keeps the script in the list', () {
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty.withReport(
        SourceCheckReport(
          sourceId: 'a',
          sourceName: 'A',
          testedAt: now,
          perPlatform: {
            'tx': SourceCheckPlatformReport(
              platform: 'tx',
              testedAt: now,
              qualities: {
                'flac': _result('tx', 'flac', SourceCheckVerdict.hardFail),
                '320k': _result('tx', '320k', SourceCheckVerdict.ok),
              },
            ),
          },
        ),
      ),
    );

    expect(policy.isHardFail('a', 'tx', now: now), isFalse);
    expect(policy.order(['a', 'b'], 'tx', now: now), equals(['a', 'b']));
  });

  test('another platform\'s verdict does not leak across platforms', () {
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty.withReport(
        _report('a', 'tx', ['flac'], SourceCheckVerdict.hardFail, now),
      ),
    );

    expect(policy.order(['a', 'b'], 'kw', now: now), equals(['a', 'b']));
  });

  test('if everything failed, the original order is restored', () {
    // 检测结果不该把播放彻底卡死：全灭时退回原顺序，让运行时自己再试一次。
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty
          .withReport(
            _report('a', 'tx', ['flac'], SourceCheckVerdict.hardFail, now),
          )
          .withReport(
            _report('b', 'tx', ['flac'], SourceCheckVerdict.hardFail, now),
          ),
    );

    expect(policy.order(['a', 'b'], 'tx', now: now), equals(['a', 'b']));
  });

  test('an untested platform inside a report is not a failure', () {
    final policy = SourceCheckPolicy(
      book: SourceCheckBook.empty.withReport(
        SourceCheckReport(
          sourceId: 'a',
          sourceName: 'A',
          testedAt: now,
          perPlatform: const {},
          skippedPlatforms: const ['tx'],
        ),
      ),
    );

    expect(policy.isHardFail('a', 'tx', now: now), isFalse);
    expect(policy.order(['a', 'b'], 'tx', now: now), equals(['a', 'b']));
  });
}

SourceCheckResult _result(
  String platform,
  String quality,
  SourceCheckVerdict verdict,
) => SourceCheckResult(
  platform: platform,
  quality: quality,
  verdict: verdict,
  latencyMs: 100,
  sizeBytes: 5 * 1024 * 1024,
);

SourceCheckReport _report(
  String sourceId,
  String platform,
  List<String> qualities,
  SourceCheckVerdict verdict,
  DateTime testedAt,
) => SourceCheckReport(
  sourceId: sourceId,
  sourceName: '源 $sourceId',
  testedAt: testedAt,
  perPlatform: {
    platform: SourceCheckPlatformReport(
      platform: platform,
      testedAt: testedAt,
      qualities: {
        for (final quality in qualities)
          quality: _result(platform, quality, verdict),
      },
    ),
  },
);
