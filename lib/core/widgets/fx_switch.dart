import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/motion_tokens.dart';

/// 开关组件：静态外观与系统 Switch 一致，
/// 切换时轨道颜色与 thumb 滑动 180ms easeOutCubic 过渡。
class FxSwitch extends StatefulWidget {
  const FxSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.inactiveTrackColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeThumbColor;
  final Color? inactiveTrackColor;

  @override
  State<FxSwitch> createState() => _FxSwitchState();
}

class _FxSwitchState extends State<FxSwitch> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final accent = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    final trackOn = accent.withValues(alpha: 0.9);
    final defaultTrackOff = Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest;
    final trackOff =
        widget.inactiveTrackColor ??
        (enabled ? defaultTrackOff : defaultTrackOff.withValues(alpha: 0.6));
    final thumbOn =
        widget.activeThumbColor ?? Theme.of(context).colorScheme.onPrimary;
    final thumbOff = enabled
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    final activate = enabled ? () => widget.onChanged!(!widget.value) : null;
    final duration = motionDuration(context, const Duration(milliseconds: 180));

    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      onTap: activate,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              activate?.call();
              return null;
            },
          ),
        },
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: activate == null
                ? null
                : () {
                    _focusNode.requestFocus();
                    activate();
                  },
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: 44,
                  height: 26,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: widget.value ? trackOn : trackOff,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: AnimatedAlign(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    alignment: widget.value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: widget.value ? thumbOn : thumbOff,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
