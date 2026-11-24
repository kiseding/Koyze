import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 设置页的分区顺序不是随手排的，它是一条叙述线：
///
///   音源（从哪来）→ 音乐库（存哪）→ 下载（怎么拿到）→ 播放（怎么听）
///   → 歌词 → 外观 → 数据 → 通用 → 关于
///
/// 这条线一断，用户就得重新猜「这个设置会在哪」。所以这里把它钉住：
/// 分区顺序，以及最容易漂移的两处归属（歌词、重置设置）；另外钉住「下载目录
/// 不在这一页」——它已经移进「本地音乐目录」页面。
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
        // 频谱条要引擎真的吐 FFT 才可用，测试里没有播放引擎，直接放行。
        playerSpectrumSupportedProvider.overrideWithValue(true),
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

    // 下载目录不再是设置页的一行：它已经收进「本地音乐目录」页面（那一页
    // 列的就是"这个库由哪些目录组成"）。设置页再摆一行等于同一个目录两个
    // 入口。这里钉住「不许加回来」。
    expect(
      find.text('下载目录'),
      findsNothing,
      reason: '下载目录的入口在本地音乐目录页面里，设置页不该再有第二处',
    );

    // 重置设置是唯一不可撤销的入口，排在「关于」之前最后一个位置。
    final reset = topOf('恢复默认设置');
    expect(reset, greaterThan(topOf('清除缓存')));
    expect(reset, lessThan(tops[9]));
  });

  testWidgets('音效项整组搬进均衡器页，频谱留在播放区', (tester) async {
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
        // 频谱条要引擎真的吐 FFT 才可用，测试里没有播放引擎，直接放行。
        playerSpectrumSupportedProvider.overrideWithValue(true),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 这三项以前在「播放」区里，和淡入淡出、跳过静音混排。它们改的是
    // 声音本身，现在归均衡器页（标题仍是「均衡器」）。如果哪天有人把它们
    // 加回设置页，这里会红——同一个开关两个入口是最容易复发的漂移。
    for (final label in ['交叉馈送', '响度均衡', '削波保护']) {
      expect(
        find.text(label),
        findsNothing,
        reason: '「$label」属于均衡器页，设置页不该再有第二处',
      );
    }
    // 频谱只影响画面，不属于音效页；它在播放区，紧跟在音效入口之后。
    expect(find.text('实时频谱'), findsOneWidget);
    // 入口还在，而且搜索「交叉馈送」要能落到它上面（关键词已并进入口行）。
    expect(find.text('均衡器'), findsOneWidget);
  });
}
