import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home hosts search entry and random favorites shortcut', () {
    final source = File(
      'lib/features/home/presentation/home_screen.dart',
    ).readAsStringSync();
    final quick = File(
      'lib/features/home/presentation/home_quick_provider.dart',
    ).readAsStringSync();

    final hero = File(
      'lib/features/home/presentation/home_hero_card.dart',
    ).readAsStringSync();

    expect(source, contains('showSearchSheet'));
    expect(source, contains("title: 'Koyze'"));
    // 顶栏由根壳层统一渲染，首页只发布品牌标题和动作。
    expect(source, contains('RootHeaderPublisher('));
    expect(source, isNot(contains('FrostedTabHeader(')));
    expect(source, isNot(contains('免费的音乐查找助手')));
    expect(source, contains('HomeHeroCard'));
    expect(source, contains('HomeHeroCardSettings'));
    expect(source, contains('_showHeroCardSettings'));
    expect(source, contains('_showQuickSettings'));
    expect(source, contains('_QuickEditPenPainter'));
    expect(hero, contains('homeHeroCardProvider'));
    expect(hero, contains('homeHeroPlayModeProvider'));
    expect(hero, contains('playPagedPlaylist'));
    expect(hero, contains('captureExpandRect: true'));
    expect(hero, contains('_applyPlayMode'));
    expect(hero, contains("'收藏列表'"));
    expect(hero, contains("'猜你喜欢'"));
    expect(hero, contains("'本地音乐'"));
    expect(hero, contains("'NAS 乐库'"));
    expect(hero, contains("'最近播放'"));
    final strings = File('lib/l10n/app_strings.dart').readAsStringSync();
    expect(strings, contains('只能启用其中一张'));
    expect(strings, contains('右侧按钮播放模式'));
    expect(hero, contains('titleFor(S.of(context))'));
    expect(hero, contains('setShuffleMode'));
    expect(hero, contains('setRepeatMode'));
    expect(hero, contains('AudioServiceRepeatMode.one'));
    expect(hero, contains('home_hero_play_mode_v1'));
    expect(source, contains('LayoutBuilder'));
    // 自定义源与云端同步已从快捷网格移除；主题用调色板图标区分睡眠定时。
    expect(source, isNot(contains("route: '/custom-source'")));
    expect(source, isNot(contains("route: '/sync'")));
    expect(quick, contains('Icons.palette_outlined'));
    expect(source, contains('homeQuickSettingsProvider'));
    expect(source, contains('semanticLabel: S.of(context).heroCardSettingsAction'));
    expect(source, contains('semanticLabel: S.of(context).shortcutSettings'));
    expect(strings, contains('设置首页大卡片'));
    expect(strings, contains('快捷功能设置'));
    expect(source, contains('ReorderableListView.builder'));
    expect(quick, contains('home_quick_features_v1'));
    expect(source, isNot(contains('Icons.dark_mode_outlined')));
    expect(quick, contains("id: 'subsonic'"));
    expect(quick, contains("title: 'NAS 乐库'"));
    expect(quick, contains("route: '/subsonic'"));
  });

  test('playlist labels custom playlists below recent card', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();

    expect(source, contains('_BodyHeader(title: S.of(context).customPlaylists'));
  });

  test('search sheet follows the Origo search surface and delays keyboard focus', () {
    final sheet = File('lib/core/widgets/search_sheet.dart').readAsStringSync();
    final search = File(
      'lib/features/search/presentation/search_screen.dart',
    ).readAsStringSync();
    final controls = File(
      'lib/features/search/presentation/search_controls.dart',
    ).readAsStringSync();

    expect(sheet, contains('autofocusDelay'));
    expect(sheet, contains('topInset'));
    expect(sheet, contains('rootNavigator: true'));
    expect(sheet, contains('barrierDismissible'));
    expect(
      sheet,
      isNot(contains('margin: EdgeInsets.only(top: widget.topInset)')),
    );
    // 拖拽、回弹和退场都由自绘路由的同一进度驱动，不再叠系统弹层手势。
    expect(sheet, contains('class _SearchSheetRoute extends PopupRoute'));
    expect(sheet, contains('onVerticalDragUpdate'));
    expect(sheet, contains('_endDrag'));
    expect(sheet, contains('Transform.translate'));
    expect(sheet, contains('_settleBack'));
    expect(sheet, isNot(contains('showModalBottomSheet')));
    expect(search, contains('autofocusDelay'));
    expect(search, contains('Timer(delay'));
    // 面板靠下滑关闭，输入行左侧不再挂返回箭头；清空交给右侧胶囊。
    expect(controls, isNot(contains('Icons.arrow_back_rounded')));
    expect(search, contains('onCancel: clear'));
    expect(sheet, contains('liveSearch: true'));
    expect(search, contains('Timer(const Duration(milliseconds: 250)'));
    // 控件整体做轻微上浮淡入，不再左右对冲。
    expect(search, contains('Offset(0, 6 * (1 - t))'));
    // 输入行与平台胶囊各自成组件，弹窗里固定上下堆叠，独立页横屏才并排。
    expect(controls, contains('class SearchFieldBar'));
    expect(controls, contains('class SearchSourceChips'));
    expect(controls, contains('onCancel'));
    expect(controls, contains('onChanged'));
    expect(search, contains('final wide = size.width > size.height * 1.15;'));
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
    expect(source, contains('Icons.play_arrow_rounded'));
    expect(source, contains('/leaderboard/detail'));
  });

  test('top segmented control second slot is leaderboard', () {
    final source = File(
      'lib/core/widgets/root_tab_bar.dart',
    ).readAsStringSync();

    expect(source, contains('s.charts'));
    expect(
      File('lib/l10n/app_strings.dart').readAsStringSync(),
      contains("en ? 'Charts' : '榜单'"),
    );
    // 选中态是向右展开的图标胶囊：实心图标切换 + 末尾过冲的弹性曲线。
    expect(source, contains('AnimatedSwitcher'));
    expect(source, contains('MotionCurve.emphasize'));
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

  test('tab container snaps when the route index changes mid-swipe', () {
    final source = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();
    expect(source, contains('_anim.stop()'));
    expect(source, contains('oldWidget.currentIndex != widget.currentIndex'));
    expect(source, isNot(contains('!_animating &&\n        !_dragging')));
  });

  test('快捷卡的留白由卡片高度与图标推出来，四边同一个数', () {
    final source = File(
      'lib/features/home/presentation/home_screen.dart',
    ).readAsStringSync();
    final card = source.substring(
      source.indexOf('class _QuickEntryCard'),
      source.indexOf('class _QuickEditPenPainter'),
    );

    // 图标在卡内垂直居中，上下留白 = (高 - 图标) / 2；四边沿用同一个值，
    // 否则图标看起来是"贴左"而不是"居中于卡"。
    expect(card, contains('final height = tileHeight ?? (dense ? 52.0 : 68.0);'));
    expect(card, contains('final iconExtent = dense ? 40.0 : 52.0;'));
    expect(card, contains('final inset = (height - iconExtent) / 2;'));
    expect(card, contains('padding: EdgeInsets.all(inset)'));
    expect(card, isNot(contains('EdgeInsets.fromLTRB(11,')));

    // 卡高 68 上图标取 52，内容区正好等于图标，留白落到 8——原先图标 34、
    // 四边各 17，看着像一排空盒子。留白再涨回去就等于把这条又改回去了。
    expect((68.0 - 52.0) / 2, 8.0);
  });
}
