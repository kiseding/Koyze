import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/custom_source/domain/lx_source_capabilities.dart';
import 'package:koyze/features/custom_source/presentation/custom_source_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/source_check/data/source_check_store.dart';
import 'package:koyze/features/source_check/domain/media_probe.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';
import 'package:koyze/features/source_check/domain/source_check_runner.dart';
import 'package:koyze/features/source_check/domain/source_check_samples.dart';
import 'package:koyze/features/source_check/presentation/source_check_provider.dart';
import 'package:koyze/features/source_check/presentation/source_check_screen.dart';

void main() {
  testWidgets('points at the script page when nothing is imported', (
    tester,
  ) async {
    await tester.pumpWidget(_app(service: _FakeService(const [])));
    await tester.pumpAndSettle();

    expect(
      find.text('No source scripts yet. Import one first.'),
      findsOneWidget,
    );
    expect(find.text('Run check'), findsNothing);
  });

  testWidgets('expands a card into one row per quality', (tester) async {
    final book = SourceCheckBook.empty.withReport(_report());
    await tester.pumpWidget(
      _app(
        service: _FakeService([_source('s1')]),
        book: book,
      ),
    );
    await tester.pumpAndSettle();

    // 折叠时只给一行摘要：一个平台可用。
    expect(find.textContaining('1/1 platforms usable'), findsOneWidget);
    expect(find.text('Lossless'), findsNothing);

    await tester.tap(find.text('Source s1'));
    await tester.pumpAndSettle();

    expect(find.text('Lossless'), findsOneWidget);
    expect(find.text('320kbps'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.textContaining('返回内容不是音频'), findsOneWidget);
  });

  testWidgets('running the check fills the card with fresh results', (
    tester,
  ) async {
    final service = _FakeService([_source('s1')]);
    await tester.pumpWidget(
      _app(
        service: service,
        runner: SourceCheckRunner(
          service: service,
          probe: _FakeProbe(),
          samples: _samples,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not tested'), findsWidgets);

    await tester.tap(find.text('Run check'));
    await tester.pumpAndSettle();

    // 样本表里只有 tx，脚本也只声明了 tx → 一跑就出结论。
    expect(find.textContaining('1/1 platforms usable'), findsOneWidget);
    expect(find.text('Run check'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('disabled scripts are checked too', (tester) async {
    final service = _FakeService([_source('s1', enabled: false)]);
    await tester.pumpWidget(
      _app(
        service: service,
        runner: SourceCheckRunner(
          service: service,
          probe: _FakeProbe(),
          samples: _samples,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Disabled'), findsOneWidget);

    await tester.tap(find.text('Run check'));
    await tester.pumpAndSettle();

    // 卡片上就列着它，不给结论只会一直显示「没测过」。
    expect(find.textContaining('1/1 platforms usable'), findsOneWidget);
  });
}

const _samples = {
  'tx': SourceCheckSample(
    platform: 'tx',
    name: '晴天',
    singer: '周杰伦',
    songmid: '0039MnYb0qxYhV',
    duration: Duration(minutes: 4, seconds: 29),
  ),
};

Widget _app({
  required CustomSourceService service,
  SourceCheckBook book = SourceCheckBook.empty,
  SourceCheckRunner? runner,
}) {
  return ProviderScope(
    overrides: [
      customSourceServiceProvider.overrideWithValue(service),
      sourceCheckStoreProvider.overrideWithValue(_FakeStore(book)),
      if (runner != null) sourceCheckRunnerProvider.overrideWithValue(runner),
    ],
    child: const MaterialApp(home: SourceCheckScreen()),
  );
}

CustomSource _source(String id, {bool enabled = true}) => CustomSource(
  id: id,
  name: 'Source $id',
  description: '',
  version: '1.0.0',
  author: 'tester',
  script: '// script',
  isEnabled: enabled,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

SourceCheckReport _report() => SourceCheckReport(
  sourceId: 's1',
  sourceName: 'Source s1',
  testedAt: DateTime.utc(2026, 10, 27, 20, 5),
  perPlatform: {
    'tx': SourceCheckPlatformReport(
      platform: 'tx',
      testedAt: DateTime.utc(2026, 10, 27, 20, 5),
      qualities: const {
        'flac': SourceCheckResult(
          platform: 'tx',
          quality: 'flac',
          verdict: SourceCheckVerdict.ok,
          latencyMs: 420,
          sizeBytes: 30 * 1024 * 1024,
          extension: '.flac',
        ),
        '320k': SourceCheckResult(
          platform: 'tx',
          quality: '320k',
          verdict: SourceCheckVerdict.hardFail,
          latencyMs: 180,
          message: '返回内容不是音频',
        ),
      },
    ),
  },
);

class _FakeStore extends SourceCheckStore {
  _FakeStore(this._book);

  final SourceCheckBook _book;

  @override
  Future<SourceCheckBook> load() async => _book;

  @override
  Future<void> save(SourceCheckBook book) async {}
}

class _FakeService extends CustomSourceService {
  _FakeService(this._sources);

  final List<CustomSource> _sources;

  @override
  List<CustomSource> get sources => _sources;

  @override
  Future<void> init() async {}

  @override
  Future<LxSourceCapabilities?> capabilitiesOf(String sourceId) async {
    return LxSourceCapabilities.fromInitData(const {
      'sources': {
        'tx': {'musicUrl': true},
      },
    });
  }

  @override
  Future<({String url, String? type})?> getMusicUrlDetailed(
    String sourceId,
    MusicItem music, {
    String quality = '320k',
    bool requireEnabled = true,
  }) async => (url: 'https://cdn/tx.mp3', type: null);
}

class _FakeProbe implements MediaProbe {
  @override
  Future<MediaProbeResult> probe(
    String url, {
    required String platform,
    Duration timeout = const Duration(seconds: 6),
  }) async => const MediaProbeResult(
    ok: true,
    message: '',
    sizeBytes: 8 * 1024 * 1024,
    extension: '.mp3',
  );
}
