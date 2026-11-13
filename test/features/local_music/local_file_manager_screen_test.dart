import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/presentation/local_file_manager_provider.dart';
import 'package:koyze/features/local_music/presentation/local_file_manager_screen.dart';
import 'package:koyze/features/local_music/presentation/local_music_provider.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 只服务这个页面的替身：`listDirectory` 同步返回固定内容。
///
/// 不用真实 `IoFileSystem`——widget 测试跑在假异步里，真实文件 IO 的
/// Future 不会 resolve，`_loading` 会一直是 true，转圈的进度条让
/// `pumpAndSettle` 永远等不到静止。
class _FakeFileSystem implements LocalFileSystem {
  _FakeFileSystem({required this.entries});

  final Map<String, List<LocalFileEntry>> entries;

  @override
  bool get isSupported => true;

  @override
  Future<List<LocalFileEntry>> listDirectory(String directoryPath) async =>
      entries[directoryPath] ?? const [];

  @override
  Future<String> copyInto(String sourcePath, String targetDirectory) async =>
      '$targetDirectory/$sourcePath';

  @override
  Future<String> moveInto(String sourcePath, String targetDirectory) async =>
      '$targetDirectory/$sourcePath';

  @override
  Future<String> rename(String sourcePath, String newName) async => newName;

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<String> createDirectory(String parentPath, String name) async => name;

  @override
  Future<bool> exists(String path) async => true;

  @override
  bool get needsNativeDirectoryPicker => false;

  @override
  Future<String?> pickDirectory() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const root = '/library/downloads';
  late LocalMusicLibrary library;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'local_music_download_dir_v1': root,
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    library = LocalMusicLibrary(storage: storage);
    await library.init();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFileSystemProvider.overrideWithValue(
            _FakeFileSystem(
              entries: {
                root: const [
                  LocalFileEntry(
                    name: 'a.mp3',
                    path: '$root/a.mp3',
                    isDirectory: false,
                    size: 1024,
                  ),
                  LocalFileEntry(
                    name: 'b.mp3',
                    path: '$root/b.mp3',
                    isDirectory: false,
                    size: 2048,
                  ),
                  LocalFileEntry(
                    name: 'c.mp3',
                    path: '$root/c.mp3',
                    isDirectory: false,
                    size: 4096,
                  ),
                  LocalFileEntry(
                    name: 'sub',
                    path: '$root/sub',
                    isDirectory: true,
                  ),
                ],
              },
            ),
          ),
          localMusicLibraryProvider.overrideWith((ref) async => library),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LocalFileManagerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('路径条与列表不钻到标题栏下面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    // 页面开了 extendBodyBehindAppBar，body 从屏幕最顶开始画。测试环境没有
    // 状态栏 padding，所以顶栏高度就是 kToolbarHeight——内容起点必须让出它，
    // 否则路径条会压着标题（修复前 y≈18，直接在栏底下）。
    expect(
      tester.getTopLeft(find.text(root)).dy,
      greaterThanOrEqualTo(kToolbarHeight),
    );
    expect(
      tester.getTopLeft(find.text('a.mp3')).dy,
      greaterThan(kToolbarHeight),
    );
  });

  testWidgets('多选要看得见：勾选圈、已选数量、全选与取消全选', (tester) async {
    await pumpScreen(tester);

    // 未选中时没有勾选标记，路径条上给的是「全选」。
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('Select all'), findsOneWidget);

    await tester.tap(find.text('a.mp3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b.mp3'));
    await tester.pumpAndSettle();

    // 多选的关键是「点了有反馈」——修复前只有一层几乎看不出的底纹。
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.text('2 selected'), findsOneWidget);

    // 全选：三个文件全选上，子目录不算。
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.text('Deselect all'), findsOneWidget);

    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('重命名对话框退场时不会用到已释放的 controller', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'renamed.mp3');
    await tester.tap(find.text('Save'));

    // 关键窗口：pop 之后对话框还在播退场动画，TextField 仍在树里。
    // 修复前 controller 在这时已经被外层 dispose，重建就抛
    // "A TextEditingController was used after being disposed"，debug 下整页红屏。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 对话框确实关掉了（这里不查通知：通知由 AppNotificationHost 渲染，
    // 本用例的树里没挂它）。
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('选中后再点一次取消，目录行只有文件夹图标', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('a.mp3'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.text('a.mp3'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    // 动作栏随选中出现，取消后应消失。
    expect(find.text('1 selected'), findsNothing);

    // 目录行没有勾选圈，只有文件夹图标。
    expect(find.byIcon(Icons.folder_rounded), findsWidgets);
  });
}
