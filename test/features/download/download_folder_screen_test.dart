import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';
import 'package:koyze/features/download/presentation/download_folder_screen.dart';
import 'package:koyze/features/download/presentation/download_provider.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';
import 'package:koyze/features/local_music/presentation/local_file_manager_provider.dart';
import 'package:koyze/features/settings/presentation/settings_notifiers.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 下载目录是一整页，不是中心弹窗。
///
/// 这一页上的东西不止「选一下」：当前落地路径、默认位置、换目录的影响范围、
/// 已下载的能不能导出——弹窗装不下这些还要滚动，所以 5.2.7 起改成了页面。
/// 这条测试钉的就是「形态」：进得去、看得全、不弹窗、改完不把人弹走。
///
/// 真正的切换（建目录、写探针、归属根、持久化）由
/// `test/features/download/domain/download_directory_test.dart` 覆盖——那些
/// 用例要做真实文件 I/O，放进 widget 测试的假时钟里会卡住，所以这里用桩把
/// provider 换掉，不碰磁盘。
void main() {
  testWidgets('下载目录是整页，能一键恢复默认且停留在页面上', (tester) async {
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
        // 里永远停在 loading，页面就不会画路径。这里直接给同步结果。
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
          home: const DownloadFolderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 形态：一个独立页面，而不是盖在当前页上的弹窗。
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(KoyzeDialog), findsNothing);

    expect(find.text('当前目录'), findsOneWidget);
    // 自定义目录时也列默认位置，用户才知道「恢复默认」会去哪。
    expect(find.text('默认位置'), findsOneWidget);
    expect(find.text(customPath), findsOneWidget);
    expect(find.text(defaultPath), findsOneWidget);
    expect(find.text('选择文件夹'), findsOneWidget);

    final reset = tester.widget<TextButton>(
      find.ancestor(of: find.text('恢复默认'), matching: find.byType(TextButton)),
    );
    expect(reset.onPressed, isNotNull, reason: '自定义目录时恢复默认必须可点');

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    // 恢复默认 = 传 null；页面不关，用户就停在原地看当前目录变化。
    expect(switched, <String?>[null]);
    expect(find.text('当前目录'), findsOneWidget);
    expect(find.byType(KoyzeDialog), findsNothing);
  });

  testWidgets('导出已不在这一页，只留指向本地音乐设置的说明', (tester) async {
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

    final container = ProviderContainer(
      overrides: [
        downloadDirectoryProvider.overrideWith(
          () => DownloadDirectoryNotifier(storage: () async => storage),
        ),
        downloadDirectoryInfoProvider.overrideWith(
          (ref) => const DownloadDirectoryInfo(
            current: customPath,
            defaultPath: defaultPath,
            custom: customPath,
          ),
        ),
        switchDownloadDirectoryProvider.overrideWithValue(
          (path) async => path ?? defaultPath,
        ),
        // 换成**本来会显示导出**的平台。桌面跑测试时导出天然不出现，不换
        // 的话「这页没有导出」就什么都没证明。
        localFileSystemProvider.overrideWithValue(
          AndroidFileSystem(channel: const MethodChannel('test')),
        ),
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
          home: const DownloadFolderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 导出搬去「本地音乐设置」了，这页不该再有自己的导出入口。
    expect(find.text('导出已下载的歌'), findsNothing);
    // 但得指路：上面那句平台说明里提到「导出」，不交代去哪找就是个坑。
    expect(find.textContaining('本地音乐设置'), findsOneWidget);
  });
}
