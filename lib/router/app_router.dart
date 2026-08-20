import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/logging/app_log.dart';
import '../core/card_expand.dart';
import '../core/player_route_progress.dart';
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

/// 处理小组件 / 深链打开播放器的请求。
/// 支持 `koyze://nowplaying` 等意图，统一路由到全屏播放器。
void routeWidgetLaunch(Uri? uri) {
  if (uri == null) return;
  final host = uri.host.toLowerCase();
  if (host == 'nowplaying') {
    appRouter.push('/player');
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
      // opaque:false 让下拉关闭时透出打开前的界面
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 360),
        child: const EdgeSwipeDismiss(child: PlayerScreen()),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // 全屏播放器内部自带"从迷你栏生长"的矩形变形（读取 playerRouteProgress），
          // 这里只同步进度并保持不透明，不再叠加页面级动画。
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return _PlayerRouteProgressBridge(animation: curved, child: child);
        },
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
    playerRouteProgress.value = widget.animation.value;
  }

  @override
  void dispose() {
    widget.animation.removeListener(_sync);
    playerRouteProgress.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
