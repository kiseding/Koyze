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
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final scope = RootTabScope.maybeOf(context);
    final accent = AppColors.accentOf(context);
    final isDark = AppColors.isDark(context);
    final idle = AppColors.secondaryText(context);
    const style = _kTextStyle;

    // 胶囊底：强调色只用在这一小块上。导航是结构，但「你现在在哪」算关键
    // 元素——这是整条栏里唯一带颜色的地方。
    final pillFill = accent.withValues(alpha: isDark ? 0.20 : 0.13);
    final pillEdge = accent.withValues(alpha: isDark ? 0.26 : 0.18);

    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
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
                  accent: accent,
                  idle: idle,
                  pillFill: pillFill,
                  pillEdge: pillEdge,
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
    required Color accent,
    required Color idle,
    required Color pillFill,
    required Color pillEdge,
    required TextStyle style,
    required VoidCallback? onTap,
  }) {
    final spread = _spread(index);
    final expandedWidth = _kTextLeft + textWidth + _kRightPadding;
    final width =
        _kCollapsedWidth + (expandedWidth - _kCollapsedWidth) * spread;
    final fill = spread.clamp(0.0, 1.0);
    final opacity = _textOpacity(index).clamp(0.0, 1.0);

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
              // 胶囊底随展开淡入，收起时不留一个空壳。
              Positioned.fill(
                child: Opacity(
                  opacity: fill,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: pillFill,
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      border: Border.all(color: pillEdge, width: 0.8),
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
                        selected ? _iconsSelected[index] : _icons[index],
                        key: ValueKey<bool>(selected),
                        size: _kIconSize,
                        color: Color.lerp(idle, accent, fill),
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
                        style: style.copyWith(color: accent),
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
