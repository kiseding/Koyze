import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/player_route_progress.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/pressable.dart';
import '../../player/presentation/widgets/mini_player.dart';

/// 主壳：底栏 + 迷你播放器；分支内容由 [SwipeBranchContainer] 提供。
class MainScaffold extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  final ValueChanged<int>? onBranchTap;

  const MainScaffold({
    super.key,
    required this.navigationShell,
    this.onBranchTap,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // 上一帧 progress：判定方向——下滑/关闭（progress 下降）时 chrome
  // 全程立即显示，迷你栏绝不"消失一下"；打开（上升）保留退场窗口。
  double _prevProgress = 0;

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    final media = MediaQuery.of(context);
    // `padding` can exclude an overlaid system bar on edge-to-edge platforms.
    // Keep the existing iOS layout, while using the larger stable inset when
    // Flutter reports one through `viewPadding`.
    final bottomInset = media.padding.bottom > media.viewPadding.bottom
        ? media.padding.bottom
        : media.viewPadding.bottom;
    final bottomSpacing = bottomInset == 0 ? 2.0 : 0.0;
    // Without a system bottom inset, the icon/text column needs a few more
    // pixels than the compact iOS bar height to avoid overflowing downward.
    final textScale = media.textScaler.scale(1).clamp(1.0, 2.0);
    final navHeight = 36.0 + (textScale - 1) * 20 + bottomInset + bottomSpacing;
    const miniHeight = 78.0;
    const miniGap = 11.0;
    // 无系统底栏的安卓/Windows：用等效系统栏高度把导航栏整体上移，
    // 使图标列离屏幕底部的距离与 iOS 视觉一致（约 19px）。
    final bottomClearance = bottomInset == 0 ? 11.0 : 0.0;
    // 迷你播放器定位在导航栏容器顶（navHeight+16+clearance）之上 miniGap。
    final miniBottom = bottomInset == 0
        ? navHeight + 16 + bottomClearance + miniGap
        : navHeight + miniGap;
    final selectedIndex = navigationShell.currentIndex;
    // 壳层布局必须与键盘无关：任何 keyboardOpen 时改 padding/挪 chrome
    // 都会在 iOS 首次聚焦时触发布局抖动 → 输入法秒关。
    // 键盘盖住底栏即可；内容区始终预留 chrome 高度。
    final chromeBottom = miniBottom + miniHeight;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: ValueListenableBuilder<double>(
        valueListenable: playerRouteProgress,
        builder: (context, progress, _) {
          // 全屏播放器展开时：底栏向下挤出屏幕、Tab 内容向上挤出屏幕、
          // 迷你栏向上扩张渐隐，营造"从迷你栏展开"的联动感。
          // 透明播放器路由只在前景 currentRect 内绘制。若底层主壳在
          // 前 90% 转场中先上移/消失，未覆盖区域会露出 Navigator/Scaffold
          // 底色，视觉上就是不分深浅色都会闪一下的全屏浅色幕。
          // 所以底层 chrome 保持到播放器几乎全屏后，再在最后 8% 快速退场。
          // 方向感知：下滑/关闭（progress 下降）时 chrome 全程立即显示，
          // 迷你栏绝不"消失一下"；打开（上升）保留最后 8% 退场窗口。
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
          return Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: chromeOpacity,
                  child: Transform.translate(
                    offset: Offset(0, -tabPush * eased),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: chromeBottom),
                      child: navigationShell,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 3,
                right: 3,
                bottom: miniBottom,
                child: Transform.scale(
                  alignment: Alignment.bottomCenter,
                  scale: 1 + 0.035 * eased,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: const MiniPlayer(floating: true, alwaysShow: true),
                  ),
                ),
              ),
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
                      onTap: (i) {
                        if (widget.onBranchTap != null) {
                          widget.onBranchTap!(i);
                        } else {
                          widget.navigationShell.goBranch(i);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
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
    // 外部 goBranch（点底栏）时重置手势状态
    if (oldWidget.currentIndex != widget.currentIndex &&
        !_animating &&
        !_dragging) {
      _dx = 0;
      _transitionTargetIndex = null;
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
    return SizedBox(
      height: height + 16,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: GlassSurface(
              style: AppGlassStyle.bar,
              borderRadius: BorderRadius.zero,
              border: Border(top: AppGlass.hairline(context)),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomSpacing),
              child: Row(
                children: [
                  _item(context, 0, Icons.home_outlined, Icons.home, '首页'),
                  _item(
                    context,
                    1,
                    Icons.leaderboard_outlined,
                    Icons.leaderboard,
                    '榜单',
                  ),
                  _item(
                    context,
                    2,
                    Icons.library_music_outlined,
                    Icons.library_music,
                    '歌单',
                  ),
                  _item(
                    context,
                    3,
                    Icons.settings_outlined,
                    Icons.settings,
                    '设置',
                  ),
                ],
              ),
            ),
          ),
        ],
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
