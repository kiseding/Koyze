import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';

/// 带按压缩放的 IconButton：按压时图标微缩 0.9 + 透明度降低，
/// 110ms easeOutCubic，与 Pressable 手感一致。
/// 全项目图标按钮统一使用，替代裸 IconButton。
class FxIconButton extends StatefulWidget {
  const FxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.padding,
    this.iconSize,
    this.visualDensity,
    this.constraints,
    this.color,
    this.disabledColor,
    this.highlightColor,
    this.splashColor,
    this.focusColor,
    this.hoverColor,
    this.focusNode,
    this.autofocus = false,
    this.enableFeedback,
    this.isSelected,
    this.selectedIcon,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final VisualDensity? visualDensity;
  final BoxConstraints? constraints;
  final Color? color;
  final Color? disabledColor;
  final Color? highlightColor;
  final Color? splashColor;
  final Color? focusColor;
  final Color? hoverColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool? enableFeedback;
  final bool? isSelected;
  final Widget? selectedIcon;

  @override
  State<FxIconButton> createState() => _FxIconButtonState();
}

class _FxIconButtonState extends State<FxIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onPressed == null
          ? null
          : (_) {
              setState(() => _pressed = true);
            },
      onTapUp: widget.onPressed == null
          ? null
          : (_) => setState(() => _pressed = false),
      onTapCancel: widget.onPressed == null
          ? null
          : () => setState(() => _pressed = false),
      child: IconButton(
        icon: AnimatedScale(
          scale: _pressed ? 0.9 : 1,
          duration: motionDuration(context, const Duration(milliseconds: 110)),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.85 : 1,
            duration: motionDuration(
              context,
              const Duration(milliseconds: 110),
            ),
            child: widget.isSelected == true && widget.selectedIcon != null
                ? widget.selectedIcon!
                : widget.icon,
          ),
        ),
        onPressed: widget.onPressed,
        tooltip: widget.tooltip,
        padding: widget.padding,
        iconSize: widget.iconSize,
        visualDensity: widget.visualDensity,
        constraints: widget.constraints,
        color: widget.color,
        disabledColor: widget.disabledColor,
        highlightColor: widget.highlightColor,
        splashColor: widget.splashColor,
        focusColor: widget.focusColor,
        hoverColor: widget.hoverColor,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enableFeedback: widget.enableFeedback,
        isSelected: widget.isSelected,
        selectedIcon: widget.selectedIcon,
      ),
    );
  }
}
