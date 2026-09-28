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
class IndependentSideRail extends ConsumerWidget {
  const IndependentSideRail({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = MediaQuery.of(context);
    final side = shouldUseSideNavigation(
      size: media.size,
      orientation: media.orientation,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
      forceLandscape: ref.watch(forceLandscapeProvider),
    );
    if (!side) return child;

    final leadingInset = media.padding.left > media.viewPadding.left
        ? media.padding.left
        : media.viewPadding.left;
    final topInset = media.padding.top > media.viewPadding.top
        ? media.padding.top
        : media.viewPadding.top;
    final bottomInset = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    final railWidth = leadingInset + sideRailContentWidth(media.size.width);
    final contentWidth = (media.size.width - railWidth).clamp(
      0.0,
      media.size.width,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: railWidth,
          child: _RailOverlay(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.fill(context),
                border: Border(
                  right: BorderSide(color: AppColors.cardBorder(context)),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: leadingInset,
                  top: topInset,
                  bottom: bottomInset,
                ),
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    appRouter.routerDelegate,
                    rootBranchIndex,
                  ]),
                  builder: (context, _) {
                    return RootSideNav(
                      selectedIndex: rootBranchIndex.value,
                      headers: rootHeaderController,
                      routeListenable: appRouter.routerDelegate,
                      currentPath: appRouter
                          .routerDelegate
                          .currentConfiguration
                          .uri
                          .path,
                      onTap: selectRootBranch,
                      onOpenSync: () => appRouter.push('/sync'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery(
            data: media.copyWith(
              size: Size(contentWidth, media.size.height),
              padding: media.padding.copyWith(left: 0),
              viewPadding: media.viewPadding.copyWith(left: 0),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Gives the rail its own overlay so tooltips work without joining the
/// page navigator.
class _RailOverlay extends StatefulWidget {
  const _RailOverlay({required this.child});

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
