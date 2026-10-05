import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/player_route_progress.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../router/app_router.dart';
import '../../settings/presentation/settings_provider.dart';
import 'main_scaffold.dart';

/// Below this long-side / short-side ratio, the landscape player takes the
/// whole window and the side rail steps aside.
const double fullscreenPlayerSideRailAspectRatio = 2.5;

/// Longer side divided by the shorter side. Orientation does not matter.
double screenAspectRatio(Size size) {
  final width = size.width.abs();
  final height = size.height.abs();
  final shortSide = width < height ? width : height;
  if (shortSide == 0) return 1;
  final longSide = width > height ? width : height;
  return longSide / shortSide;
}

/// The fullscreen player covers the rail only on screens narrower than
/// [fullscreenPlayerSideRailAspectRatio]. Wider landscape windows keep it.
bool showIndependentSideRail({
  required bool side,
  required bool playerOpen,
  required double aspectRatio,
}) {
  return sideRailShownFraction(
        side: side,
        aspectRatio: aspectRatio,
        playerProgress: playerOpen &&
                aspectRatio < fullscreenPlayerSideRailAspectRatio
            ? 1
            : 0,
      ) >
      0;
}

/// How much of the side rail stays visible while the fullscreen player moves.
///
/// Narrow landscape follows [playerProgress] (1 = rail gone) so the rail
/// steps aside with the transition instead of popping. Wide windows keep it.
double sideRailShownFraction({
  required bool side,
  required double aspectRatio,
  required double playerProgress,
}) {
  if (!side) return 0;
  if (aspectRatio >= fullscreenPlayerSideRailAspectRatio) return 1;
  final progress = playerProgress.isFinite
      ? playerProgress.clamp(0.0, 1.0)
      : 0.0;
  return 1 - progress;
}

/// Keeps the side rail outside the app navigator.
///
/// Subpages, sheets, dialogs, and their transitions are all painted by that
/// navigator, so they stay in the right pane and cannot cover the rail.
class IndependentSideRail extends ConsumerStatefulWidget {
  const IndependentSideRail({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IndependentSideRail> createState() =>
      _IndependentSideRailState();
}

class _IndependentSideRailState extends ConsumerState<IndependentSideRail> {
  String _path = '/';
  bool _playerOpen = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    appRouter.routerDelegate.addListener(_onRoute);
    _listening = true;
    _path = _currentPath();
    _playerOpen = routerHasFullscreenPlayer();
  }

  @override
  void dispose() {
    if (_listening) appRouter.routerDelegate.removeListener(_onRoute);
    super.dispose();
  }

  String _currentPath() {
    return appRouter.routerDelegate.currentConfiguration.uri.path;
  }

  /// The router notifies while it is still building. Refreshing the rail in
  /// that moment marks an ancestor dirty and takes down the page.
  void _onRoute() {
    final path = _currentPath();
    final playerOpen = routerHasFullscreenPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_path == path && _playerOpen == playerOpen)) return;
      setState(() {
        _path = path;
        _playerOpen = playerOpen;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final brightness = Theme.of(context).brightness;
    ref.watch(themeModeProvider);
    final side = shouldUseSideNavigation(
      size: media.size,
      orientation: media.orientation,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
      forceLandscape: ref.watch(forceLandscapeProvider),
    );
    final leadingInset = media.padding.left > media.viewPadding.left
        ? media.padding.left
        : media.viewPadding.left;
    final topInset = media.padding.top > media.viewPadding.top
        ? media.padding.top
        : media.viewPadding.top;
    final bottomInset = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    final aspect = screenAspectRatio(media.size);
    final followsPlayer =
        side && aspect < fullscreenPlayerSideRailAspectRatio;
    if (!followsPlayer) {
      return _buildFrame(
        context,
        media: media,
        side: side,
        fraction: side ? 1 : 0,
        leadingInset: leadingInset,
        topInset: topInset,
        bottomInset: bottomInset,
        brightness: brightness,
      );
    }
    return ListenableBuilder(
      listenable: playerRouteProgress,
      builder: (context, _) {
        return _buildFrame(
          context,
          media: media,
          side: side,
          fraction: sideRailShownFraction(
            side: true,
            aspectRatio: aspect,
            playerProgress: playerRouteProgress.value,
          ),
          leadingInset: leadingInset,
          topInset: topInset,
          bottomInset: bottomInset,
          brightness: brightness,
        );
      },
    );
  }

  Widget _buildFrame(
    BuildContext context, {
    required MediaQueryData media,
    required bool side,
    required double fraction,
    required double leadingInset,
    required double topInset,
    required double bottomInset,
    required Brightness brightness,
  }) {
    final fullRail = side
        ? leadingInset + sideRailContentWidth(media.size.width)
        : 0.0;
    final rawRail = fullRail * fraction;
    final pixel = 1 / MediaQuery.devicePixelRatioOf(context);
    // 收到最后不到半像素时直接落位，避免亚像素来回取整把界面抖一下。
    final railWidth = rawRail <= pixel
        ? 0.0
        : (fullRail - rawRail) <= pixel
        ? fullRail
        : rawRail;
    final showRail = railWidth > 0;
    final contentWidth = (media.size.width - railWidth).clamp(
      0.0,
      media.size.width,
    );
    // 栏在时左安全区算在栏里；栏让开后安全区要交还给内容。
    // 两边按同一进度过渡，结束时不会突然多出一条刘海内边距。
    final paddingLeft = side
        ? media.padding.left * (1 - fraction)
        : media.padding.left;
    final viewPaddingLeft = side
        ? media.viewPadding.left * (1 - fraction)
        : media.viewPadding.left;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('side-rail'),
          width: railWidth,
          // 宽度跟着播放器进度收，但栏内容保持原宽并往左滑出，避免文字被挤扁。
          child: showRail
              ? ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: fullRail,
                    maxWidth: fullRail,
                    child: Transform.translate(
                      offset: Offset(-fullRail * (1 - fraction), 0),
                      child: _RailOverlay(
                  key: ValueKey(brightness),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.scaffold(context),
                      border: Border(
                        right: BorderSide(color: AppColors.cardBorder(context)),
                      ),
                    ),
                    // Outside the navigator there is no Material, so text would
                    // inherit MaterialApp's yellow double-underline fallback.
                    child: Material(
                      type: MaterialType.transparency,
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: leadingInset,
                          top: topInset,
                          bottom: bottomInset,
                        ),
                        child: ListenableBuilder(
                          listenable: rootBranchIndex,
                          builder: (context, _) {
                            return RootSideNav(
                              selectedIndex: rootBranchIndex.value,
                              headers: rootHeaderController,
                              currentPath: _path,
                              onTap: selectRootBranch,
                              onOpenSync: () => appRouter.push('/sync'),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          key: const ValueKey('side-content'),
          child: MediaQuery(
            data: media.copyWith(
              size: Size(contentWidth, media.size.height),
              padding: media.padding.copyWith(left: paddingLeft),
              viewPadding: media.viewPadding.copyWith(left: viewPaddingLeft),
            ),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// Gives the rail its own overlay so tooltips work without joining the
/// page navigator.
class _RailOverlay extends StatefulWidget {
  const _RailOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<_RailOverlay> createState() => _RailOverlayState();
}

class _RailOverlayState extends State<_RailOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (context) => widget.child,
  );

  @override
  void didUpdateWidget(covariant _RailOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
