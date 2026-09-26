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

/// Width reserved for the persistent side rail.
///
/// Phone landscape safe areas exist on both horizontal edges. Applying the
/// trailing inset inside the left rail collapses its content to zero, so only
/// the leading inset is included here.
double sideNavigationWidth({
  required bool enabled,
  required EdgeInsets padding,
  required EdgeInsets viewPadding,
}) {
  if (!enabled) return 0;
  final leading = padding.left > viewPadding.left
      ? padding.left
      : viewPadding.left;
  return leading + 176;
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
