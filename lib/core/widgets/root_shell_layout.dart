import 'dart:math';

import 'package:flutter/widgets.dart';

bool shouldUseSideNavigation({
  required Size size,
  required Orientation orientation,
  required TargetPlatform platform,
  required bool isWeb,
  bool forceLandscape = false,
}) {
  if (forceLandscape) return true;
  final isDesktop =
      !isWeb &&
      {
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(platform);
  return isDesktop || orientation == Orientation.landscape;
}

/// Side-rail content width for the current window.
///
/// It grows with the screen instead of staying on one constant, and it keeps
/// enough room for the label and the trailing action button to stay apart.
double sideRailContentWidth(double screenWidth) {
  return (screenWidth * 0.22).clamp(180.0, 320.0);
}

/// Home-tab content width. Wide windows keep an 18% margin and cap at 900.
/// Other root tabs and the mini player use the same measure.
double shellContentWidth(double availableWidth) {
  if (availableWidth >= 720) {
    return min(availableWidth * 0.82, 900.0);
  }
  return availableWidth;
}

/// Horizontal inset that lines the mini player up with [shellContentWidth].
/// Narrow windows keep the existing floating margin.
double miniPlayerSideInset({
  required double pageWidth,
  required bool usesSideNavigation,
}) {
  final centered = (pageWidth - shellContentWidth(pageWidth)) / 2;
  if (centered > 0.5) return centered;
  return usesSideNavigation ? 16 : 3;
}

/// Centers [child] in the shared home-tab content width.
class ShellContentFrame extends StatelessWidget {
  const ShellContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = shellContentWidth(constraints.maxWidth);
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}

/// Layout mode supplied by the root navigation shell.
///
/// Root pages use this only to remove their duplicated compact title bar when
/// the shell already provides persistent navigation chrome on the left.
class RootShellLayout extends InheritedWidget {
  const RootShellLayout({
    super.key,
    required this.usesSideNavigation,
    this.obscuredBottom = 0,
    required super.child,
  });

  final bool usesSideNavigation;

  /// Space covered by the floating mini player. Scrollables add this so the
  /// last item can clear the bar, while the page background continues behind it.
  final double obscuredBottom;

  static bool usesSideNavigationOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RootShellLayout>()
            ?.usesSideNavigation ??
        false;
  }

  static double obscuredBottomOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RootShellLayout>()
            ?.obscuredBottom ??
        0;
  }

  @override
  bool updateShouldNotify(RootShellLayout oldWidget) {
    return usesSideNavigation != oldWidget.usesSideNavigation ||
        obscuredBottom != oldWidget.obscuredBottom;
  }
}

class RootHeader {
  const RootHeader({
    required this.title,
    this.titleKey,
    this.actions = const [],
  });

  final String title;
  final Key? titleKey;
  final List<Widget> actions;
}

/// Page titles and portrait header actions, shown in the side rail.
class RootHeaderController extends ChangeNotifier {
  final _headers = List<RootHeader?>.filled(4, null);

  RootHeader? headerFor(int index) {
    if (index < 0 || index >= _headers.length) return null;
    return _headers[index];
  }

  void publish(int index, RootHeader header) {
    if (index < 0 || index >= _headers.length) return;
    _headers[index] = header;
    notifyListeners();
  }

  void clear(int index) {
    if (index < 0 || index >= _headers.length || _headers[index] == null) {
      return;
    }
    _headers[index] = null;
    notifyListeners();
  }
}

class RootHeaderScope extends InheritedWidget {
  const RootHeaderScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final RootHeaderController controller;

  static RootHeaderController? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RootHeaderScope>()?.controller;
  }

  @override
  bool updateShouldNotify(RootHeaderScope oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// Publishes the portrait title-bar title and actions into the side rail.
class RootHeaderPublisher extends StatefulWidget {
  const RootHeaderPublisher({
    super.key,
    required this.index,
    required this.title,
    this.titleKey,
    this.actions = const [],
  });

  final int index;
  final String title;
  final Key? titleKey;
  final List<Widget> actions;

  @override
  State<RootHeaderPublisher> createState() => _RootHeaderPublisherState();
}

class _RootHeaderPublisherState extends State<RootHeaderPublisher> {
  RootHeaderController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePublish();
  }

  @override
  void didUpdateWidget(covariant RootHeaderPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePublish();
  }

  @override
  void dispose() {
    _controller?.clear(widget.index);
    super.dispose();
  }

  void _schedulePublish() {
    final controller = RootHeaderScope.maybeOf(context);
    _controller = controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller != controller) return;
      controller.publish(
        widget.index,
        RootHeader(
          title: widget.title,
          titleKey: widget.titleKey,
          actions: widget.actions,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
