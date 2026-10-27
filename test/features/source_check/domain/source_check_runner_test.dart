import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/custom_source/domain/lx_source_capabilities.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/source_check/domain/media_probe.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';
import 'package:koyze/features/source_check/domain/source_check_runner.dart';

void main() {
  final source = _source('s1');

  test('a reachable URL of the right size passes', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': ['flac', '320k']}),
      respond: (_, _) async => (url: 'https://cdn/tx.flac', type: null),
    );
    final probe = _FakeProbe(
      (_, _) async => const MediaProbeResult(
        ok: true,
        message: '',
        sizeBytes: 5 * 1024 * 1024,
        extension: '.flac',
      ),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: probe,
    ).runScript(source);

    expect(report, isNotNull);
    final platform = report!.forPlatform('tx')!;
    expect(platform.anyOk, isTrue);
    expect(platform.allHardFail, isFalse);
    expect(platform.qualities['flac']!.verdict, SourceCheckVerdict.ok);
    expect(platform.qualities['flac']!.extension, equals('.flac'));
  });

  test('only the top declared qualities are probed', () async {
    final probed = <String>[];
    final service = _FakeService(
      capabilities: _capabilities({
        'tx': ['128k', 'flac', '320k', 'hires'],
      }),
      respond: (_, quality) async {
        probed.add(quality);
        return (url: 'https://cdn/tx.mp3', type: null);
      },
    );

    await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
      qualitiesPerPlatform: 2,
    ).runScript(source);

    // 声明顺序被打乱也必须按高→低取前两档。
    expect(probed, equals(['hires', 'flac']));
  });

  test('a platform without a sample is reported as skipped', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null, 'local': null}),
      respond: (_, _) async => (url: 'https://cdn/tx.mp3', type: null),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
    ).runScript(source);

    expect(report!.skippedPlatforms, contains('local'));
    expect(report.perPlatform.keys, equals(['tx']));
  });

  test('no returned URL is a hard failure', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => null,
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
    ).runScript(source);

    final result = report!.forPlatform('tx')!.qualities['']!;
    expect(result.verdict, SourceCheckVerdict.hardFail);
    expect(result.message, contains('没有返回播放地址'));
    expect(report.forPlatform('tx')!.allHardFail, isTrue);
  });

  test('a script error is a hard failure and keeps the message', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => throw Exception('token 已失效'),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
    ).runScript(source);

    final result = report!.forPlatform('tx')!.qualities['']!;
    expect(result.verdict, SourceCheckVerdict.hardFail);
    expect(result.message, equals('token 已失效'));
  });

  test('timing out twice is a soft failure, not a hard one', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) => Completer<({String url, String? type})?>().future,
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
      firstTimeout: const Duration(milliseconds: 10),
      retryTimeout: const Duration(milliseconds: 10),
    ).runScript(source);

    final platform = report!.forPlatform('tx')!;
    expect(platform.qualities['']!.verdict, SourceCheckVerdict.softFail);
    expect(platform.hasSoftFail, isTrue);
    expect(platform.allHardFail, isFalse);
  });

  test('a slow first call that succeeds on retry is marked cold start', () async {
    var calls = 0;
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async {
        calls++;
        if (calls == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
        return (url: 'https://cdn/tx.mp3', type: null);
      },
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
      firstTimeout: const Duration(milliseconds: 20),
      retryTimeout: const Duration(seconds: 2),
    ).runScript(source);

    final result = report!.forPlatform('tx')!.qualities['']!;
    expect(calls, equals(2));
    expect(result.verdict, SourceCheckVerdict.ok);
    expect(result.coldStart, isTrue);
    expect(result.message, contains('冷启动'));
  });

  test('a probe timeout downgrades to a soft failure', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => (url: 'https://cdn/tx.mp3', type: null),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _FakeProbe(
        (_, _) async =>
            const MediaProbeResult.failed('探测超时', timedOut: true),
      ),
    ).runScript(source);

    expect(
      report!.forPlatform('tx')!.qualities['']!.verdict,
      SourceCheckVerdict.softFail,
    );
  });

  test('a listener page instead of audio is a hard failure', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => (url: 'https://cdn/play', type: null),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _FakeProbe(
        (_, _) async => const MediaProbeResult.failed('返回内容不是音频'),
      ),
    ).runScript(source);

    expect(
      report!.forPlatform('tx')!.qualities['']!.verdict,
      SourceCheckVerdict.hardFail,
    );
  });

  test('a clip far shorter than the sample track is rejected', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => (url: 'https://cdn/tx.mp3', type: null),
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _FakeProbe(
        // 样本曲 4:29，64 kbps 下限约 2.05 MB；300 KB 只可能是试听片段。
        (_, _) async => const MediaProbeResult(
          ok: true,
          message: '',
          sizeBytes: 300 * 1024,
          extension: '.mp3',
        ),
      ),
    ).runScript(source);

    final result = report!.forPlatform('tx')!.qualities['']!;
    expect(result.verdict, SourceCheckVerdict.hardFail);
    expect(result.message, contains('疑似试听片段'));
  });

  test('disabled sources are still tested', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => (url: 'https://cdn/tx.mp3', type: null),
    );

    await SourceCheckRunner(service: service, probe: _okProbe()).runScript(
      source,
    );

    // 检测意义在于「能不能用」，与被测试者当前有没有勾选启用无关。
    expect(service.requireEnabledFlags, equals([false]));
  });

  test('a script that fails to load yields no report', () async {
    final service = _FakeService(
      capabilities: null,
      respond: (_, _) async => null,
    );

    expect(
      await SourceCheckRunner(service: service, probe: _okProbe()).runScript(
        source,
      ),
      isNull,
    );
  });

  test('cancelling stops before the next platform', () async {
    var calls = 0;
    final service = _FakeService(
      capabilities: _capabilities({'tx': null, 'kw': null, 'wy': null}),
      respond: (_, _) async {
        calls++;
        return (url: 'https://cdn/x.mp3', type: null);
      },
    );

    final report = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
    ).runScript(source, isCancelled: () => calls >= 1);

    expect(calls, equals(1));
    expect(report!.perPlatform.keys, equals(['tx']));
  });

  test('runAll keeps going when one script cannot be loaded', () async {
    final service = _FakeService(
      capabilities: _capabilities({'tx': null}),
      respond: (_, _) async => (url: 'https://cdn/tx.mp3', type: null),
      missing: {'broken'},
    );
    final progress = <SourceCheckProgress>[];

    final reports = await SourceCheckRunner(
      service: service,
      probe: _okProbe(),
    ).runAll([_source('ok'), _source('broken')], onProgress: progress.add);

    expect(reports.map((report) => report.sourceId), equals(['ok']));
    expect(progress, isNotEmpty);
    expect(progress.last.total, equals(1));
  });
}

CustomSource _source(String id) => CustomSource(
  id: id,
  name: '源 $id',
  description: '',
  version: '1.0.0',
  author: 'tester',
  script: '// script',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

LxSourceCapabilities _capabilities(Map<String, List<String>?> platforms) {
  return LxSourceCapabilities.fromInitData({
    'sources': {
      for (final entry in platforms.entries)
        entry.key: {
          'musicUrl': true,
          if (entry.value != null) 'qualitys': entry.value,
        },
    },
  });
}

MediaProbe _okProbe() => _FakeProbe(
  (_, _) async => const MediaProbeResult(
    ok: true,
    message: '',
    sizeBytes: 5 * 1024 * 1024,
    extension: '.mp3',
  ),
);

class _FakeProbe implements MediaProbe {
  _FakeProbe(this._respond);

  final Future<MediaProbeResult> Function(String url, String platform) _respond;

  @override
  Future<MediaProbeResult> probe(
    String url, {
    required String platform,
    Duration timeout = const Duration(seconds: 6),
  }) => _respond(url, platform);
}

class _FakeService extends CustomSourceService {
  _FakeService({
    required this.capabilities,
    required this.respond,
    this.missing = const <String>{},
  });

  final LxSourceCapabilities? capabilities;
  final Future<({String url, String? type})?> Function(
    String platform,
    String quality,
  )
  respond;

  /// 这些 id 模拟「脚本加载失败」。
  final Set<String> missing;

  final List<bool> requireEnabledFlags = <bool>[];

  @override
  Future<LxSourceCapabilities?> capabilitiesOf(String sourceId) async =>
      missing.contains(sourceId) ? null : capabilities;

  @override
  Future<({String url, String? type})?> getMusicUrlDetailed(
    String sourceId,
    MusicItem music, {
    String quality = '320k',
    bool requireEnabled = true,
  }) {
    requireEnabledFlags.add(requireEnabled);
    return respond(music.platform, quality);
  }
}
