import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../router/app_router.dart';
import '../../settings/presentation/settings_provider.dart';
import 'main_scaffold.dart';

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
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    appRouter.routerDelegate.addListener(_onRoute);
    _listening = true;
    _path = _currentPath();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _path == path) return;
      setState(() => _path = path);
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
    final railWidth = side
        ? leadingInset + sideRailContentWidth(media.size.width)
        : 0.0;
    final contentWidth = (media.size.width - railWidth).clamp(
      0.0,
      media.size.width,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('side-rail'),
          width: railWidth,
          child: side
              ? _RailOverlay(
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
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          key: const ValueKey('side-content'),
          child: MediaQuery(
            data: side
                ? media.copyWith(
                    size: Size(contentWidth, media.size.height),
                    padding: media.padding.copyWith(left: 0),
                    viewPadding: media.viewPadding.copyWith(left: 0),
                  )
                : media,
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
