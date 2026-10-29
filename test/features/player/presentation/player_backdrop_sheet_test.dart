import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/player_backdrop.dart';
import 'package:koyze/features/player/presentation/player_backdrop_sheet.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StorageService storage;

  Future<ProviderContainer> harness(
    WidgetTester tester, {
    MusicItem? music,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = StorageService.forTesting(await SharedPreferences.getInstance());
    final container = ProviderContainer(
      overrides: [
        // 直接把两个 notifier 钉在这份内存存储上：`StorageService.instance`
        // 是进程级单例，会缓存第一次拿到的 SharedPreferences 快照，跨用例
        // 复用时会写进上一个用例的存储里。
        playerBackdropBlurProvider.overrideWith(
          () => PlayerBackdropBlurNotifier(storage: () async => storage),
        ),
        playerBackdropScrimProvider.overrideWith(
          () => PlayerBackdropScrimNotifier(storage: () async => storage),
        ),
        if (music != null) currentMusicProvider.overrideWithValue(music),
        currentMediaItemProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerBackdropSheet())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('both tiers are shown with their current values', (tester) async {
    await harness(tester);

    expect(find.text('Background blur'), findsOneWidget);
    expect(find.text('Scrim opacity'), findsOneWidget);
    expect(
      find.text(PlayerBackdrop.blurLabel(PlayerBackdrop.defaultBlur)),
      findsOneWidget,
    );
    expect(
      find.text(PlayerBackdrop.scrimLabel(PlayerBackdrop.defaultScrim)),
      findsOneWidget,
    );
  });

  testWidgets('dragging the blur slider drives the setting', (tester) async {
    final container = await harness(tester);

    await tester.drag(find.byType(Slider).first, const Offset(160, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(
      container.read(playerBackdropBlurProvider),
      greaterThan(PlayerBackdrop.defaultBlur),
    );
    // 面板上显示的值跟着滑杆走，不需要退出重进。
    expect(
      find.text(
        PlayerBackdrop.blurLabel(container.read(playerBackdropBlurProvider)),
      ),
      findsOneWidget,
    );
    // 松手 120ms 之后应该已经落盘。
    expect(
      storage.getDouble('player_backdrop_blur'),
      container.read(playerBackdropBlurProvider),
    );
  });

  testWidgets('reset puts both tiers back to the shipped values', (
    tester,
  ) async {
    final container = await harness(tester);
    container.read(playerBackdropBlurProvider.notifier).setBlur(12);
    container.read(playerBackdropScrimProvider.notifier).setScrim(0.1);
    await tester.pump();

    await tester.tap(find.text('Reset to default'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(
      container.read(playerBackdropBlurProvider),
      PlayerBackdrop.defaultBlur,
    );
    expect(
      container.read(playerBackdropScrimProvider),
      PlayerBackdrop.defaultScrim,
    );
    expect(
      storage.getDouble('player_backdrop_blur'),
      PlayerBackdrop.defaultBlur,
    );
  });

  testWidgets('the preview names the song that is actually playing', (
    tester,
  ) async {
    await harness(
      tester,
      music: MusicItem(
        id: 'p1',
        name: '晴天',
        singer: '周杰伦',
        source: 'local',
        duration: const Duration(seconds: 269),
      ),
    );

    expect(find.text('晴天'), findsOneWidget);
    expect(find.text('周杰伦'), findsOneWidget);
  });

  testWidgets('nothing playing still shows a usable preview', (tester) async {
    await harness(tester);

    expect(find.text('Nothing playing'), findsOneWidget);
  });
}
