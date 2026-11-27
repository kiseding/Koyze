import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/stats/data/play_history_store.dart';
import 'package:koyze/features/stats/presentation/play_history_provider.dart';
import 'package:koyze/features/stats/presentation/stats_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('歌曲排行把播放次数放在歌曲行右侧', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PlayHistoryStore(() async => throw StateError('unused'))
      ..record(
        songId: 'song-1',
        songTitle: '测试歌曲',
        artistName: '测试歌手',
        albumTitle: '测试专辑',
        source: 'tx',
        startedAt: DateTime.now(),
        listenedSec: 45,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playHistoryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text('测试歌曲');
    final artist = find.text('测试歌手');
    final count = find.text('1次');
    expect(title, findsOneWidget);
    expect(artist, findsOneWidget);
    expect(count, findsOneWidget);
    expect(
      tester.getTopLeft(count).dx,
      greaterThan(tester.getTopLeft(title).dx),
    );
    expect(find.text('测试歌手 · 1次'), findsNothing);

    store.dispose();
  });

  testWidgets('有数据时显示生成听歌海报入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PlayHistoryStore(() async => throw StateError('unused'))
      ..record(
        songId: 'song-1',
        songTitle: '测试歌曲',
        artistName: '测试歌手',
        albumTitle: '测试专辑',
        source: 'tx',
        startedAt: DateTime.now(),
        listenedSec: 45,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playHistoryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('生成听歌海报'), findsOneWidget);
    // 时段分布卡片：有播放数据时应渲染出来。
    expect(find.text('一天中的收听分布'), findsOneWidget);

    store.dispose();
  });

  testWidgets('无播放数据时不显示海报入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = PlayHistoryStore(() async => throw StateError('unused'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playHistoryStoreProvider.overrideWithValue(store)],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('生成听歌海报'), findsNothing);
    store.dispose();
  });
}
