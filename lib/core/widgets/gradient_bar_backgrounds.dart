import 'package:flutter/material.dart';

/// 顶栏背景：栏上 [fadeStart] 比例透明度从 0% 缓变到 3%，剩余部分从 3%
/// 渐变到 100% 透明。栏上文字几乎不透明、清晰，列表滚入栏底时自然透出。
/// 配合 `AppBar.flexibleSpace` 或榜单 tab 悬浮 header 使用。
/// 注意：`AppBar.flexibleSpace` 收到的约束是 loose 的，无 child 时必须撑满，
/// 否则装饰会被压缩成 0×0 而完全不可见。
class GradientAppBarBackground extends StatelessWidget {
  const GradientAppBarBackground({
    super.key,
    required this.background,
    this.minAlpha = 0.0,
    this.child,
    this.fadeStart = 0.87,
  });

  /// 栏底部露出的背景色。
  final Color background;

  /// 渐变最透处的透明度（0~1）。
  final double minAlpha;

  /// 可选子内容（如自定义标题栏），置于渐变背景之上。
  final Widget? child;

  /// 渐变起始位置（0~1）：此前为 0%→5% 透明度缓变段，之后为 5%→100% 段。
  final double fadeStart;

  @override
  Widget build(BuildContext context) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            background,
            background.withValues(alpha: 0.97),
            background.withValues(alpha: minAlpha),
          ],
          // 上 87%：透明度 0%→3%（alpha 1→0.97），下 13%：3%→100%。
          stops: [0.0, fadeStart, 1.0],
        ),
      ),
      child: child,
    );
    if (child != null) {
      return gradient;
    }
    // 无 child（如 AppBar.flexibleSpace）时撑满可用区域，
    // 避免 loose 约束下被压缩成 0×0 导致渐变不可见。
    return SizedBox.expand(child: gradient);
  }
}

/// 底栏背景：栏顶部 13% 透明度从 100% 渐变到 3%，下方 87% 从 3% 渐变到 0%。
/// 包裹分页栏等底部控件使用。
class GradientBottomBarBackground extends StatelessWidget {
  const GradientBottomBarBackground({
    super.key,
    required this.background,
    required this.child,
    this.minAlpha = 0.0,
  });

  /// 栏顶部露出的背景色。
  final Color background;

  /// 渐变最透处的透明度（0~1）。
  final double minAlpha;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            background.withValues(alpha: minAlpha),
            background.withValues(alpha: 0.97),
            background,
          ],
          // 顶部 13%：透明度 100%→3%，下方 87%：3%→0%。
          stops: const [0.0, 0.13, 1.0],
        ),
      ),
      child: child,
    );
  }
}
