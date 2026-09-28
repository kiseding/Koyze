import 'dart:math';

import 'package:flutter/material.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_tokens.dart';

/// 统一的底部弹窗：从底部进入 + 轻微淡入/缩放 + scrim 平滑出现。
/// 所有 showModalBottomSheet 调用点统一替换，保证 Modal Motion 一致。
///
/// 默认铺磨砂玻璃。调用方若自己包了 [GlassSurface]（或需要完全透明），
/// 传 [backgroundColor] = [Colors.transparent] 并设 [frosted] = false。
///
/// 高度上限避开状态栏 / 灵动岛：顶边至少留出 [padding.top] + [_topGap]。
Future<T?> showKoyzeSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  bool enableDrag = true,
  bool frosted = true,
}) {
  final useGlass = frosted && backgroundColor != Colors.transparent;
  // 必须用调用方 context：sheet 内部会 removeTop，padding.top 会变成 0。
  final maxHeight = koyzeSheetMaxHeight(context);
  // 调用方没自己控制高度时，横屏仍会被 Material 限制在屏幕的 9/16，
  // 选项列表会直接底部溢出。这时改成内容多高就多高，放不下再滚动。
  final compactMenu = !isScrollControlled;
  return showModalBottomSheet<T>(
    context: context,
    // 壳层迷你栏画在分支导航之上。弹窗必须走根导航，否则横屏时
    // 迷你栏会盖住睡眠定时这类弹窗的底部内容，并且拦掉点击。
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.4),
    isScrollControlled: true,
    enableDrag: enableDrag,
    requestFocus: false,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    sheetAnimationStyle: effectsAnimationStyle(),
    builder: (context) {
      final built = builder(context);
      final content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motionDuration(context, MotionDuration.normal),
        curve: MotionCurve.easeOut,
        builder: (context, t, child) => Transform.scale(
          scale: 1 - 0.02 * (1 - t),
          child: Opacity(opacity: t, child: child),
        ),
        child: compactMenu ? _CompactSheet(child: built) : built,
      );
      if (!useGlass) return content;
      return GlassSurface(
        style: AppGlassStyle.regular,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        color: backgroundColor,
        child: content,
      );
    },
  );
}

/// 弹窗可用高度：屏幕高度减去状态栏（含灵动岛）再留一点空隙。
/// [context] 必须是弹窗弹出之前的页面；sheet 内部 padding.top 会被清掉。
double koyzeSheetMaxHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final topInset = max(media.padding.top, media.viewPadding.top);
  return max(media.size.height - topInset - _topGap, 200);
}

const double _topGap = 16;

/// 短菜单按内容收缩；超过可用高度时在弹窗内部滚动，而不是底部溢出。
class _CompactSheet extends StatelessWidget {
  const _CompactSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: child,
    );
  }
}
