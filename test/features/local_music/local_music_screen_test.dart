import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/presentation/local_music_provider.dart';
import 'package:koyze/features/local_music/presentation/local_music_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
