import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  });

  test('playlist detail rows pass the shared favorite id set', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_detail_screen.dart',
    ).readAsStringSync();

    expect(source, contains('favoriteIdsProvider'));
    expect(source, contains('isFavorite:'));
    expect(source, contains('isFavorites ||'));
    expect(source, contains('favoriteIds.contains(song.identityKey)'));
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
    expect(appBarClass, contains('BackdropFilter'));
    expect(appBarClass, contains('ImageFilter.blur'));
    expect(appBarClass, contains('sigmaX: 36'));
    expect(appBarClass, contains('sigmaY: 36'));
    expect(appBarClass, isNot(contains('LinearGradient')));
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
    // 榜单 tab 标题栏悬浮且磨砂，列表可滚动到栏内部。
    expect(source, contains('GradientAppBarBackground('));
    expect(source, contains('child: _buildHeader(context)'));
    expect(source, contains('Positioned.fill('));
    expect(
      source,
      contains('padding: const EdgeInsets.fromLTRB(12, 72, 12, 16)'),
    );
    expect(source, isNot(contains('fadeStart:')));
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
}
