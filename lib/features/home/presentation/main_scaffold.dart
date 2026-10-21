import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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
import '../../../core/widgets/root_tab_bar.dart';
import '../../cloud/presentation/cloud_provider.dart';
import '../../player/presentation/widgets/mini_player.dart';
import '../../settings/presentation/settings_provider.dart';
import 'widgets/mini_bar.dart';

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

/// 顶栏此刻该显示哪一页的标题与动作按钮。
///
/// 它**不是**路由的 currentIndex。点击 tab / 横滑时，目标页在补间一开始就
/// 跟着手指进来了，而路由要等补间跑完才 `goBranch`——中间这 300~400ms 里
/// 顶栏还挂着上一页的动作：看着榜单卡片已经铺满屏幕，右上角那颗「榜单设置」
/// 却要再等一下才冒出来，在那之前根本点不到。
///
/// [SwipeBranchContainer] 在「决定去目标页」的那一刻（手指抬起判定通过、
/// 或点击动画起跑）就把它切过去；被重新按住 / 取消时退回当前页。
final rootHeaderBranchIndex = ValueNotifier<int>(0);

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
    // 竖屏底部只有一条迷你播放条，几何与播放页 morph 共用同一份数字。
    final miniBar = KoyzeMiniBarMetrics(
      screen: media.size,
      bottomInset: bottomInset,
    );
    final trailingInset = media.padding.right > media.viewPadding.right
        ? media.padding.right
        : media.viewPadding.right;
    // Landscape content must clear the rounded screen corner, not only the
    // reported inset. Pages add their own small padding inside this gutter.
    final contentRightInset = usesSideNavigation
        ? (trailingInset > 20 ? trailingInset : 20.0)
        : 0.0;
    // 竖屏顶部有一根毛玻璃标题栏，它自己吃掉状态栏高度；横屏/桌面走侧栏时
    // 那根栏不画，页面只按「没有标题栏」留十来点间距——于是右上角的搜索框
    // 直接顶到状态栏下沿，读起来像内容压在了系统栏上。这里把状态栏安全区
    // 补到壳层上，页面的间距就变成「状态栏下面再留一段」。
    // 迷你播放条是另一个 Positioned 层，位置不受这段内边距影响。
    final topInset = media.padding.top > media.viewPadding.top
        ? media.padding.top
        : media.viewPadding.top;
    final contentTopInset = usesSideNavigation ? topInset : 0.0;
    // The side rail is outside this navigator, and the media size already
    // excludes it. Do not reserve the rail width a second time.
    const sideRailWidth = 0.0;
    // 横屏/桌面没有底部导航：迷你播放条仍是一张完整卡片；竖屏是横跨
    // 内容区的一条玻璃栏。
    final miniHeight = usesSideNavigation ? 78.0 : kMiniBarHeight;
    final miniBottom = usesSideNavigation
        ? (bottomInset == 0 ? 8.0 : 6.0)
        : miniBar.bottom;
    final selectedIndex = navigationShell.currentIndex;
    if (rootBranchIndex.value != selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootBranchIndex.value != selectedIndex) {
          rootBranchIndex.value = selectedIndex;
        }
      });
    }
    final chromeBottom = usesSideNavigation
        ? miniBottom + miniHeight + 8.0
        : miniBar.contentObstruction;
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
          final tabPush = chromeBottom * 0.6;
          final shell = RootShellLayout(
            usesSideNavigation: usesSideNavigation,
            // 底部 chrome 不再"占位"：页面一直画到屏幕底边，dock 是浮在上面
            // 的一层液态玻璃，滚动内容从它后面经过并透出来。各根页面用这个
            // 高度给自己的滚动列表留出底部安全距离。
            obscuredBottom: chromeBottom,
            child: navigationShell,
          );

          // 顶部栏固定在壳层里，不跟着页面走。四个根页面只把标题和动作
          // 发布到 rootHeaderController，栏本身在这里渲染一次——切 tab 时
          // 页面在下面横移，栏原地不动，只有文字和药丸换位置。
          final chrome = Stack(
            fit: StackFit.expand,
            children: [
              shell,
              if (!usesSideNavigation)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<int>(
                    // 顶栏跟的是「视觉上的当前页」，不是路由索引：过渡一旦
                    // 决定去目标页就换过来，右上角的动作按钮和页面同一帧
                    // 到位，落地的瞬间就能点。
                    valueListenable: rootHeaderBranchIndex,
                    builder: (context, chromeIndex, _) {
                      return ListenableBuilder(
                        listenable: rootHeaderController,
                        builder: (context, _) {
                          final header = rootHeaderController.headerFor(
                            chromeIndex,
                          );
                          return FrostedTabHeader(
                            // 竖屏里标题不再渲染：选中的那个 tab 展开后就是
                            // 这一页的名字，再写一遍大标题只是重复。title 仍
                            // 传过去，回退标题栏（推送页）才用得到。
                            title: header?.title ?? '',
                            titleKey: header?.titleKey,
                            actions: header?.actions ?? const [],
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
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
                        top: contentTopInset,
                      ),
                      child: chrome,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: usesSideNavigation ? miniInset : kMiniBarSideMargin,
                right: usesSideNavigation
                    ? contentRightInset + miniInset
                    : kMiniBarSideMargin,
                bottom: miniBottom,
                child: Transform.scale(
                  alignment: Alignment.bottomCenter,
                  scale: 1 + 0.035 * eased,
                  child: Opacity(
                    opacity: chromeOpacity,
                    child: MiniPlayer(
                      floating: usesSideNavigation,
                      alwaysShow: true,
                    ),
                  ),
                ),
              ),
            ],
          );

          return RootTabScope(
            selectedIndex: selectedIndex,
            onTap: onBranchTap,
            child: RootHeaderScope(
              controller: rootHeaderController,
              child: content,
            ),
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

/// 松手补间的弹簧：略过阻尼（ζ≈1.08），不回弹但保留手指速度。
const _kSettleSpring = SpringDescription(mass: 1, stiffness: 340, damping: 40);

/// 松手速度超过这个值就翻页（px/s）。比原来的 400 低——有了弹簧，
/// 轻挑一下就能顺着惯性过去，不必甩得那么用力。
const double _kFlickVelocity = 320;

/// 弹簧初速度上限：极端甩动时不让页面甩出好几屏。
const double _kMaxSettleVelocity = 3200;

class SwipeBranchContainerState extends State<SwipeBranchContainer>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  bool _dragging = false;
  bool _animating = false;
  int? _transitionTargetIndex;

  /// 视觉上的当前页。
  ///
  /// 补间刚落到目标页时要立刻切过来，不能等外层 goBranch 把 currentIndex
  /// 推回来——中间那一帧会画成「旧页静止在原点」，收尾时闪一下旧页。
  int? _visualIndex;

  /// 每次新手势 / 新补间递增。旧的补间回来时用它判断自己是否已过期，
  /// 过期就不再提交结果（否则会把手势中途接管的页又切走）。
  int _epoch = 0;

  /// 无界控制器：位移由 [SpringSimulation] 直接驱动。
  ///
  /// 之前是固定 280ms + easeOutCubic：松手瞬间曲线从零速度起步，页面会先
  /// 顿一下再加速，而且不管还剩多少距离都走满 280ms。改成弹簧后松手速度
  /// 被继承下来，剩得少就收得快，才是 iOS 那种「接着滑」的手感。
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController.unbounded(vsync: this)..addListener(_tick);
    // 壳层可能是被深链直接建在某一页上的：先把顶栏对齐到当前页，
    // 免得第一帧显示上一页残留的动作按钮。
    rootHeaderBranchIndex.value = widget.currentIndex;
  }

  @override
  void dispose() {
    _anim.removeListener(_tick);
    _anim.dispose();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _dx = _anim.value);
    _syncDragProgress(MediaQuery.sizeOf(context).width);
  }

  /// 渲染用的页码：手势刚落定时是目标页，其余时候跟路由一致。
  int get _renderIndex => _visualIndex ?? widget.currentIndex;

  @override
  void didUpdateWidget(covariant SwipeBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 路由真的换页了：清掉视觉索引，交回 widget.currentIndex 控制。
    if (_visualIndex != null && widget.currentIndex == _visualIndex) {
      _visualIndex = null;
    }
    // Route/goBranch changes must snap even if a swipe animation is in flight.
    // Otherwise the URI can move to /settings while the visible page stays home.
    if (oldWidget.currentIndex != widget.currentIndex) {
      _epoch++;
      _anim.stop();
      _dx = 0;
      _visualIndex = null;
      _transitionTargetIndex = null;
      _animating = false;
      _dragging = false;
      rootBranchDrag.value = 0;
      rootBranchDragTarget.value = null;
      rootHeaderBranchIndex.value = widget.currentIndex;
    }
  }

  /// 把当前位移折算成 tab 条用的进度（向下一页为正）。
  void _syncDragProgress(double width) {
    if (width <= 0) return;
    rootBranchDrag.value = (-_dx / width).clamp(-1.0, 1.0);
  }

  /// 用弹簧把位移收向 [end]，[velocity] 是松手瞬间的手指速度（px/s）。
  ///
  /// 返回 false 表示这段补间被新手势打断了，调用方不要再提交切页结果。
  Future<bool> _settleTo(double end, double velocity) async {
    final epoch = ++_epoch;
    if (reduceMotion(context)) {
      _anim.value = end;
      setState(() {
        _dragging = false;
        _animating = true;
        _dx = end;
      });
      return epoch == _epoch;
    }
    setState(() {
      _dragging = false;
      _animating = true;
    });
    final simulation = SpringSimulation(
      _kSettleSpring,
      _dx,
      end,
      velocity.clamp(-_kMaxSettleVelocity, _kMaxSettleVelocity).toDouble(),
    );
    await _anim.animateWith(simulation);
    if (!mounted || epoch != _epoch) return false;
    _anim.value = end;
    return true;
  }

  Future<void> _finish(double width, double velocity) async {
    if (_animating) return;
    final idx = _renderIndex;
    final count = widget.children.length;
    // 位移过屏宽 20% 或甩得够快就翻页。有了弹簧，速度这一条是主角：
    // 轻轻一挑就能过，慢慢拖到 20% 也让过。
    final threshold = width * 0.2;
    int? target;
    if (velocity < -_kFlickVelocity || _dx < -threshold) {
      // 左滑进入下一项；最后一页循环回首页。
      target = idx + 1 < count ? idx + 1 : 0;
    } else if (velocity > _kFlickVelocity || _dx > threshold) {
      // 右滑进入上一项；首页循环到最后一页。
      target = idx > 0 ? idx - 1 : count - 1;
    }

    if (target == null || target == idx) {
      // 取消：被重新按住再放回原页时，顶栏要跟着退回来。
      rootHeaderBranchIndex.value = idx;
      if (!await _settleTo(0, velocity)) return;
      if (!mounted) return;
      setState(() {
        _animating = false;
        _dragging = false;
        _dx = 0;
      });
      rootBranchDrag.value = 0;
      return;
    }

    final end = _neighborEntersFromRight(idx, target) ? -width : width;
    _transitionTargetIndex = target;
    rootBranchDragTarget.value = target;
    // 手指抬起的这一帧就把顶栏换成目标页的：此时页面正顺着惯性滑进来，
    // 右上角的动作按钮和它同时到位，落地的瞬间就能点。
    rootHeaderBranchIndex.value = target;
    if (!await _settleTo(end, velocity)) return;
    if (!mounted) return;
    // 补间已经落到目标页：先把渲染索引切过去，再把路由推过去。
    // 两个动作在同一帧里完成，页面始终是静止的目标页，不会闪回旧页。
    setState(() {
      _animating = false;
      _dragging = false;
      _dx = 0;
      _visualIndex = target;
      _transitionTargetIndex = null;
    });
    // 先把 tab 条钉到目标，再撤掉进度：两步在同一帧里完成，胶囊不会先弹
    // 回旧 tab、再从 0 重播一遍展开动画（那正是"切完又跳一下"的来源）。
    rootBranchSettle.value = target;
    rootBranchDrag.value = 0;
    rootBranchDragTarget.value = null;
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
    if (target < 0 || target >= widget.children.length) return;
    // 动画状态可能因为上一条手势被中断而残留：没有位移、控制器也没在跑时
    // 直接复位，否则一次误触就能让 tab 栏在本次会话里永久点不动。
    if (_animating && !_anim.isAnimating && _dx.abs() < 0.5) {
      _animating = false;
    }
    if (_animating) return;
    final current = _renderIndex;
    if (target == current) {
      widget.onSelect(target);
      return;
    }

    final width = MediaQuery.sizeOf(context).width;
    _transitionTargetIndex = target;
    rootBranchDragTarget.value = target;
    // 点击也是「页面开始滑 = 顶栏开始换」：动作按钮随页面一起进场，
    // 而不是等补间跑完、路由切过去之后才补上。
    rootHeaderBranchIndex.value = target;
    if (!await _settleTo(target > current ? -width : width, 0)) return;
    if (!mounted) return;
    setState(() {
      _animating = false;
      _dragging = false;
      _dx = 0;
      _visualIndex = target;
      _transitionTargetIndex = null;
    });
    // 先把 tab 条钉到目标，再撤掉进度：两步在同一帧里完成，胶囊不会先弹
    // 回旧 tab、再从 0 重播一遍展开动画（那正是"切完又跳一下"的来源）。
    rootBranchSettle.value = target;
    rootBranchDrag.value = 0;
    rootBranchDragTarget.value = null;
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
    // 补间进行中也参赛：按住就能打断、接着拖，这是 iOS 的手感。
    // 中断判定在 onStart 里做（那时才赢下 arena，不会误打断一次点击）。
    if (_imeActive) return false;
    if (_hitTestEditable(globalPosition)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final idx = _renderIndex;
    final count = widget.children.length;
    final moving = _dragging || _animating;

    // 邻页：跟手预览（支持循环切换）
    int? neighbor;
    if (moving) {
      neighbor = _transitionTargetIndex;
      if (neighbor == null) {
        if (_dx < 0) {
          neighbor = idx + 1 < count ? idx + 1 : 0;
        } else if (_dx > 0) {
          neighbor = idx > 0 ? idx - 1 : count - 1;
        }
      }
    }

    final stack = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 每页在树上占一个**固定位置**，起手/落手只改 offstage 和位移。
          // 之前是「静止时挂 N 个 Offstage，滑动时换成另外两个 Transform」，
          // 子树结构一变，全部页面的 element 就被销毁重建一次——一次滑动
          // 起手和落手各卡一帧，这才是"慢半拍"的主因。
          for (var i = 0; i < count; i++)
            _buildLayer(i, idx: idx, neighbor: neighbor, width: width),
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
                  // 28 的 slop 让「已经开始滑了」和「页面开始动」之间隔着
                  // 近一指宽，手感就是迟滞。收到 16：仍能和纵向列表区分，
                  // 跟手却明显更快。
                  touchSlop: 16,
                );
                instance
                  // 从按下点算起：否则识别成功时页面比手指永久落后一个
                  // slop（16px），整段拖动都是"差半拍"。
                  ..dragStartBehavior = DragStartBehavior.down
                  ..onStart = (details) {
                    // 补间还没跑完就重新按住：立刻接管，从当前位移继续拖。
                    if (_animating) {
                      _epoch++;
                      _anim.stop();
                      _transitionTargetIndex = null;
                      rootBranchDragTarget.value = null;
                      // 顶栏退回屏幕上这一页的：刚才决定要走了，现在又被
                      // 按住，最后可能滑回原页，动作按钮不能先跳过去。
                      rootHeaderBranchIndex.value = _renderIndex;
                      _animating = false;
                    }
                    setState(() => _dragging = true);
                    // 不重置 _dx：接管时要从页面当前的位置继续。
                  }
                  ..onUpdate = (details) {
                    if (_animating || !_dragging) return;
                    setState(() => _dx += details.delta.dx);
                    _syncDragProgress(width);
                  }
                  ..onEnd = (details) {
                    if (_animating) return;
                    _finish(width, details.primaryVelocity ?? 0);
                  }
                  // 只有真正拖动过的指针才需要收尾：点击时横向识别器会被
                  // 判负并回调 onCancel，若在这里也跑一次归位动画，就会在
                  // 同一帧把 _animating 置为 true，把随后的 tab 点击吞掉。
                  ..onCancel = () {
                    if (_animating || !_dragging) return;
                    _finish(width, 0);
                  };
              },
            ),
      },
      behavior: HitTestBehavior.translucent,
      child: stack,
    );
  }

  /// 单页图层。位置固定，只有 offstage 与位移随手势变化。
  Widget _buildLayer(
    int i, {
    required int idx,
    required int? neighbor,
    required double width,
  }) {
    final isCurrent = i == idx;
    final isNeighbor = neighbor == i;
    final hidden = !isCurrent && !isNeighbor;
    final offset = isCurrent
        ? _dx
        : isNeighbor
        ? (_dx < 0 ? width : -width) + _dx
        : 0.0;
    return Offstage(
      offstage: hidden,
      child: TickerMode(
        // 滑入中的邻居页保持 ticker 运行（和原先一致），隐藏页停表。
        enabled: !hidden,
        child: Transform.translate(
          offset: Offset(offset, 0),
          child: widget.children[i],
        ),
      ),
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

/// 手机横屏（393pt 高）放不下常规档：标题整段会被判掉，栏顶直接从第一个
/// tab 开始，看上去像少了一块。矮屏换成紧凑档——标题留着但压扁，行高和
/// 间距各收一档，五个入口仍然一次排开。
const _sideNavTitleCompactExtent = 58.0;
const _sideNavTabCompactExtent = 46.0;
const _sideNavTabCompactGap = 6.0;

/// 低于这个高度就换紧凑档（手机横屏 393、折叠屏展开后才回到常规）。
const double _sideNavCompactBelow = 420;

/// Selected rail item: an accent wash, not an opaque card. A solid white pill
/// on top of glass reads as a different material.
Color _sideNavSelectedFill(BuildContext context) {
  final accent = Theme.of(context).colorScheme.primary;
  return accent.withValues(alpha: AppColors.isDark(context) ? 0.18 : 0.11);
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
            final compact = constraints.maxHeight < _sideNavCompactBelow;
            final tabExtent = compact
                ? _sideNavTabCompactExtent
                : _sideNavTabExtent;
            final tabGap = compact ? _sideNavTabCompactGap : _sideNavTabGap;
            final titleExtent = compact
                ? _sideNavTitleCompactExtent
                : _sideNavTitleExtent;
            final bodyExtent =
                tabGap +
                tabExtent * 3 +
                tabGap * 2 +
                _sideNavRuleExtent +
                _sideNavFooterPadding +
                tabExtent +
                _sideNavShortcutExtent;
            final showTitle =
                constraints.maxHeight >=
                titleExtent + _sideNavRuleExtent + bodyExtent;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showTitle) ...[
                  _title(context, compact: compact),
                  _rule(context),
                ] else
                  const SizedBox(height: 8),
                // 选中态的绿色药丸是 14 圆角，紧贴分隔线时上缘会把线压住，
                // 看着像"高亮溢出到线上"。空出与 tab 之间相同的间距，节奏也一致。
                SizedBox(height: tabGap),
                _item(
                  context,
                  0,
                  Icons.home_outlined,
                  Icons.home,
                  s.home,
                  extent: tabExtent,
                ),
                SizedBox(height: tabGap),
                _item(
                  context,
                  1,
                  Icons.leaderboard_outlined,
                  Icons.leaderboard,
                  s.charts,
                  extent: tabExtent,
                ),
                SizedBox(height: tabGap),
                _item(
                  context,
                  2,
                  Icons.library_music_outlined,
                  Icons.library_music,
                  s.playlists,
                  extent: tabExtent,
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
                        extent: tabExtent,
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

  Widget _title(BuildContext context, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideNavItemOuterPadding + _sideNavItemInnerPadding,
        compact ? 12 : 18,
        8,
        compact ? 6 : 10,
      ),
      child: SizedBox(
        height: compact ? 40 : 52,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Koyze',
            key: headers.headerFor(0)?.titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 21 : 26,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.accentOf(context),
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
    String label, {
    required double extent,
  }) {
    final isSelected = index == selectedIndex;
    final accent = Theme.of(context).colorScheme.primary;
    final isDark = AppColors.isDark(context);
    final muted = isDark ? const Color(0xCCFFFFFF) : const Color(0xCC000000);
    final actions = _tabActions(index, isSelected);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sideNavItemOuterPadding),
      child: SizedBox(
        height: extent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSelected
                ? _sideNavSelectedFill(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          // 热区要整块，不能只落在图标和文字那条线上。
          //
          // 原来 Pressable 直接包 Row，它的盒子只有内容高（约 23），而行高
          // 是 46（紧凑档）或 54——上下各有一半是"看着在这一行里、点下去
          // 没反应"。横屏侧栏本来就窄，这一个来回就是"tab 很难点"。
          // 现在给 Pressable 一个等于行高的 SizedBox，并把内边距收进热区，
          // 视觉位置一点没动，可点的却是整个高亮块。
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: extent,
                  child: Pressable(
                    semanticLabel: label,
                    selected: isSelected,
                    onTap: () => onTap(index),
                    scale: 0.97,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _sideNavItemInnerPadding,
                      ),
                      child: Row(
                        children: [
                          AnimatedIconSwitch(
                            icon: isSelected ? activeIcon : icon,
                            keyValue: isSelected ? activeIcon : icon,
                            size: 23,
                            color: isSelected ? accent : muted,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isSelected ? accent : muted,
                                fontSize: 14.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // 动作按钮不进热区，但右侧那点内边距要自己补回来。
              for (var i = 0; i < actions.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == actions.length - 1
                        ? _sideNavItemInnerPadding
                        : 0,
                  ),
                  child: actions[i],
                ),
            ],
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
