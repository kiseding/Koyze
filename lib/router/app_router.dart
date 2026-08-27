import 'package:flutter/material.dart';
import 'dart:async';

import 'package:go_router/go_router.dart';
import '../core/logging/app_log.dart';
import '../core/card_expand.dart';
import '../core/player_route_progress.dart';
import '../core/motion/motion_tokens.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/home/presentation/main_scaffold.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/playlist/presentation/playlist_screen.dart';
import '../features/playlist/presentation/playlist_detail_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/download/presentation/download_screen.dart';
import '../features/custom_source/presentation/custom_source_screen.dart';
import '../features/leaderboard/presentation/leaderboard_screen.dart';
import '../features/leaderboard/presentation/leaderboard_settings_screen.dart';
import '../features/sync/presentation/sync_screen.dart';
import '../features/stats/presentation/stats_screen.dart';
import '../features/playlist/presentation/duplicate_screen.dart';
import '../features/recommend/presentation/recommendation_screen.dart';
import '../features/local_music/presentation/local_music_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<SwipeBranchContainerState> _swipeBranchKey =
    GlobalKey<SwipeBranchContainerState>();

bool _playerRoutePushInFlight = false;
Timer? _playerRoutePushTimeout;

/// 左缘右滑收拢成型后锁定播放器路由反向动画：pop 后进度保持、
/// 迷你栏无缝接管，避免先弹回全屏再播放关闭动效。
void _lockPlayerRouteDismiss() {
  playerRouteDismissLocked = true;
}

bool _isCurrentRoute(String path) =>
    appRouter.routerDelegate.currentConfiguration.uri.path == path;

Future<void> pushPlayerRoute(
  BuildContext context, {
  required bool hasSong,
}) async {
  if (!hasSong || _isCurrentRoute('/player') || _playerRoutePushInFlight) {
    return;
  }
  _playerRoutePushInFlight = true;
  _playerRoutePushTimeout?.cancel();
  _playerRoutePushTimeout = Timer(const Duration(seconds: 2), () {
    _playerRoutePushInFlight = false;
  });
  try {
    await context.push('/player');
  } finally {
    _playerRoutePushTimeout?.cancel();
    _playerRoutePushTimeout = null;
    _playerRoutePushInFlight = false;
  }
}

/// 处理小组件 / 深链打开播放器的请求。
/// 支持 `koyze://nowplaying` 等意图，统一路由到全屏播放器。
void routeWidgetLaunch(Uri? uri) {
  if (uri == null) return;
  final host = uri.host.toLowerCase();
  if (host == 'nowplaying' &&
      !_isCurrentRoute('/player') &&
      !_playerRoutePushInFlight) {
    _playerRoutePushInFlight = true;
    _playerRoutePushTimeout?.cancel();
    _playerRoutePushTimeout = Timer(const Duration(seconds: 2), () {
      _playerRoutePushInFlight = false;
    });
    appRouter.push('/player').whenComplete(() {
      _playerRoutePushTimeout?.cancel();
      _playerRoutePushTimeout = null;
      _playerRoutePushInFlight = false;
    });
  }
}

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  observers: [appLogNavigationObserver],
  routes: [
    StatefulShellRoute(
      builder: (context, state, navigationShell) {
        return MainScaffold(
          navigationShell: navigationShell,
          onBranchTap: (index) {
            final state = _swipeBranchKey.currentState;
            if (state != null) {
              state.select(index);
            } else {
              AppLog.instance.record('navigation', 'select branch=$index');
              navigationShell.goBranch(index);
            }
          },
        );
      },
      navigatorContainerBuilder: (context, navigationShell, children) {
        return SwipeBranchContainer(
          key: _swipeBranchKey,
          currentIndex: navigationShell.currentIndex,
          onSelect: (index) {
            AppLog.instance.record('navigation', 'select branch=$index');
            navigationShell.goBranch(index);
          },
          children: children,
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/leaderboard',
              builder: (context, state) => const LeaderboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/playlist',
              builder: (context, state) => const PlaylistScreen(),
              routes: [
                GoRoute(
                  name: 'playlistDetail',
                  path: 'detail/:playlistId',
                  parentNavigatorKey: rootNavigatorKey,
                  pageBuilder: (context, state) => expandablePage(
                    state.pageKey,
                    PlaylistDetailScreen(
                      playlistId: state.pathParameters['playlistId']!,
                      focusSongId: state.uri.queryParameters['focusSongId'],
                    ),
                    expandRect: consumeCardExpandRect(),
                    expandSnapshot: consumeCardExpandSnapshot(),
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const SearchScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/player',
      parentNavigatorKey: rootNavigatorKey,
      // 透明但不使用系统 route snapshot，避免打开/关闭时快照层闪成半透明浅色幕。
      pageBuilder: (context, state) => _PlayerTransitionPage(
        key: state.pageKey,
        child: EdgeSwipeDismiss(
          // 左缘右滑直接驱动播放器 morph 进度，全屏界面整体跟手收拢。
          progress: playerRouteProgress,
          onDismissCommit: _lockPlayerRouteDismiss,
          child: const PlayerScreen(),
        ),
      ),
    ),
    GoRoute(
      path: '/local-music',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const LocalMusicScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/download',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const DownloadScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/custom-source',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const CustomSourceScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/leaderboard-settings',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const LeaderboardSettingsScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/leaderboard/detail',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        LeaderboardDetailScreenById(
          id: state.uri.queryParameters['id'] ?? '',
          name: state.uri.queryParameters['name'] ?? '',
        ),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/sync',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const SyncScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/stats',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const StatsScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/duplicates',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const DuplicateScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
    GoRoute(
      path: '/recommend',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => expandablePage(
        state.pageKey,
        const RecommendationScreen(),
        expandRect: consumeCardExpandRect(),
        expandSnapshot: consumeCardExpandSnapshot(),
      ),
    ),
  ],
);

/// 全屏播放器专用透明路由。Flutter 的默认 route snapshotting 在透明路由 +
/// 深/浅色主题快速切换首尾帧时可能短暂合成一层浅色快照，表现成全屏半透明白闪。
/// 播放器本身已有基于 [playerRouteProgress] 的元素 morph，所以这里强制实时绘制。
class _PlayerTransitionPage extends Page<void> {
  const _PlayerTransitionPage({required this.child, super.key});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) =>
      _PlayerTransitionRoute(page: this);
}

class _PlayerTransitionRoute extends PageRoute<void> {
  _PlayerTransitionRoute({required _PlayerTransitionPage page})
    : super(settings: page);

  _PlayerTransitionPage get _page => settings as _PlayerTransitionPage;

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
  bool get fullscreenDialog => false;

  @override
  bool get allowSnapshotting => false;

  @override
  Duration get transitionDuration => MotionDuration.player;

  @override
  Duration get reverseTransitionDuration => MotionDuration.playerReverse;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: _page.child,
    );
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
      curve: MotionCurve.iosSpring,
      reverseCurve: MotionCurve.easeInOut,
    );
    return _PlayerRouteProgressBridge(animation: curved, child: child);
  }
}

/// 把全屏播放器路由过渡进度同步给主壳（底栏挤出 / Tab 上移 / 迷你栏扩张）。
class _PlayerRouteProgressBridge extends StatefulWidget {
  const _PlayerRouteProgressBridge({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  State<_PlayerRouteProgressBridge> createState() =>
      _PlayerRouteProgressBridgeState();
}

class _PlayerRouteProgressBridgeState
    extends State<_PlayerRouteProgressBridge> {
  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant _PlayerRouteProgressBridge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_sync);
      widget.animation.addListener(_sync);
    }
  }

  void _sync() {
    if (playerRouteDismissLocked) return;
    playerRouteProgress.value = widget.animation.value;
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    playerRouteDismissLocked = false;
    playerRouteProgress.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
