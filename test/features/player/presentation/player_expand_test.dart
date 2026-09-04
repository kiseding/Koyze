import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full player morphs from mini-bar rect with staggered fades', () {
    final full = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();

    // 对称收起（卡片式）：矩形从全屏线性收向目标——封面页→迷你栏、
    // 歌词页→迷你栏歌词行同款长条；内容中心锚定 + 按宽度比缩放，
    // 上下对称裁剪（焦点=矩形中心）。
    expect(full, contains('final collapseTarget = lyricCollapsing'));
    expect(full, contains('final currentRect = Rect.lerp(collapseTarget'));
    expect(full, contains('final artworkMorphRect = Rect.lerp'));
    expect(full, contains('_miniArtworkRect(miniRect)'));
    expect(full, contains('_fullArtworkRect('));
    expect(full, contains('_RouteArtworkMorphOverlay'));
    expect(full, contains('_RoutePlayButtonMorphOverlay'));
    expect(full, contains('final playButtonTarget = _currentPage == 1'));
    expect(
      full,
      contains('final btnMorphT = (progress / 0.35).clamp(0.0, 1.0)'),
    );
    expect(full, contains('miniPlayButtonRect,\n          1 - btnMorphT'));
    expect(full, contains('Rect.lerp('));
    expect(full, contains('_miniPlayButtonRect(miniRect)'));
    expect(full, contains('_fullControlsPlayButtonRect('));
    expect(full, contains('_fullLyricPlayButtonRect('));
    expect(full, contains('_currentPage == 1'));
    expect(full, contains('fullLyricPlayButtonRect'));
    expect(full, contains('fullControlsPlayButtonRect'));
    expect(full, isNot(contains('final shellOpacity =')));
    expect(full, isNot(contains('scaffoldBackgroundColor.withAlpha')));
    expect(full, isNot(contains('(255 * shellOpacity).round()')));
    expect(full, contains('if (!hideLayer && (progress > 0 || closing))'));
    // 歌词页关闭：整页对称收成迷你栏歌词行同款长条
    // （_miniLyricRowRect），0~90% 原样、90~99% 渐变成迷你栏同款灰、
    // 99% 后砍掉由真实迷你栏接管。
    expect(full, contains('_miniLyricRowRect(miniRect)'));
    expect(full, contains('final collapseTarget = lyricCollapsing'));
    expect(full, contains('((closeT - 0.9) / 0.09).clamp(0.0, 1.0)'));
    expect(full, contains('AppColors.miniBar(context)'));
    expect(full, contains('closeT >= 0.99'));
    expect(full, contains('else if (!lyricCollapsing)'));
    expect(full, contains('Theme.of(context).scaffoldBackgroundColor'));
    expect(full, contains('color: Colors.transparent'));
    expect(full, contains('if (_currentPage == 0)'));
    expect(full, contains('artworkReveal'));
    expect(full, contains('progress >= 1.0 ? 1.0 : 0.0'));
    expect(
      full,
      isNot(contains('((progress - 0.74) / 0.22).clamp(0.0, 1.0)')),
    );
    expect(full, contains('OverflowBox'));
    expect(full, contains('ClipRRect'));
    expect(full, contains('playerRouteProgress'));
    expect(full, contains('MotionCurve.iosSpring'));
    expect(full, contains('MotionDuration.playerReverse'));
    // 内容必须在 morph 底还很小时就完全不透明，否则整屏会长时间
    // 呈"半透明全屏白色层"（内容鬼影盖在白色 sheet 上，进入/退出各闪一次）；
    // 之后各区块的显隐节奏交给 _StaggeredFade；封面全程隐藏、只留快照。
    expect(full, contains('((progress - 0.03) / 0.17).clamp(0.0, 1.0)'));
    // morph 覆盖层必须把 Positioned 直接挂在 Stack 下（IgnorePointer 在内侧），
    // 否则 Debug 模式抛 ParentData 断言、Release 下覆盖层错位。
    expect(
      full,
      contains(
        'return Positioned.fromRect(\n      rect: rect,\n      child: IgnorePointer(',
      ),
    );
    expect(
      full,
      isNot(
        contains('return IgnorePointer(\n      child: Positioned.fromRect'),
      ),
    );
    // morph 覆盖层终点必须取真实布局几何（GlobalKey 实测），否则
    // 展开/收起终点与页面封面/按钮错位 -> "卡一下再向上跳"。
    expect(full, contains('_recordMorphTargets()'));
    expect(full, contains('final GlobalKey _artworkKey = GlobalKey();'));
    expect(full, contains('key: _artworkKey'));
    expect(full, contains('key: _controlsPlayKey'));
    expect(full, contains('key: _lyricPlayKey'));
    expect(full, contains('??\n            _fullArtworkRect('));
    // 拖拽关闭必须从当前位置继续收拢（回弹/收拢都走同一跟手动画），
    // 不能先放大回去再关，也不能让 Navigator 反向动画回写进度；
    // 用确定性 controller 从当前位置 settle，避免弹簧 overshoot / cancel
    // 后视觉停在半路（松手后没有动效/卡住）。
    expect(full, contains('_settleRouteProgress('));
    expect(full, contains('onComplete: _completeDragDismiss'));
    expect(full, contains('_settleController'));
    expect(full, contains('.forward(from: 0)'));
    expect(full, contains('.orCancel'));
    expect(full, contains('playerRouteDismissLocked = true;'));
    expect(
      full,
      contains('final v = (1 - _dragOffset / _dragDistance).clamp(0.0, 1.0)'),
    );
    expect(
      full,
      isNot(contains('Matrix4.translationValues(0, _dragOffset, 0)')),
    );
    expect(full, isNot(contains('0.28 * (1 - revealT)')));
    // 歌词页关闭的播放按钮 morph 必须按启用视觉渲染（绿色），
    // 否则关闭瞬间按钮从绿变灰再变绿。
    expect(full, contains('onPressed: () {},'));
    expect(full, contains('enabled: true,'));
    // 各区块独立节奏（stagger）。
    expect(full, contains('_StaggeredFade'));
    expect(full, contains('delay: 0.2')); // 歌名
    expect(full, contains('delay: 0.3')); // 歌词
    expect(full, contains('delay: 0.45')); // 进度
    expect(full, contains('delay: 0.5')); // 控制按钮
    expect(full, contains('delay: 0.55')); // AppBar
    // 不再使用 Hero 飞行（由整体变形取代）。
    expect(full, isNot(contains('tag: \'player-')));
  });

  test('mini player no longer wraps elements in heroes', () {
    final mini = File(
      'lib/features/player/presentation/widgets/mini_player.dart',
    ).readAsStringSync();

    expect(mini, isNot(contains('Hero(')));
    expect(mini, isNot(contains('tag: \'player-')));
    expect(mini, contains('playerRouteProgress'));
    expect(mini, contains('progress > 0 && progress < 1'));
  });

  test('player route drives shell squeeze and no page-level transforms', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();
    final scaffold = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();

    // 页面级动画全部交给 PlayerScreen 内部矩形变形。
    expect(router, contains('playerRouteProgress'));
    expect(router, isNot(contains('ScaleTransition')));
    expect(router, isNot(contains('FadeTransition')));
    final player = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();
    expect(player, contains('kFullPlayerTrackSwitchDuration'));
    expect(player, contains('Duration(milliseconds: 880)'));
    expect(player, contains('Duration(milliseconds: 860)'));
    expect(player, contains('MotionDuration.playerReverse'));
    expect(player, contains('_FullPlayerArtworkSwitcher'));
    expect(player, contains('precacheImage'));
    expect(player, contains('kFullPlayerArtworkSwitchDuration'));
    expect(player, contains('ColoredBox'));
    expect(player, isNot(contains('begin: const Offset(0.08, 0)')));
    expect(player, contains('alignment: Alignment.centerLeft'));
    expect(player, contains('width: double.infinity'));
    expect(
      player,
      contains('final bottomSpacing = bottomInset == 0 ? 2.0 : 0.0'),
    );
    expect(
      player,
      contains('final bottomClearance = bottomInset == 0 ? 11.0 : 0.0'),
    );
    // 主壳联动：底栏挤出、Tab 上移、迷你栏扩张。
    expect(scaffold, contains('playerRouteProgress'));
    expect(scaffold, contains('navPush'));
    expect(scaffold, contains('tabPush'));
  });

  test('full-screen lyric highlights use the green theme accent', () {
    final lyric = File(
      'lib/features/lyric/presentation/lyric_view.dart',
    ).readAsStringSync();

    expect(lyric, contains('activeColor: accent'));
  });

  test(
    'playback queue uses draggable sheet so sheet drag tracks the finger',
    () {
      final full = File(
        'lib/features/player/presentation/player_screen.dart',
      ).readAsStringSync();

      expect(full, contains('showKoyzeSheet'));
      expect(full, contains('DraggableScrollableSheet'));
      expect(full, contains('dragScrollController: scrollController'));
      expect(full, contains('controller: _queueScrollController'));
      expect(full, contains('initialChildSize: sheetSize'));
      expect(full, contains('maxChildSize: sheetSize'));
      expect(full, contains('snap: true'));
      expect(full, contains('const extraHeight = 50.0'));
      expect(full, contains('const maxSheetSize = 0.78'));
      expect(full, isNot(contains('snapSizes:')));
      expect(full, isNot(contains('_handleQueueScrollNotification')));
      expect(full, contains('backgroundColor: Colors.transparent'));
      expect(full, contains('GlassSurface('));
      expect(full, contains('Material('));
      expect(full, contains('color: Colors.transparent'));
      expect(
        full,
        contains(
          'borderRadius: const BorderRadius.vertical(',
        ),
      );
      expect(full, contains('final pageContext = context'));
      expect(full, contains('showPlaylistPicker(context: pageContext'));
    },
  );

  test('search sheet closes via default bottom-sheet animation', () {
    final sheet = File('lib/core/widgets/search_sheet.dart').readAsStringSync();

    expect(sheet, contains('Navigator.pop(context)'));
    expect(sheet, isNot(contains('_closing')));
  });

  test('player route disables route snapshotting to avoid white flash', () {
    final router = File('lib/router/app_router.dart').readAsStringSync();

    expect(router, contains('class _PlayerTransitionPage extends Page<void>'));
    expect(
      router,
      contains('class _PlayerTransitionRoute extends PageRoute<void>'),
    );
    expect(router, contains('bool get allowSnapshotting => false'));
    expect(router, contains('bool get opaque => false'));
    expect(router, contains('barrierColor => Colors.transparent'));
    expect(
      router,
      contains('pageBuilder: (context, state) => _PlayerTransitionPage'),
    );
    expect(router, isNot(contains('CustomTransitionPage<void>')));
  });
  test(
    'main scaffold keeps underlying chrome visible during early player morph',
    () {
      final source = File(
        'lib/features/home/presentation/main_scaffold.dart',
      ).readAsStringSync();

      expect(source, contains('visibleProgress'));
      expect(source, contains('final descending = progress < _prevProgress'));
      expect(source, contains('descending || progress <= 0.92'));
      expect(source, contains('final chromeOpacity'));
      expect(source, contains('1 - visibleProgress'));
    },
  );
}
