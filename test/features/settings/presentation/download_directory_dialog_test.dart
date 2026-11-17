import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';
import 'package:koyze/features/download/presentation/download_provider.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/settings/presentation/settings_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 下载目录走中心弹窗，而不是音质那类底部抽屉。
///
/// 这条测试钉的是「形态」与「接线」：设置里点开下载目录出现的是 KoyzeDialog
/// （带当前目录、默认位置、恢复默认 / 取消 / 选择文件夹），而不是 BottomSheet；
/// 点「恢复默认」传给服务的是 `null`（不是写死的绝对路径，换机器 / 便携模式
/// 换盘仍然对）。
///
/// 真正的切换（建目录、写探针、归属根、持久化）由
/// `test/features/download/domain/download_directory_test.dart` 覆盖——那些
/// 用例要做真实文件 I/O，放进 widget 测试的假时钟里会卡住，所以这里用桩把
/// 两个 provider 换掉，不碰磁盘。
void main() {
  testWidgets('下载目录是中心弹窗，能一键恢复默认', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );

    const customPath = r'D:\Music\Koyze';
    const defaultPath = r'C:\Users\test\Documents\koyze\downloads';

    final switched = <String?>[];
    final container = ProviderContainer(
      overrides: [
        downloadDirectoryProvider.overrideWith(
          () => DownloadDirectoryNotifier(storage: () async => storage),
        ),
        // 真身要 await defaultDownloadDirectory()（真实文件 I/O），在假时钟
        // 里永远停在 loading，弹窗就不会画路径。这里直接给同步结果。
        downloadDirectoryInfoProvider.overrideWith(
          (ref) => const DownloadDirectoryInfo(
            current: customPath,
            defaultPath: defaultPath,
            custom: customPath,
          ),
        ),
        switchDownloadDirectoryProvider.overrideWithValue((path) async {
          switched.add(path);
          return path ?? defaultPath;
        }),
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
          // 英文，下面按中文断言就全找不到。注册真实委托并锁定中文。
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 设置页是懒加载列表，靠后的分组首屏没构建；先滚到目标行再点。
    // scrollUntilVisible / dragUntilVisible 会先判 `evaluate().isEmpty`，
    // 所以必须传原始 finder（`.first` 在空集合上直接抛 Bad state）；
    // scrollable 也要显式指定，否则撞上嵌套滚动视图取不到唯一元素。
    await tester.scrollUntilVisible(
      find.text('下载位置'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载位置').first);
    await tester.pumpAndSettle();

    expect(find.byType(KoyzeDialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    // 设置行副标题也显示当前目录，所以要限定在弹窗里找。
    final dialog = find.byType(KoyzeDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('当前目录')),
      findsOneWidget,
    );
    // 自定义目录时也列默认位置，用户才知道「恢复默认」会去哪。
    expect(
      find.descendant(of: dialog, matching: find.text('默认位置')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(customPath)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text(defaultPath)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('选择文件夹')),
      findsOneWidget,
    );

    final reset = tester.widget<TextButton>(
      find.ancestor(of: find.text('恢复默认'), matching: find.byType(TextButton)),
    );
    expect(reset.onPressed, isNotNull, reason: '自定义目录时恢复默认必须可点');

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    // 恢复默认 = 传 null，弹窗随后关掉。
    expect(switched, <String?>[null]);
    expect(find.byType(KoyzeDialog), findsNothing);
  });
}
