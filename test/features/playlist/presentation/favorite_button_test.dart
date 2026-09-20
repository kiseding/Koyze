import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/core/widgets/favorite_button.dart';

void main() {
  test('favorite button animates with scale on tap', () {
    final source = File(
      'lib/core/widgets/favorite_button.dart',
    ).readAsStringSync();

    expect(source, contains('ScaleTransition'));
    expect(source, contains('TweenSequence'));
    expect(source, contains('elasticOut'));
    expect(source, contains('favorite_border'));
    expect(source, contains('toggleFavoriteProvider'));
    expect(source, contains('isSongFavoriteProvider'));
    // 长列表可从外部传入收藏状态，避免每个可见行创建异步查询。
    expect(source, contains('this.isFavorite'));
    expect(source, contains('bool _pending = false'));
    expect(source, contains('if (_pending) return'));
    expect(source, contains('onPressed: _pending ? null : _toggle'));
  });

  test('shared bottom sheet does not request focus by default', () {
    final source = File('lib/core/widgets/koyze_sheet.dart').readAsStringSync();

    expect(source, contains('requestFocus: false'));
    expect(source, contains('useSafeArea: true'));
    expect(source, contains('koyzeSheetMaxHeight'));
    expect(source, contains('viewPadding.top'));
  });

  test('playlist detail rows pass the shared favorite id set', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('favoriteSongsProvider'));
    expect(source, contains('isFavorite:'));
    expect(source, contains('isFavorites'));
    expect(source, contains('isFavoriteMusic(song, favoriteSongs)'));
  });

  test('playlist detail uses a frosted top bar and floating pagination', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
    ).readAsStringSync();

    // 列表可滚动到栏内部（栏高度不变），磨砂才可见。
    expect(source, contains('extendBodyBehindAppBar: true'));
    // 顶栏磨砂玻璃（flexibleSpace），页码栏悬浮于列表上方。
    expect(source, contains('GradientAppBarBackground('));
    expect(source, contains('PageNavigationBar('));
    expect(source, isNot(contains('ShaderMask')));
  });

  test('title bars use stronger frosted glass instead of a bottom fade', () {
    final gradientSource = File(
      'lib/core/widgets/gradient_bar_backgrounds.dart',
    ).readAsStringSync();
    expect(gradientSource, contains('class GradientAppBarBackground'));
    expect(gradientSource, contains('class GradientBottomBarBackground'));
    // 底栏仍可渐变到透明；顶栏不再用底部渐变。
    expect(gradientSource, contains('this.minAlpha = 0.0'));

    final appBarClass = gradientSource.substring(
      gradientSource.indexOf('class GradientAppBarBackground'),
      gradientSource.indexOf('class GradientBottomBarBackground'),
    );
    expect(appBarClass, contains('GlassSurface('));
    expect(appBarClass, contains('style: AppGlassStyle.bar'));
    expect(appBarClass, isNot(contains('fadeStart')));

    for (final path in [
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
      'lib/features/playlist/presentation/duplicate_screen.dart',
      'lib/features/search/presentation/song_list_detail_screen.dart',
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('GradientAppBarBackground('), reason: path);
      // 列表可滚动到栏内部（extendBodyBehindAppBar），磨砂才可见。
      expect(source, contains('extendBodyBehindAppBar: true'), reason: path);
      expect(source, isNot(contains('fadeStart:')), reason: path);
    }
  });

  test('leaderboard tab header also frosts over its list', () {
    final source = File(
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
    ).readAsStringSync();
    expect(source, contains('FrostedTabHeader('));
    expect(source, contains("title: '榜单'"));
    expect(source, contains('FrostedTabHeader.extent(context)'));
    expect(source, contains('Positioned.fill('));
    expect(source, isNot(contains('fadeStart:')));
    expect(source, isNot(contains('body: SafeArea(')));
  });

  test('playlist detail rows embed favorite before overflow button', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
    ).readAsStringSync();

    // 非多选模式 trailing 区域：FavoriteButton 在 more_vert 之前。
    final trailing = source.substring(
      source.indexOf('trailing: isSelectionMode'),
    );
    expect(trailing, contains('FavoriteButton('));
    expect(trailing, contains('song: song'));
    expect(trailing, contains('Icons.more_vert'));
    expect(
      trailing.indexOf('FavoriteButton('),
      lessThan(trailing.indexOf('Icons.more_vert')),
    );
  });

  test('local playlist menu offers favorite-all and hides delete', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains("playlist.id == 'local'"));
    expect(source, contains('收藏所有'));
    expect(source, contains("playlist.id != 'local'"));
    expect(source, contains('addAllSongsToFavorites'));
  });

  test('favorite button drops leftover optimistic unfavorite on song change', () {
    final source = File(
      'lib/core/widgets/favorite_button.dart',
    ).readAsStringSync();
    expect(source, contains('didUpdateWidget'));
    expect(source, contains('isSameCatalogTrack(oldWidget.song)'));
    expect(source, contains('_optimisticFavorite = null'));
    expect(source, contains('_resolvedFavorite'));

    final player = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();
    expect(player, contains("ValueKey<String>('player-fav-\${music.identityKey}')"));
  });

  testWidgets(
    'unfavorite then skip does not keep later songs hollow',
    (tester) async {
      final first = MusicItem(
        id: 'song-a',
        name: 'Song A',
        singer: 'Artist',
        source: 'kw',
        platform: 'kw',
      );
      final second = MusicItem(
        id: 'song-b',
        name: 'Song B',
        singer: 'Artist',
        source: 'kw',
        platform: 'kw',
      );
      var song = first;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            toggleFavoriteProvider.overrideWithValue((_) async {}),
            playlistSongsPageProvider.overrideWith((ref, request) async {
              return PlaylistSongPage(total: 0, offset: 0, songs: const []);
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      FavoriteButton(song: song, isFavorite: true),
                      TextButton(
                        onPressed: () => setState(() => song = second),
                        child: const Text('skip'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await tester.tap(find.byType(FavoriteButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.text('skip'));
      await tester.pump();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    },
  );
}
