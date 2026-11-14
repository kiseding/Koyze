import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/player_route_progress.dart';

/// 打开全屏播放器时，主壳不允许被"提前宣布已经全屏"。
///
/// HeroController 每次 push 都会把目标路由临时 offstage 一帧去量 Hero 位置，
/// 这期间 `ModalRoute` 的动画代理被换成 `kAlwaysCompleteAnimation`
/// （value 恒为 1.0）。如果进度桥把这一帧的 1.0 当真写进
/// [playerRouteProgress]，主壳就会按"播放器已全屏"把 chrome 淡到全透明，
/// 而播放器这一帧本身是 offstage 不画的——整屏只剩一层底色，肉眼就是
/// 打开播放器前闪一下黑（实测录屏里恰好一帧，约 16ms）。
void main() {
  tearDown(() {
    playerRouteProgress.value = 0;
    playerRouteDismissLocked = false;
  });

  const background = Color(0xFF111318);
  const shell = Color(0xFFB8D4FF);

  testWidgets('推送播放器路由时主壳不会先闪一帧全透明', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 主壳每帧实际拿去画 chrome 的进度值。复刻 MainScaffold 的取用方式：
    // 只有 progress > 0.92 才开始把 chrome 淡出。
    final shellSaw = <double>[];
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF111111),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: background,
        ),
        home: Scaffold(
          backgroundColor: background,
          body: ValueListenableBuilder<double>(
            valueListenable: playerRouteProgress,
            builder: (context, progress, _) {
              shellSaw.add(progress);
              final visible = progress <= 0.92
                  ? 0.0
                  : ((progress - 0.92) / 0.08).clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - visible,
                child: const ColoredBox(color: shell),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    unawaited(navigatorKey.currentState!.push(_PlayerLikeRoute()));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }

    expect(
      tester.takeException(),
      isNull,
      reason: '构建期回写进度不能让监听者在本帧被标脏',
    );
    expect(shellSaw.first, 0.0, reason: '推送首帧主壳必须还停在"未打开"');
    for (var i = 1; i < shellSaw.length; i++) {
      expect(
        shellSaw[i],
        greaterThanOrEqualTo(shellSaw[i - 1]),
        reason:
            '进度必须单调上升；中途回退说明主壳先被推到"已全屏"再被拉回 '
            '(第 $i 帧 ${shellSaw[i]} < ${shellSaw[i - 1]})',
      );
    }
    expect(
      shellSaw.where((v) => v >= 1.0),
      isNotEmpty,
      reason: '路由动画结束后进度必须回到 1',
    );
  });
}

/// 复刻 app_router 里的播放器路由：透明、不 snapshot、220ms。
/// 正文换成纯色块——这一帧的问题出在进度回写与主壳联动，与播放器内容无关。
class _PlayerLikeRoute extends PageRoute<void> {
  _PlayerLikeRoute() : super(settings: const RouteSettings(name: '/player'));

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get allowSnapshotting => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return const ColoredBox(color: Color(0xFF20242A));
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return PlayerRouteProgressBridge(animation: curved, child: child);
  }
}
