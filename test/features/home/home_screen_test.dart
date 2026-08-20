import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home hosts search entry and random favorites shortcut', () {
    final source = File(
      'lib/features/home/presentation/home_screen.dart',
    ).readAsStringSync();

    expect(source, contains('showSearchSheet'));
    expect(source, contains('Enjoy Music'));
    expect(source, isNot(contains('免费的音乐查找助手')));
    expect(source, contains('随机播放收藏'));
    expect(source, contains('playPagedPlaylist'));
    expect(source, contains('setShuffleMode(true)'));
    expect(source, contains('LayoutBuilder'));
    // 自定义源与云端同步已从快捷网格移除；主题用调色板图标区分睡眠定时。
    expect(source, isNot(contains("route: '/custom-source'")));
    expect(source, isNot(contains("route: '/sync'")));
    expect(source, contains('Icons.palette_outlined'));
    expect(source, isNot(contains('Icons.dark_mode_outlined')));
  });

  test('search sheet has draggable handle and delays keyboard focus', () {
    final sheet = File('lib/core/widgets/search_sheet.dart').readAsStringSync();
    final search = File(
      'lib/features/search/presentation/search_screen.dart',
    ).readAsStringSync();

    expect(sheet, contains('autofocusDelay'));
    expect(sheet, contains('topInset'));
    expect(sheet, contains('useRootNavigator: true'));
    expect(sheet, contains('isDismissible: true'));
    expect(
      sheet,
      isNot(contains('margin: EdgeInsets.only(top: widget.topInset)')),
    );
    expect(sheet, contains('onVerticalDragUpdate'));
    expect(sheet, contains('onVerticalDragEnd'));
    expect(sheet, contains('Transform.translate'));
    expect(sheet, contains('_closeThreshold'));
    expect(search, contains('autofocusDelay'));
    expect(search, contains('Timer(delay'));
    // 弹窗可下拉关闭，无需返回按钮。
    expect(search, isNot(contains("Icons.arrow_back")));
    // 左右滑入动效。
    expect(search, contains('Offset(-40 * (1 - t), 0)'));
    expect(search, contains('Offset(40 * (1 - t), 0)'));
  });

  test('home does not duplicate leaderboard cards', () {
    final source = File(
      'lib/features/home/presentation/home_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('TabBar')));
    expect(source, isNot(contains('leaderboardCategoriesProvider')));
    expect(source, isNot(contains("route: '/leaderboard'")));
  });

  test('leaderboard screen renders one list across platforms', () {
    final source = File(
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
    ).readAsStringSync();

    expect(source, contains('class LeaderboardScreen'));
    expect(source, isNot(contains('TabBar')));
    expect(source, contains("Icons.play_arrow_rounded"));
    expect(source, contains('/leaderboard/detail'));
  });

  test('bottom navigation second tab is leaderboard', () {
    final source = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();

    expect(source, contains("Icons.leaderboard_outlined"));
    expect(source, contains("'榜单'"));
    expect(source, contains('BoxConstraints(minHeight: 48)'));
    expect(source, contains('(textScale - 1) * 20'));
  });

  test('leaderboard renders list with settings entry and one-tap play', () {
    final source = File(
      'lib/features/leaderboard/presentation/leaderboard_screen.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/leaderboard/presentation/leaderboard_settings_screen.dart',
    ).readAsStringSync();

    expect(source, contains('leaderboardSongsProvider(category.id).future'));
    expect(source, contains("context.push('/leaderboard-settings')"));
    expect(source, isNot(contains('ReorderableDelayedDragStartListener')));
    expect(settings, contains('FxSwitch'));
    expect(settings, contains('_CategoryVisibilityTile'));
    expect(settings, isNot(contains('Reorderable')));
    expect(settings, contains('hidePlatform'));
  });
}
