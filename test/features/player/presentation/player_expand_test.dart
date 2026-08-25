import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full player morphs from mini-bar rect with staggered fades', () {
    final full = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();

    // 矩形窗口变形：页面不被非等比压缩。
    expect(full, contains('Rect.lerp(miniRect, fullRect'));
    expect(full, contains('OverflowBox'));
    expect(full, contains('ClipRRect'));
    expect(full, contains('playerRouteProgress'));
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
    expect(player, contains('Duration(milliseconds: 620)'));
    expect(player, contains('AnimatedSwitcher'));
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
      expect(full, contains('Material('));
      expect(full, contains('color: AppColors.dialogBg(context)'));
      expect(
        full,
        contains(
          'borderRadius: const BorderRadius.vertical(top: Radius.circular(20))',
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
}
