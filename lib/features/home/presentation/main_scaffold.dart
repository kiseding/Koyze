import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../l10n/app_strings.dart';
import '../../../core/player_route_progress.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../cloud/presentation/cloud_provider.dart';
import '../../player/presentation/widgets/mini_player.dart';
import '../../settings/presentation/settings_provider.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int>? onBranchTap;

  const MainScaffold({
    super.key,
    required this.navigationShell,
    this.onBranchTap,
  });

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

/// Titles and actions published by the four tabs, read by the side rail.
final rootHeaderController = RootHeaderController();

/// Active shell tab. Updated by [MainScaffold], including while a page
/// covers the right pane.
final rootBranchIndex = ValueNotifier<int>(0);

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  // 上一帧 progress：判定方向——下滑/关闭（progress 下降）时 chrome
  // 全程立即显示，迷你栏绝不"消失一下"；打开（上升）保留退场窗口。
  double _prevProgress = 0;

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final media = MediaQuery.of(context);
    final usesSideNavigation = shouldUseSideNavigation(
      size: media.size,
      orientation: media.orientation,
      platform: defaultTargetPlatform,
      isWeb: kIsWeb,
      forceLandscape: ref.watch(forceLandscapeProvider),
    );
    // `padding` can exclude an overlaid system bar on edge-to-edge platforms.
    // Keep the existing iOS layout, while using the larger stable inset when
    // Flutter reports one through `viewPadding`.
    final bottomInset = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    final bottomSpacing = bottomInset == 0 ? 2.0 : 0.0;
    final textScale = media.textScaler.scale(1).clamp(1.0, 2.0);
    final navHeight = 36.0 + (textScale - 1) * 20 + bottomInset + bottomSpacing;
    const miniHeight = 66.0;
    const miniGap = 11.0;
    final trailingInset = media.padding.right > media.viewPadding.right
        ? media.padding.right
        : media.viewPadding.right;
    // Landscape content must clear the rounded screen corner, not only the
    // reported inset. Pages add their own small padding inside this gutter.
    final contentRightInset = usesSideNavigation
        ? (trailingInset > 20 ? trailingInset : 20.0)
        : 0.0;
    // The side rail is outside this navigator, and the media size already
    // excludes it. Do not reserve the rail width a second time.
    const sideRailWidth = 0.0;
    // The side layout has no bottom tab bar, so only reserve space for the
    // mini-player and a small breathing room below it.
    final bottomClearance = bottomInset == 0 ? 11.0 : 0.0;
    final miniBottom = usesSideNavigation
        ? (bottomInset == 0 ? 8.0 : 6.0)
        : bottomInset == 0
        ? navHeight + 16 + bottomClearance + miniGap
        : navHeight + miniGap;
    final selectedIndex = navigationShell.currentIndex;
    if (rootBranchIndex.value != selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootBranchIndex.value != selectedIndex) {
          rootBranchIndex.value = selectedIndex;
        }
      });
    }
    final chromeBottom =
        miniBottom + miniHeight + (usesSideNavigation ? 8.0 : 0.0);
    final pageWidth = media.size.width - sideRailWidth - contentRightInset;
    final miniInset = miniPlayerSideInset(
      pageWidth: pageWidth,
      usesSideNavigation: usesSideNavigation,
    );

    void onBranchTap(int index) {
      if (widget.onBranchTap != null) {
        widget.onBranchTap!(index);
      } else {
        widget.navigationShell.goBranch(index);
      }
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ValueListenableBuilder<double>(
        valueListenable: playerRouteProgress,
        builder: (context, progress, _) {
          final descending = progress < _prevProgress;
          _prevProgress = progress;
          final visibleProgress = descending || progress <= 0.92
              ? 0.0
              : ((progress - 0.92) / 0.08).clamp(0.0, 1.0);
          final eased = reduceMotion(context)
              ? (visibleProgress == 0 ? 0.0 : 1.0)
              : Curves.easeOutCubic.transform(visibleProgress);
          final chromeOpacity = 1 - visibleProgress;
          final navPush = miniBottom + miniHeight;
          final tabPush = chromeBottom * 0.6;
          final shell = RootShellLayout(
            usesSideNavigation: usesSideNavigation,
            obscuredBottom: usesSideNavigation ? chromeBottom : 0,
            child: navigationShell,
          );

          final content = Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: chromeOpacity,
                  child: Transform.translate(
                    offset: Offset(0, -tabPush * eased),
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: contentRightInset,
                        bottom: usesSideNavigation ? 0 : chromeBottom,
                      ),
                      child: shell,
                    ),
                  ),
                ),
              ),
              if (!usesSideNavigation)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomClearance,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: Transform.translate(
                      offset: Offset(0, navPush * eased),
                      child: _BottomNav(
                        height: navHeight,
                        bottomSpacing: bottomSpacing,
                        selectedIndex: selectedIndex,
                        onTap: onBranchTap,
                      ),
                    ),
                  ),
                ),
              Positioned(
                // Match the home tab column. Narrow windows keep the small
                // floating inset; wide windows use the same centered width.
                left: miniInset,
                right: contentRightInset + miniInset,
                bottom: miniBottom,
                child: Transform.scale(
                  alignment: Alignment.bottomCenter,
                  scale: 1 + 0.035 * eased,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: const MiniPlayer(
                      floating: true,
                      alwaysShow: true,
                    ),
                  ),
                ),
              ),
            ],
          );

          return RootHeaderScope(
            controller: rootHeaderController,
            child: content,
          );
        },
      ),
    );
  }
}

/// 双页跟手滑动：目标页从侧边跟入，松手后顺势切完，不再弹回/闪跳。
class SwipeBranchContainer extends StatefulWidget {
  final int currentIndex;
  final List<Widget> children;
  final void Function(int index) onSelect;

  const SwipeBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
    required this.onSelect,
  });

  @override
  State<SwipeBranchContainer> createState() => SwipeBranchContainerState();
}

class SwipeBranchContainerState extends State<SwipeBranchContainer>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _dragging = false;
  bool _animating = false;
  int? _transitionTargetIndex;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: MotionDuration.normal);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SwipeBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Route/goBranch changes must snap even if a swipe animation is in flight.
    // Otherwise the URI can move to /settings while the visible page stays home.
    if (oldWidget.currentIndex != widget.currentIndex) {
      _anim.stop();
      _dx = 0;
      _transitionTargetIndex = null;
      _animating = false;
      _dragging = false;
    }
  }

  Future<void> _animateTo(double end) async {
    if (reduceMotion(context)) {
      setState(() {
        _dragging = false;
        _animating = true;
        _dx = end;
      });
      return;
    }
    final start = _dx;
    _anim.reset();
    final tween = Tween<double>(
      begin: start,
      end: end,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    void tick() {
      if (mounted) setState(() => _dx = tween.value);
    }

    tween.addListener(tick);
    setState(() {
      _dragging = false;
      _animating = true;
    });
    try {
      await _anim.forward();
    } on TickerCanceled {
      // 壳层在动画中销毁时静默退出，避免未捕获异步异常。
    }
    tween.removeListener(tick);
  }

  Future<void> _finish(double width, double velocity) async {
    if (_animating) return;
    final idx = widget.currentIndex;
    final count = widget.children.length;
    final threshold = width * 0.18;
    int? target;
    if (_dx < -threshold || velocity < -400) {
      // 左滑进入下一项；最后一页循环回首页。
      target = idx + 1 < count ? idx + 1 : 0;
    } else if (_dx > threshold || velocity > 400) {
      // 右滑进入上一项；首页循环到最后一页。
      target = idx > 0 ? idx - 1 : count - 1;
    }

    if (target == null) {
      await _animateTo(0);
      if (!mounted) return;
      setState(() {
        _animating = false;
        _dx = 0;
      });
      return;
    }

    final end = _neighborEntersFromRight(idx, target) ? -width : width;
    _transitionTargetIndex = target;
    await _animateTo(end);
    if (!mounted) return;
    // 切页时同时清零位移：新页以静止态显示，无回弹
    setState(() {
      _animating = false;
      _dragging = false;
      _dx = 0;
      _transitionTargetIndex = null;
    });
    widget.onSelect(target);
  }

  /// 循环切换时判定目标页从哪侧进入：
  /// 正常下一页（idx+1）从右侧；首页右滑到末页视为“上一项”，从左侧进入。
  bool _neighborEntersFromRight(int idx, int target) {
    final count = widget.children.length;
    if (target == idx + 1) return true;
    if (idx == 0 && target == count - 1) return false;
    if (idx == count - 1 && target == 0) return true;
    return target > idx;
  }

  Future<void> select(int target) async {
    if (target < 0 || target >= widget.children.length || _animating) return;
    final current = widget.currentIndex;
    if (target == current) {
      widget.onSelect(target);
      return;
    }

    final width = MediaQuery.sizeOf(context).width;
    _transitionTargetIndex = target;
    await _animateTo(target > current ? -width : width);
    if (!mounted) return;
    setState(() {
      _animating = false;
      _dragging = false;
      _dx = 0;
      _transitionTargetIndex = null;
    });
    widget.onSelect(target);
  }

  /// 输入框已聚焦：整页卸横滑，避免误滑关盘。
  /// 不读 viewInsets：键盘动画中 MediaQuery 变化会 rebuild 手势树，
  /// 在 iOS 首焦过程中足以把输入法打掉。
  bool get _imeActive {
    return FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
  }

  /// 根因：父级 HorizontalDrag 只要 addAllowedPointer，就会进 gesture arena，
  /// 与 TextField 首击抢手势 → iOS 输入法秒关。落在可编辑区域时直接不参赛。
  bool _shouldParticipateInSwipe(Offset globalPosition) {
    if (_animating) return false;
    if (_imeActive) return false;
    if (_hitTestEditable(globalPosition)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final idx = widget.currentIndex;
    final count = widget.children.length;
    final moving = _dragging || _animating;

    // 邻页：跟手预览（支持循环切换）
    int? neighbor = _transitionTargetIndex;
    if (moving) {
      if (neighbor == null && _dx < 0) {
        neighbor = idx + 1 < count ? idx + 1 : 0;
      } else if (neighbor == null && _dx > 0) {
        neighbor = idx > 0 ? idx - 1 : count - 1;
      }
    }

    final stack = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!moving)
            for (var i = 0; i < count; i++)
              Offstage(
                offstage: i != idx,
                child: TickerMode(enabled: i == idx, child: widget.children[i]),
              ),
          if (moving) ...[
            if (neighbor != null)
              Transform.translate(
                offset: Offset(_dx < 0 ? width + _dx : -width + _dx, 0),
                child: widget.children[neighbor],
              ),
            Transform.translate(
              offset: Offset(_dx, 0),
              child: widget.children[idx],
            ),
          ],
        ],
      ),
    );

    // 始终挂载识别器，但 addAllowedPointer 在 TextField/已聚焦时直接 return，
    // 不进 arena。禁止在聚焦时拆掉 GestureDetector（子树结构突变也会关盘）。
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _EditableAwareHorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _EditableAwareHorizontalDragGestureRecognizer
            >(
              () => _EditableAwareHorizontalDragGestureRecognizer(
                debugOwner: this,
                shouldParticipate: _shouldParticipateInSwipe,
                supportedDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                },
              ),
              (_EditableAwareHorizontalDragGestureRecognizer instance) {
                // ignore: invalid_use_of_protected_member
                instance.gestureSettings = const DeviceGestureSettings(
                  touchSlop: 28,
                );
                instance
                  ..onStart = (details) {
                    if (_animating) return;
                    setState(() {
                      _dragging = true;
                      _dx = 0;
                    });
                  }
                  ..onUpdate = (details) {
                    if (_animating || !_dragging) return;
                    setState(() => _dx += details.delta.dx);
                  }
                  ..onEnd = (details) {
                    if (_animating) return;
                    _finish(width, details.primaryVelocity ?? 0);
                  }
                  ..onCancel = () {
                    if (_animating) return;
                    _finish(width, 0);
                  };
              },
            ),
      },
      behavior: HitTestBehavior.translucent,
      child: stack,
    );
  }

  bool _hitTestEditable(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final local = box.globalToLocal(globalPosition);
    final result = BoxHitTestResult();
    if (!box.hitTest(result, position: local)) return false;
    for (final entry in result.path) {
      final t = entry.target;
      if (t is RenderEditable) return true;
    }
    return false;
  }
}

/// 落在 TextField 时不进入 gesture arena，从根上避免与首焦抢手势。
class _EditableAwareHorizontalDragGestureRecognizer
    extends HorizontalDragGestureRecognizer {
  _EditableAwareHorizontalDragGestureRecognizer({
    required this.shouldParticipate,
    super.debugOwner,
    super.supportedDevices,
  });

  final bool Function(Offset globalPosition) shouldParticipate;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!shouldParticipate(event.position)) {
      return;
    }
    super.addAllowedPointer(event);
  }
}

const _sideNavItemOuterPadding = 8.0;
const _sideNavItemInnerPadding = 10.0;

/// 标题栏占位：上 18 + 字高 52 + 下 10。矮屏放不下整栏时整段隐藏。
const _sideNavTitleExtent = 80.0;
const _sideNavRuleExtent = 1.0;
const _sideNavTabExtent = 54.0;
const _sideNavTabGap = 8.0;
const _sideNavShortcutExtent = 36.0;
const _sideNavFooterPadding = 16.0;

/// 三个标签、设置和登录入口，按舒适字号排开的高度。
const _sideNavBodyExtent =
    _sideNavTabExtent * 3 +
    _sideNavTabGap * 2 +
    _sideNavRuleExtent +
    _sideNavFooterPadding +
    _sideNavTabExtent +
    _sideNavShortcutExtent;

/// 浅色用实色卡片，深色用主题色薄底，避免半透明绿在两种背景上都发灰。
Color _sideNavSelectedFill(BuildContext context) {
  if (!AppColors.isDark(context)) return AppColors.card(context);
  return Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);
}

class RootSideNav extends ConsumerWidget {
  final int selectedIndex;
  final RootHeaderController headers;
  final ValueChanged<int> onTap;
  final String currentPath;
  final VoidCallback onOpenSync;

  const RootSideNav({
    super.key,
    required this.selectedIndex,
    required this.headers,
    required this.onTap,
    required this.currentPath,
    required this.onOpenSync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final session = ref.watch(cloudSessionProvider);
    return ListenableBuilder(
      listenable: headers,
      builder: (context, _) {
        final path = currentPath;
        final loggedIn = session.loggedIn;
        final username = session.username?.trim() ?? '';
        return LayoutBuilder(
          builder: (context, constraints) {
            final showTitle =
                constraints.maxHeight >=
                _sideNavTitleExtent + _sideNavRuleExtent + _sideNavBodyExtent;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showTitle) ...[
                  _title(context),
                  _rule(context),
                ] else
                  const SizedBox(height: 8),
                _item(context, 0, Icons.home_outlined, Icons.home, s.home),
                const SizedBox(height: _sideNavTabGap),
                _item(
                  context,
                  1,
                  Icons.leaderboard_outlined,
                  Icons.leaderboard,
                  s.charts,
                ),
                const SizedBox(height: _sideNavTabGap),
                _item(
                  context,
                  2,
                  Icons.library_music_outlined,
                  Icons.library_music,
                  s.playlists,
                ),
                const Spacer(),
                _rule(context),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Column(
                    children: [
                      _item(
                        context,
                        3,
                        Icons.settings_outlined,
                        Icons.settings,
                        s.settings,
                      ),
                      _shortcut(
                        context,
                        icon: loggedIn && username.isNotEmpty
                            ? Icons.person_rounded
                            : Icons.login_rounded,
                        color: AppColors.accentOf(context),
                        label: loggedIn && username.isNotEmpty
                            ? username
                            : s.login,
                        semanticLabel: loggedIn && username.isNotEmpty
                            ? s.loggedInAs(username)
                            : s.login,
                        selected: _isPath(path, '/sync'),
                        onTap: onOpenSync,
                        compact: true,
                        trailing: loggedIn
                            ? _logoutButton(context, ref, s, compact: true)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _title(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _sideNavItemOuterPadding + _sideNavItemInnerPadding,
        18,
        8,
        10,
      ),
      child: SizedBox(
        height: 52,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Koyze',
            key: headers.headerFor(0)?.titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.amber,
            ),
          ),
        ),
      ),
    );
  }

  Widget _rule(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardBorder(context),
          borderRadius: BorderRadius.circular(1),
        ),
        child: const SizedBox(height: 1),
      ),
    );
  }

  Widget _shortcut(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? semanticLabel,
    Widget? trailing,
    bool compact = false,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppColors.isDark(context);
    final muted = isDark ? const Color(0xC7FFFFFF) : const Color(0xC7000000);
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 0 : 2, 0, 8, 0),
      child: SizedBox(
        height: compact ? 32 : _sideNavShortcutExtent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? _sideNavSelectedFill(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: compact ? 18 : 8, right: 2),
            child: Row(
              children: [
                Expanded(
                  child: Pressable(
                    semanticLabel: semanticLabel ?? label,
                    onTap: onTap,
                    scale: 0.98,
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(icon, size: compact ? 14 : 16, color: color),
                        SizedBox(width: compact ? 6 : 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? accent : muted,
                              fontSize: compact ? 13 : 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(
    BuildContext context,
    WidgetRef ref,
    S s, {
    bool compact = false,
  }) {
    return Pressable(
      semanticLabel: s.logOut,
      tooltip: s.logOut,
      onTap: () async {
        await ref.read(cloudSessionProvider.notifier).logout();
        if (!context.mounted) return;
        final next = ref.read(cloudSessionProvider);
        showAppNotification(
          next.loggedIn ? (next.error ?? s.logOut) : s.loggedOut,
          type: next.loggedIn
              ? AppNotificationType.error
              : AppNotificationType.success,
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: compact ? 24 : 28,
          height: compact ? 24 : 28,
          child: Icon(
            Icons.logout_rounded,
            size: compact ? 14 : 16,
            color: AppColors.error,
          ),
        ),
      ),
    );
  }

  bool _isPath(String path, String location) {
    return path == location || path.startsWith('$location/');
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = index == selectedIndex;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppColors.isDark(context);
    final muted = isDark ? const Color(0xE6FFFFFF) : const Color(0xE6000000);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sideNavItemOuterPadding),
      child: SizedBox(
        height: _sideNavTabExtent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? _sideNavSelectedFill(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _sideNavItemInnerPadding,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Pressable(
                    semanticLabel: label,
                    selected: isSelected,
                    onTap: () => onTap(index),
                    scale: 0.96,
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        AnimatedIconSwitch(
                          icon: isSelected ? activeIcon : icon,
                          keyValue: isSelected ? activeIcon : icon,
                          size: 26,
                          color: isSelected ? accent : muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? accent : muted,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ..._tabActions(index, isSelected),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _standbyActionIcons = <int, IconData>{
    0: Icons.tune_rounded,
    1: Icons.tune_rounded,
    2: Icons.playlist_add_rounded,
  };

  List<Widget> _tabActions(int index, bool enabled) {
    final published =
        headers
            .headerFor(index)
            ?.actions
            .whereType<FrostedHeaderButton>()
            .toList() ??
        const <FrostedHeaderButton>[];
    final icons = published.isNotEmpty
        ? published.map((button) => button.icon).toList()
        : [if (_standbyActionIcons[index] case final icon?) icon];
    if (icons.isEmpty) return const [];
    return [
      for (var i = 0; i < icons.length; i++) ...[
        const SizedBox(width: 4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? null : () {},
          child: IgnorePointer(
            ignoring: !enabled,
            child: ExcludeSemantics(
              excluding: !enabled,
              child: FrostedHeaderButton(
                icon: icons[i],
                semanticLabel: i < published.length
                    ? published[i].semanticLabel
                    : null,
                dimmed: !enabled,
                solid: true,
                iconSize: 16,
                padding: const EdgeInsets.all(6),
                onTap: enabled && i < published.length
                    ? published[i].onTap
                    : () {},
              ),
            ),
          ),
        ),
      ],
    ];
  }
}

class _BottomNav extends StatelessWidget {
  final double height;
  final double bottomSpacing;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.height,
    required this.bottomSpacing,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SizedBox(
      height: height + 16,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomSpacing),
        child: Row(
          children: [
            _item(context, 0, Icons.home_outlined, Icons.home, s.home),
            _item(
              context,
              1,
              Icons.leaderboard_outlined,
              Icons.leaderboard,
              s.charts,
            ),
            _item(
              context,
              2,
              Icons.library_music_outlined,
              Icons.library_music,
              s.playlists,
            ),
            _item(
              context,
              3,
              Icons.settings_outlined,
              Icons.settings,
              s.settings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final isSelected = index == selectedIndex;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppColors.isDark(context);
    // 未选中也要深、粗（约 90% 不透明）
    final muted = isDark ? const Color(0xE6FFFFFF) : const Color(0xE6000000);
    return Expanded(
      child: Pressable(
        semanticLabel: label,
        selected: isSelected,
        onTap: () => onTap(index),
        scale: 0.92,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedIconSwitch(
                icon: isSelected ? activeIcon : icon,
                keyValue: isSelected ? activeIcon : icon,
                size: 23,
                color: isSelected ? accent : muted,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? accent : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
