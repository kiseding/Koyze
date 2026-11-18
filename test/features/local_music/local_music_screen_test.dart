import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/card_expand.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/features/download/domain/download_task.dart';
import 'package:koyze/features/download/presentation/download_provider.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/presentation/local_file_manager_provider.dart';
import 'package:koyze/features/local_music/presentation/local_music_provider.dart';
import 'package:koyze/features/local_music/presentation/local_music_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录被 push 的路由，用来判断转场走的是哪一条分支。
class _RouteRecorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

void main() {
  const downloads = '/data/downloads';
  const musicDir = '/storage/Music';

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'local_music_download_dir_v1': downloads,
      'local_music_dirs_v1': <String>[downloads, musicDir],
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final library = LocalMusicLibrary(storage: storage);
    await library.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localMusicLibraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LocalMusicScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('顶部只让出顶栏高度，不再多空一个工具栏', (tester) async {
    await pumpScreen(tester);

    final cardTop = tester.getTopLeft(find.byType(GlassSurface).first).dy;
    // Scaffold 在 extendBodyBehindAppBar 时已经把 AppBar 高度并进 body 的
    // padding.top。修复前 helper 又加了一次 kToolbarHeight，卡片被顶到 112，
    // 比真实栏底低了一整个工具栏——就是「上部留空有点多」的来源。
    final barBottom = MediaQuery.paddingOf(
      tester.element(find.byType(KoyzeAppBarBody)),
    ).top;

    expect(cardTop, barBottom + 8);
  });

  testWidgets('目录长在「本地音乐库」卡片里，且同一路径不重复出现', (tester) async {
    await pumpScreen(tester);

    // 下载目录已经在 _directories 里，来源行不能再渲染一遍。
    expect(find.text(downloads), findsOneWidget);
    expect(find.text(musicDir), findsOneWidget);

    final libraryCard = find
        .ancestor(of: find.text(downloads), matching: find.byType(GlassSurface))
        .first;

    // 同一条祖先链里既有「本地音乐库」标题，说明目录确实在卡片内部，
    // 而不是卡片外一行平级的设置项。
    expect(
      find.descendant(of: libraryCard, matching: find.text('On this device')),
      findsOneWidget,
      reason: '目录必须收在库卡片里，否则用户会读成两个互不相干的设置',
    );

    // 手动添加的目录可以移除；下载目录由下载功能托管，不给移除按钮。
    expect(
      find.descendant(of: libraryCard, matching: find.byIcon(Icons.close)),
      findsOneWidget,
    );
  });

  testWidgets('下载目录那一行可点，直接进下载目录页面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 转场原点也是全局记录，测试之间必须清掉。
    debugResetCardExpandOrigins();
    addTearDown(debugResetCardExpandOrigins);

    SharedPreferences.setMockInitialValues({
      'local_music_download_dir_v1': downloads,
      'local_music_dirs_v1': <String>[downloads, musicDir],
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final library = LocalMusicLibrary(storage: storage);
    await library.init();

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LocalMusicScreen()),
        GoRoute(
          path: '/download-folder',
          pageBuilder: (context, state) => expandablePage(
            state.pageKey,
            const Scaffold(body: Text('download-folder')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localMusicLibraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp.router(
          // 下载目录这一行的标题带着「· 自动收录」，按英文断言更明确。
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Downloads · added automatically'));
    await tester.pumpAndSettle();

    expect(find.text('download-folder'), findsOneWidget);
  });

  testWidgets('文件管理入口沿用设置页的卡片展开转场', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 这个页面自己的展开原点也是全局记录，测试之间必须清掉。
    debugResetCardExpandOrigins();
    addTearDown(debugResetCardExpandOrigins);

    SharedPreferences.setMockInitialValues({
      'local_music_download_dir_v1': downloads,
      'local_music_dirs_v1': <String>[downloads, musicDir],
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final library = LocalMusicLibrary(storage: storage);
    await library.init();

    final recorder = _RouteRecorder();
    final router = GoRouter(
      observers: [recorder],
      routes: [
        GoRoute(path: '/', builder: (context, state) => const LocalMusicScreen()),
        GoRoute(
          path: '/local-file-manager',
          pageBuilder: (context, state) => expandablePage(
            state.pageKey,
            const Scaffold(body: Text('file-manager')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localMusicLibraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('File manager').last);
    await tester.pumpAndSettle();

    expect(find.text('file-manager'), findsOneWidget);
    // expandablePage 只有拿到源矩形才把路由设成透明（卡片矩形 morph）；
    // 拿不到就退化成不透明页 + 上滑淡入，也就是"和设置页手感不一样"。
    expect(
      (recorder.pushed.last as ModalRoute<dynamic>).opaque,
      isFalse,
      reason: '入口必须先 captureCardExpandOrigin，否则转场退回上滑淡入',
    );
  });

  testWidgets('「导出已下载的歌」在本地音乐设置页，数量只算下完的', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({
      'local_music_download_dir_v1': downloads,
      'local_music_dirs_v1': <String>[downloads, musicDir],
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final library = LocalMusicLibrary(storage: storage);
    await library.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localMusicLibraryProvider.overrideWith((ref) async => library),
          // 桌面端没有「导出」这一步（下载直接落公共目录）。要验证这张卡，
          // 得先站到一个本来会显示它的平台上。
          localFileSystemProvider.overrideWithValue(
            AndroidFileSystem(channel: const MethodChannel('test')),
          ),
          // 真身要构造 DownloadService（连 Connectivity 插件），测试里直接
          // 给一份固定任务列表。
          downloadTasksProvider.overrideWithValue([
            DownloadTask(
              id: 'done',
              musicId: 'm1',
              name: 'Downloaded',
              singer: 'Someone',
              savePath: '/x/downloaded.flac',
              status: DownloadStatus.completed,
              createdAt: DateTime(2026, 11, 18),
            ),
            // 没下完的不算：它还没有文件可导。
            DownloadTask(
              id: 'pending',
              musicId: 'm2',
              name: 'Still going',
              singer: 'Someone',
              status: DownloadStatus.downloading,
              createdAt: DateTime(2026, 11, 18),
            ),
          ]),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LocalMusicScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export downloaded songs'), findsOneWidget);
    expect(find.text('1 ready to export'), findsOneWidget);
  });
}
