// 文件说明：根导航的图标条。未选中的栏目只留一个图标，选中的那一项向右
// 生长成胶囊，把名字显出来。
// 技术要点：
// - 点击切换：四颗格子共用同一个 AnimationController，从每一颗此刻的真实
//   展开度插值过去——被打断后接着走，不会先补满再收缩。
// - 手势滑动：直接跟页面的绝对坐标（[rootBranchDragPosition]），滑过几页
//   就跟几页，不在「一页」处截断。
// - 图标钉在胶囊左侧固定位置（左内边距 14 + 22 的一半 = 25，恰好是收起态
//   50 宽的中心），宽度只往右长。图标不动、文字被「挤」出来，重心才是稳的。
// - 展开用 easeOutBack（末尾过冲约 10% 再落回），收缩用 easeOutCubic（不弹），
//   一收一放有节奏，但不会两头一起抖。
// - 文字从图标方向滑出并淡入，裁剪边界随宽度推进，读起来是「推出来」的。

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_colors.dart';
import '../theme/glass_config.dart';
import '../../l10n/app_strings.dart';
import 'pressable.dart';

/// 手势 / 补间进行中的**页面绝对坐标**；null = 静止（胶囊跟选中态走）。
///
/// 用绝对坐标而不是「朝相邻页的进度 0..1」，是因为连续快甩时手指会在上一次
/// 补间没跑完时又起手：`_position` 可能已经越过整页（例如 1.2），而路由还停
/// 在 0。进度式把值钳在 1，胶囊就冻在「下一个 tab 已张开」那一帧不再跟随，
/// 直到落定才跳过去——看起来就是切换动效被省略了。绝对坐标没有这个上限，
/// tab 条自己按 `floor/frac` 映射到相邻两颗，滑几页就跟几页。
///
/// 定义在 tab 条这一侧（而不是壳层）避免 core→features 的反向依赖：壳层与
/// 手势容器本来就 import 本文件。
final rootBranchDragPosition = ValueNotifier<double?>(null);

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

  /// 动画起点：每一颗在起播那一帧的**实际展开度**。
  ///
  /// 不用「上一个 tab 下标」是因为连续快速切换时动画会被打断：只记下标的话，
  /// 新动画默认上一颗已经张满，会先把它瞬间补到 1 再收缩——中间那颗看起来
  /// 就是跳了一下。记每颗的真实展开度，新动画从眼前的中间态接着走。
  List<double> _startSpread = const [1, 0, 0, 0];
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
      _to = next;
      _startSpread = _restingSpread(_to);
      _controller.value = 1;
      return;
    }
    if (next == _to) return;

    // 先把眼前这一帧的真实展开度存下来，再从它起播。
    _startSpread = [
      for (var i = 0; i < _labels.length; i++) _spreadFor(i),
    ];
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
      _to = target;
      _startSpread = _restingSpread(target);
    });
    _controller.value = 1;
  }

  /// 静止态：只有 [index] 张满，其余收起。
  List<double> _restingSpread(int index) => [
    for (var i = 0; i < _labels.length; i++) i == index ? 1.0 : 0.0,
  ];

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
  ///
  /// 从 [_startSpread] 里那一颗的真实展开度插值，所以动画被打断后再起播是
  /// 连续的：不会先把上一颗补满再收。
  double _spread(int index) {
    final t = _controller.value;
    if (t >= 1) return index == _to ? 1.0 : 0.0;
    final from = index < _startSpread.length ? _startSpread[index] : 0.0;
    final to = index == _to ? 1.0 : 0.0;
    if (to > from) {
      return from + (to - from) * MotionCurve.emphasize.transform(t);
    }
    if (to < from) {
      return from + (to - from) * Curves.easeOutCubic.transform(t);
    }
    return to;
  }

  /// 手势进行中的坐标：页面停在 [head] 与下一颗之间，[frac] 是后者吃到的
  /// 比例。绝对坐标可能为负或超过一圈，取模后仍然是正确的一对。
  ({int head, double frac})? get _dragCursor {
    final p = rootBranchDragPosition.value;
    if (p == null) return null;
    final count = _labels.length;
    if (count == 0) return null;
    final base = p.floor();
    final head = base % count;
    return (head: head, frac: (p - base).clamp(0.0, 1.0));
  }

  /// 滑动进行中的插值：胶囊从当前页连续让位给下一页。
  ///
  /// 直接跟页面坐标走，所以一次手势滑过几页就跟几页；点击触发的补齐动画
  /// 照旧走 [AnimationController]，两者不同时发生——点击动画由 goBranch
  /// 驱动，坐标在那之前已经清空。
  double _spreadFor(int index) {
    final cursor = _dragCursor;
    if (cursor != null) {
      final count = _labels.length;
      if (index == cursor.head) return 1 - cursor.frac;
      if (index == (cursor.head + 1) % count) return cursor.frac;
      return 0;
    }
    return _spread(index);
  }

  /// 文字透明度跟着展开度走，而不是自成一条时间线。
  ///
  /// 手势和点击两条路径共用这一条规则：胶囊张到 [_kTextFade] 的起点之后文字
  /// 才开始出现，收缩时同理退场。这样无论动画怎么被打断，文字都不会先于
  /// 宽度出现或消失。
  double _textOpacityFor(int index) {
    return _kTextFade.transform(_spreadFor(index).clamp(0.0, 1.0));
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
    //
    // 但「结构」不等于「实心」：设置里的界面不透明度拖到 60%，这一栏也得
    // 跟着透（见下面的 ValueListenableBuilder）。这里只负责与不透明度无关
    // 的那部分样式。
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
      child: ValueListenableBuilder<double>(
        // 药丸底色跟着「界面不透明度」走，滑杆拖动时要当帧重画。
        valueListenable: GlassEffectConfig.surfaceOpacityListenable,
        builder: (context, _, _) => ListenableBuilder(
          // 胶囊的两条时间线：点击切换的 [AnimationController]，和手势滑动
          // 的实时进度。任何一个变动都要重算展开度。
          listenable: Listenable.merge([
            _controller,
            rootBranchDragPosition,
          ]),
          builder: (context, _) {
            final pillFill = GlassEffectConfig.withSurfaceOpacity(
              isDark ? const Color(0x28FFFFFF) : Colors.white,
            );
            final pillEdge = GlassEffectConfig.withSurfaceOpacity(
              isDark ? const Color(0x24FFFFFF) : const Color(0x12000000),
            );
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
                          scale: animation.drive(Tween(begin: 0.72, end: 1.0)),
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
