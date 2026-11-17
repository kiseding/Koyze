import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 设置页的分区顺序不是随手排的，它是一条叙述线：
///
///   音源（从哪来）→ 音乐库（存哪）→ 下载（怎么拿到）→ 播放（怎么听）
///   → 歌词 → 外观 → 数据 → 通用 → 关于
///
/// 这条线一断，用户就得重新猜「这个设置会在哪」。所以这里把它钉住：
/// 分区顺序、以及三处最容易漂移的归属（歌词、下载目录、重置设置）。
///
/// 用超高的视口一次把十张分区卡全部建出来，再按纵坐标比较先后——
/// 懒加载列表在 844 高的手机视口里只会建出前三四个分区。
void main() {
  testWidgets('分区按「一首歌的一生」排，歌词独立成区', (tester) async {
    tester.view.physicalSize = const Size(390, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final container = ProviderContainer(
      overrides: [
        equalizerBridgeProvider.overrideWithValue(
          const UnsupportedEqualizerBridge(),
        ),
        equalizerStorageProvider.overrideWithValue(() async => storage),
        settingsDeviceIdProvider.overrideWith((ref) async => 'device_test'),
        sleepTimerProvider.overrideWith(() => SleepTimerNotifier(() async {})),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // 裸 MaterialApp 的 supportedLocales 只有 en_US，localeOf 会回落到
          // 英文，下面按中文断言就全找不到。
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double topOf(String label) {
      final finder = find.text(label);
      expect(finder, findsOneWidget, reason: '「$label」没找到');
      return tester.getTopLeft(finder).dy;
    }

    const sections = [
      'AI',
      '音源',
      '音乐库',
      '下载',
      '播放',
      '歌词',
      '外观',
      '数据与同步',
      '通用',
      '关于',
    ];
    final tops = [for (final title in sections) topOf(title)];
    for (var i = 1; i < tops.length; i++) {
      expect(
        tops[i],
        greaterThan(tops[i - 1]),
        reason: '「${sections[i]}」应该排在「${sections[i - 1]}」之后',
      );
    }

    // 歌词四项以前一半在播放、一半在外观，用户只能猜。现在整区落在
    // 播放和外观之间，且样式页在最前（它是唯一改「长什么样」的）。
    final lyricDisplay = topOf('歌词显示');
    final lockScreen = topOf('锁屏歌词');
    expect(lyricDisplay, greaterThan(tops[4]), reason: '歌词区应在播放之后');
    expect(lyricDisplay, lessThan(tops[6]), reason: '歌词区应在外观之前');
    expect(lockScreen, greaterThan(lyricDisplay), reason: '样式在开关之前');

    // 下载目录和本地音乐目录是同一件事的两端（换目录会改音乐库的扫描
    // 来源），必须待在同一个分区里，而不是隔着三个分区。
    final downloadFolder = topOf('下载目录');
    expect(downloadFolder, greaterThan(tops[2]), reason: '下载目录应在音乐库区内');
    expect(downloadFolder, lessThan(tops[3]), reason: '下载目录不应落进下载区');

    // 重置设置是唯一不可撤销的入口，排在「关于」之前最后一个位置。
    final reset = topOf('恢复默认设置');
    expect(reset, greaterThan(topOf('清除缓存')));
    expect(reset, lessThan(tops[9]));
  });
}
