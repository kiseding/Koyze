// 音源卡片上「检测详情」入口的行为。
//
// 钉三件事：
//   1. 没检测过时右侧不出现问号，避免点开一个空面板；
//   2. 检测过之后问号出现，点开能看到每个平台、每一档音质的结论；
//   3. 明细里的数字来自落盘报告本身，不重新请求。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/custom_source/domain/custom_source.dart';
import 'package:koyze/features/source_check/data/source_check_store.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';
import 'package:koyze/features/source_check/presentation/source_check_details.dart';
import 'package:koyze/features/source_check/presentation/source_check_strip.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CustomSource buildSource(String id) => CustomSource(
    id: id,
    name: '测试音源',
    description: '',
    version: '1.0.0',
    author: 'tester',
    script: '',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  final source = buildSource('src-1');

  SourceCheckReport buildReport() => SourceCheckReport(
    sourceId: source.id,
    sourceName: source.name,
    testedAt: DateTime(2026, 11, 4, 13, 20),
    skippedPlatforms: const ['mg'],
    perPlatform: {
      'tx': SourceCheckPlatformReport(
        platform: 'tx',
        testedAt: DateTime(2026, 11, 4, 13, 20),
        qualities: const {
          'flac': SourceCheckResult(
            platform: 'tx',
            quality: 'flac',
            verdict: SourceCheckVerdict.ok,
            latencyMs: 812,
            sizeBytes: 3355443,
            extension: '.flac',
            coldStart: true,
          ),
          '320k': SourceCheckResult(
            platform: 'tx',
            quality: '320k',
            verdict: SourceCheckVerdict.hardFail,
            latencyMs: 60,
            message: '脚本没有返回播放地址',
          ),
        },
      ),
      'wy': SourceCheckPlatformReport(
        platform: 'wy',
        testedAt: DateTime(2026, 11, 4, 13, 20),
        qualities: const {
          '': SourceCheckResult(
            platform: 'wy',
            quality: '',
            verdict: SourceCheckVerdict.softFail,
            latencyMs: 33000,
            message: '取链接超时（8 秒 + 25 秒重试均未返回）',
          ),
        },
      ),
    },
  );

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  setUp(() {
    // StorageService 是进程级单例，只有第一次取用时才会读 mock prefs，
    // 所以两份用例共用同一份初始数据；「没测过」那条换一个不在报告里的 source id。
    final book = SourceCheckBook.empty.withReport(buildReport());
    SharedPreferences.setMockInitialValues({
      SourceCheckStore.storageKey: jsonEncode(book.toJson()),
    });
  });

  testWidgets('没检测过时不出现问号', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 400,
          child: SourceCheckStrip(source: buildSource('src-never-tested')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('?'), findsNothing);
    expect(find.text('开始检测'), findsOneWidget);
  });

  testWidgets('检测完成后问号点开是本次检测的明细', (tester) async {
    await tester.pumpWidget(
      wrap(SizedBox(width: 400, child: SourceCheckStrip(source: source))),
    );
    await tester.pumpAndSettle();

    expect(find.text('?'), findsOneWidget);

    await tester.tap(find.text('?'));
    await tester.pumpAndSettle();

    // 标题与总体结论（卡片上也有同一句摘要，这里只看弹窗内）
    final dialog = find.byType(SourceCheckDetailsDialog);
    expect(dialog, findsOneWidget);
    expect(find.text('检测详情'), findsOneWidget);
    expect(find.text('测试音源'), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.textContaining('1/2 个平台可用')),
      findsOneWidget,
    );

    // 两个平台的结论
    expect(find.text('QQ音乐'), findsOneWidget);
    expect(find.text('网易云音乐'), findsOneWidget);
    expect(find.text('可用'), findsOneWidget);
    expect(find.text('超时'), findsOneWidget);

    // 每一档音质：延迟、体积、扩展名、冷启动、失败原因
    expect(find.text('无损'), findsOneWidget);
    expect(find.text('320kbps'), findsOneWidget);
    expect(find.text('默认音质'), findsOneWidget);
    expect(find.textContaining('812 ms'), findsOneWidget);
    expect(find.textContaining('3.2 MB'), findsOneWidget);
    expect(find.textContaining('.flac'), findsOneWidget);
    expect(find.textContaining('冷启动'), findsOneWidget);
    expect(find.text('脚本没有返回播放地址'), findsOneWidget);
    expect(find.text('取链接超时（8 秒 + 25 秒重试均未返回）'), findsOneWidget);

    // 没样本曲的平台写在最后
    expect(find.text('没有样本曲，未测：咪咕音乐'), findsOneWidget);
  });
}
