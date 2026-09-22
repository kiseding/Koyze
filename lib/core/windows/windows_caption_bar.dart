import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// 最大化状态。原生 `WM_SIZE` 经 `koyze/window` 回写。
final ValueNotifier<bool> windowsCaptionMaximized = ValueNotifier<bool>(false);

void applyWindowsWindowState(Object? arguments) {
  windowsCaptionMaximized.value = arguments == true;
}

/// 把系统标题栏收进客户区：页面顶栏铺到窗口上沿，右上角是自绘按钮。
class WindowsCaptionFrame extends StatelessWidget {
  const WindowsCaptionFrame({super.key, required this.child});

  final Widget child;

  static const double barHeight = 40;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(top: barHeight),
        viewPadding: media.viewPadding.copyWith(top: barHeight),
      ),
      child: Stack(
        children: [
          child,
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: barHeight,
            child: WindowsCaptionBar(),
          ),
        ],
      ),
    );
  }
}

class WindowsCaptionBar extends StatelessWidget {
  const WindowsCaptionBar({super.key});

  static const _channel = MethodChannel('koyze/window');

  @override
  Widget build(BuildContext context) {
    final iconColor = AppColors.onScaffold(context);
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => _channel.invokeMethod<void>('startDragging'),
            onDoubleTap: () => _channel.invokeMethod<void>('toggleMaximize'),
          ),
        ),
        _CaptionButton(
          icon: Icons.remove_rounded,
          color: iconColor,
          tooltip: '最小化',
          onPressed: () => _channel.invokeMethod<void>('minimize'),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: windowsCaptionMaximized,
          builder: (context, maximized, _) {
            return _CaptionButton(
              icon: maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_din_rounded,
              color: iconColor,
              tooltip: maximized ? '还原' : '最大化',
              onPressed: () => _channel.invokeMethod<void>('toggleMaximize'),
            );
          },
        ),
        _CaptionButton(
          icon: Icons.close_rounded,
          color: iconColor,
          tooltip: '关闭',
          close: true,
          onPressed: () => _channel.invokeMethod<void>('closeWindow'),
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.close && _hover
        ? const Color(0xFFE81123)
        : _hover
        ? widget.color.withValues(alpha: 0.08)
        : Colors.transparent;
    final iconColor = widget.close && _hover ? Colors.white : widget.color;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: SizedBox(
            width: 46,
            height: WindowsCaptionFrame.barHeight,
            child: ColoredBox(
              color: background,
              child: Icon(widget.icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
