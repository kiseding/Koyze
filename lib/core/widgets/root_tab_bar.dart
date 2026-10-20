// 文件说明：根导航的图标条。未选中的栏目只留一个图标，选中的那一项向右
// 生长成胶囊，把名字显出来。
// 技术要点：
// - 四个格子共用同一个 AnimationController。展开和收缩是同一条时间线的两端，
//   所以看上去像一块橡皮被推向另一边，而不是两个格子各播各的动画。
// - 图标钉在胶囊左侧固定位置（左内边距 14 + 22 的一半 = 25，恰好是收起态
//   50 宽的中心），宽度只往右长。图标不动、文字被「挤」出来，重心才是稳的。
// - 展开用 easeOutBack（末尾过冲约 10% 再落回），收缩用 easeOutCubic（不弹），
//   一收一放有节奏，但不会两头一起抖。
// - 文字从图标方向滑出并淡入，裁剪边界随宽度推进，读起来是「推出来」的。

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../../l10n/app_strings.dart';
import 'pressable.dart';

/// 手势 / 点击切换 tab 的实时进度：-1..1。
///
/// 0 = 静止在选中页；正值表示正在滑向下一个 tab（页面向左），负值表示
/// 滑向上一个。定义在 tab 条这一侧（而不是壳层）避免 core→features 的
/// 反向依赖：壳层与手势容器本来就 import 本文件。
final rootBranchDrag = ValueNotifier<double>(0);

/// 滑动 / 点击动画的实际目标 tab。
///
/// 手势拖动时为 null（方向由进度符号决定，目标是相邻项）；点击远处的
/// tab 时是那个 tab 的下标——跳两页的动画同样只滑一屏，胶囊必须直接
/// 在「起点 → 目标」之间过渡，而不是先冒出中间那颗再跳过去。
final rootBranchDragTarget = ValueNotifier<int?>(null);

/// 一次切换「落定」时的目标 tab。
///
/// 位移动画（手势滑入或点击跳页）结束、页面已经到位时写入，tab 条据此把
/// 选中态直接钉到目标上。没有这一步的话：拖动进度归零时 `_to` 还停在旧
/// tab（要等路由真的切过去才更新），胶囊会先弹回旧 tab，再从头播一遍展开
/// 动画——看起来就是切完之后又「跳」了一下。
final rootBranchSettle = ValueNotifier<int?>(null);

/// 把根 tab 的选中态与切换回调传给页面顶部的 tab 条。
class RootTabScope extends InheritedWidget {
  const RootTabScope({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required super.child,
  });

  final int selectedIndex;
  final ValueChanged<int> onTap;

  static RootTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RootTabScope>();
  }

  /// 只读一次，不建立依赖。给 [FrostedTabHeader.extent] 这类只要知道
  /// 「有没有壳层」的地方用——它们不关心选中项，不该跟着切 tab 重建。
  static RootTabScope? readOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<RootTabScope>();
  }

  @override
  bool updateShouldNotify(RootTabScope oldWidget) {
    // 只比选中项：onTap 每帧都是新闭包，比它会让整棵页面树每帧重建。
    // 旧闭包指向同一个 navigationShell，继续用也不会切错分支。
    return selectedIndex != oldWidget.selectedIndex;
  }
}

/// tab 条总高，也就是胶囊的高度。
const double kRootTabBarHeight = 40;

/// 收起态宽度：一个 40 高的圆形热区。图标中心落在 25 上。
const double _kCollapsedWidth = 50;
const double _kIconSize = 22;
const double _kIconLeft = 14;
const double _kIconTextGap = 7;
const double _kItemGap = 4;
const double _kRightPadding = 14;
const double _kTextSize = 12.5;

/// 文字左边缘：紧贴图标右侧。
const double _kTextLeft = _kIconLeft + _kIconSize + _kIconTextGap;

const List<IconData> _icons = [
  Icons.home_outlined,
  Icons.leaderboard_outlined,
  Icons.library_music_outlined,
  Icons.settings_outlined,
];

const List<IconData> _iconsSelected = [
  Icons.home_rounded,
  Icons.leaderboard_rounded,
  Icons.library_music_rounded,
  Icons.settings_rounded,
];

/// 文字进场：收起时先不动，等胶囊张开到一半再淡入，避免在窄缝里被裁成碎片。
const Curve _kTextFade = Interval(0.42, 1, curve: Curves.easeOut);

/// 只用来量宽度的字体样式；颜色在 build 时补，不影响度量。
const TextStyle _kTextStyle = TextStyle(
  fontSize: _kTextSize,
  height: 1,
  letterSpacing: 0.1,
  fontWeight: FontWeight.w700,
);

class RootTabBar extends StatefulWidget {
  const RootTabBar({super.key, this.height = kRootTabBarHeight});

  final double height;

  @override
  State<RootTabBar> createState() => _RootTabBarState();
}

class _RootTabBarState extends State<RootTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionDuration.normal,
  );

  /// 动画的起点与终点。第三方栏目（既不是 from 也不是 to）保持 0。
  int _from = 0;
  int _to = 0;
  bool _ready = false;

  List<String> _labels = const ['', '', '', ''];
  List<double> _textWidths = const [0, 0, 0, 0];

  @override
  void initState() {
    super.initState();
    rootBranchSettle.addListener(_commitSettle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final s = S.of(context);
    _labels = [s.home, s.charts, s.playlists, s.settings];
    const style = _kTextStyle;
    _textWidths = [
      for (final label in _labels) _measure(context, label, style),
    ];

    final next = (RootTabScope.maybeOf(context)?.selectedIndex ?? 0).clamp(
      0,
      3,
    );
    if (!_ready) {
      _ready = true;
      _from = _to = next;
      _controller.value = 1;
      return;
    }
    if (next == _to) return;

    _from = _to;
    _to = next;
    final duration = motionDuration(context, MotionDuration.normal);
    _controller.duration = duration;
    if (duration == Duration.zero) {
      // 关闭动效时不要留一个「动画到一半」的中间态：宽度、文字透明度全部
      // 直接取终值。
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    rootBranchSettle.removeListener(_commitSettle);
    _controller.dispose();
    super.dispose();
  }

  /// 位移已经落到目标页：把选中态钉死在那儿，不要再补一遍展开动画。
  void _commitSettle() {
    final next = rootBranchSettle.value;
    if (next == null) return;
    // 先清标记：赋值会同步再通知一次，靠这个判空退出重入。
    rootBranchSettle.value = null;
    if (!mounted) return;
    final target = next.clamp(0, _labels.length - 1);
    if (target == _to && _controller.value == 1) return;
    setState(() {
      _from = target;
      _to = target;
    });
    _controller.value = 1;
  }


  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble();
  }

  /// 展开度。展开项带过冲，收缩项不带——两头一起弹会显得毛躁。
  double _spread(int index) {
    if (_from == _to) return index == _to ? 1 : 0;
    final t = _controller.value;
    if (index == _to) return MotionCurve.emphasize.transform(t);
    if (index == _from) return 1 - Curves.easeOutCubic.transform(t);
    return 0;
  }

  double _textOpacity(int index) {
    if (_from == _to) return index == _to ? 1 : 0;
    final t = _controller.value;
    if (index == _to) return _kTextFade.transform(t);
    if (index == _from) return 1 - Curves.easeIn.transform(t);
    return 0;
  }

  /// 滑动进行中的插值：胶囊从当前选中项连续让位给相邻项。
  ///
  /// 手势进度 rootBranchDrag 决定「另一颗」是谁、吃多少展开度；点击
  /// 触发的补齐动画照旧走 [AnimationController]，两者不同时发生——
  /// 点击动画由 [_animating]/goBranch 驱动，drag 在那之前已归零。
  ({int other, double t})? get _dragSplit {
    final p = rootBranchDrag.value;
    if (p.abs() < 0.005) return null;
    final count = _labels.length;
    final current = _to.clamp(0, count - 1);
    // 优先用动画的真实目标（点击跳两页时直接过渡到目标页）；纯手势
    // 拖动没有预定目标，按方向取相邻项。
    final other =
        rootBranchDragTarget.value ??
        (p > 0
            ? (current + 1) % count
            : (current + count - 1) % count);
    return (other: other, t: p.abs().clamp(0.0, 1.0));
  }

  double _spreadFor(int index) {
    final split = _dragSplit;
    if (split != null) {
      if (index == _to) return 1 - split.t;
      if (index == split.other) return split.t;
      return 0;
    }
    return _spread(index);
  }

  double _textOpacityFor(int index) {
    final split = _dragSplit;
    if (split != null) {
      if (index == _to) return 1 - split.t;
      if (index == split.other) return split.t;
      return 0;
    }
    return _textOpacity(index);
  }

  @override
  Widget build(BuildContext context) {
    final scope = RootTabScope.maybeOf(context);
    final isDark = AppColors.isDark(context);
    final onSurface = AppColors.onScaffold(context);
    final idle = AppColors.secondaryText(context);
    const style = _kTextStyle;

    // 药丸沿用原来的中性面：浅色纯白，深色一层薄白。导航是结构，不蘸
    // 强调色——换主题时这条栏不该跟着变。
    final pillFill = isDark ? const Color(0x28FFFFFF) : Colors.white;
    final pillEdge = isDark
        ? const Color(0x24FFFFFF)
        : const Color(0x12000000);
    final pillShadow = isDark
        ? null
        : const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ];

    return SizedBox(
      height: widget.height,
      child: ListenableBuilder(
        // 胶囊的两条时间线：点击切换的 [AnimationController]，和手势滑动
        // 的实时进度。任何一个变动都要重算展开度。
        listenable: Listenable.merge([_controller, rootBranchDrag]),
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _labels.length; i++) ...[
                if (i > 0) const SizedBox(width: _kItemGap),
                _tab(
                  context,
                  index: i,
                  label: _labels[i],
                  textWidth: _textWidths[i],
                  selected: _to == i,
                  onSurface: onSurface,
                  idle: idle,
                  pillFill: pillFill,
                  pillEdge: pillEdge,
                  pillShadow: pillShadow,
                  style: style,
                  onTap: scope == null ? null : () => scope.onTap(i),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required int index,
    required String label,
    required double textWidth,
    required bool selected,
    required Color onSurface,
    required Color idle,
    required Color pillFill,
    required Color pillEdge,
    required List<BoxShadow>? pillShadow,
    required TextStyle style,
    required VoidCallback? onTap,
  }) {
    final spread = _spreadFor(index);
    final expandedWidth = _kTextLeft + textWidth + _kRightPadding;
    final width =
        _kCollapsedWidth + (expandedWidth - _kCollapsedWidth) * spread;
    final fill = spread.clamp(0.0, 1.0);
    final opacity = _textOpacityFor(index).clamp(0.0, 1.0);
    // 实心/描边跟着展开度走，而不是等 selected 翻面：否则图标要到位之后才
    // 单独播一次「淡入 + 从 0.72 弹到 1」，切完还要再跳一下。
    final filled = spread >= 0.5;

    return Pressable(
      key: ValueKey<String>('root-tab-$index'),
      semanticLabel: label,
      selected: selected,
      // 宽度本身在动，再叠一层缩放会像两套动画打架；只留很轻的按压回弹。
      scale: 0.95,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.height / 2),
          child: Stack(
            children: [
              // 药丸随展开淡入，收起时不留一个空壳。
              Positioned.fill(
                child: Opacity(
                  opacity: fill,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: pillFill,
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      border: Border.all(color: pillEdge, width: 0.8),
                      boxShadow: pillShadow,
                    ),
                  ),
                ),
              ),
              // 图标钉在 25 的中心：收起态是热区中心，展开后仍在左侧视觉
              // 中心，切换时不会横向跳。
              Positioned(
                left: _kIconLeft,
                top: (widget.height - _kIconSize) / 2,
                width: _kIconSize,
                height: _kIconSize,
                child: Transform.scale(
                  scale: 1 + 0.08 * fill,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: motionDuration(context, MotionDuration.normal),
                      switchInCurve: MotionCurve.emphasize,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: animation.drive(
                            Tween(begin: 0.72, end: 1.0),
                          ),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        filled ? _iconsSelected[index] : _icons[index],
                        key: ValueKey<bool>(filled),
                        size: _kIconSize,
                        color: Color.lerp(idle, onSurface, fill),
                      ),
                    ),
                  ),
                ),
              ),
              // 文字：从图标方向滑出。收起时左移 6，展开到位时回到 0。
              Positioned(
                left: _kTextLeft,
                top: 0,
                bottom: 0,
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(-6 * (1 - fill), 0),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: style.copyWith(color: onSurface),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
