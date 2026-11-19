import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 收藏列表的多选工具条。
///
/// 这里锁的是一个很容易复发的布局约束：AppBar 把 `leading` 收成 56pt 宽，
/// 一个 48pt 的图标按钮刚好放得下，第二个会被排到盒子外面——图标画得出来、
/// 甚至盖在标题上，但点它的位置不在父盒子范围内，命中不了，表现就是
/// 「按钮点不动」。所以多选的全选按钮必须在 `actions` 里。
void main() {
  Playlist favoritesWith(int count) {
    final now = DateTime.utc(2026);
    return Playlist(
      id: 'favorites',
      name: '收藏列表',
      createdAt: now,
      updatedAt: now,
      songs: List.generate(
        count,
        (i) => MusicItem(
          id: 'song-$i',
          name: 'Song $i',
          singer: 'Artist $i',
          source: 'kw',
        ),
      ),
    );
  }

  Future<void> pumpFavorites(WidgetTester tester, Playlist playlist) async {
    final container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(
          _MemoryRepository(
            PlaylistSnapshot(schemaVersion: 1, playlists: [playlist]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('进入多选后全选按钮可以点，点完变成取消全选', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));
    expect(tester.takeException(), isNull, reason: '打开页面不该有溢出或断言');

    // 长按任意一行进入多选。
    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: '多选工具条出现时不该有 RenderFlex 溢出',
    );

    expect(find.byIcon(Icons.select_all), findsOneWidget);
    expect(find.byTooltip('全选'), findsOneWidget);

    // 关键断言：这个按钮必须真的能被点到。位置若落在 leading 盒子外，
    // tap 会因为目标不在命中链上而失败。
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.deselect),
      findsOneWidget,
      reason: '全选后按钮应切换成「取消全选」',
    );
    expect(find.text('已选 30 首'), findsOneWidget, reason: '整页 30 首应全部选中');
    expect(tester.takeException(), isNull);
  });

  testWidgets('再点一次取消全选，一首不剩时退回普通模式', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));

    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    expect(find.text('已选 30 首'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.deselect));
    await tester.pumpAndSettle();

    // 取消全选后没有选中项，多选工具条自动收起。
    expect(find.byIcon(Icons.select_all), findsNothing);
    expect(find.byIcon(Icons.deselect), findsNothing);
    expect(find.byTooltip('播放全部'), findsOneWidget, reason: '回到普通模式的工具栏');
    expect(tester.takeException(), isNull);
  });
}

class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}
