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
    // 窗口圆角是 24。右上角按钮再往里收，避免被圆弧裁掉。
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _channel.invokeMethod<void>('startDragging'),
              onDoubleTap: () => _channel.invokeMethod<void>('toggleMaximize'),
            ),
          ),
          _CaptionButton(
            glyph: _CaptionGlyph.minimize,
            color: iconColor,
            label: '最小化',
            onPressed: () => _channel.invokeMethod<void>('minimize'),
          ),
          const SizedBox(width: 2),
          ValueListenableBuilder<bool>(
            valueListenable: windowsCaptionMaximized,
            builder: (context, maximized, _) {
              return _CaptionButton(
                glyph: maximized
                    ? _CaptionGlyph.restore
                    : _CaptionGlyph.maximize,
                color: iconColor,
                label: maximized ? '还原' : '最大化',
                onPressed: () => _channel.invokeMethod<void>('toggleMaximize'),
              );
            },
          ),
          const SizedBox(width: 2),
          _CaptionButton(
            glyph: _CaptionGlyph.close,
            color: iconColor,
            label: '关闭',
            close: true,
            onPressed: () => _channel.invokeMethod<void>('closeWindow'),
          ),
        ],
      ),
    );
  }
}

enum _CaptionGlyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.glyph,
    required this.color,
    required this.label,
    required this.onPressed,
    this.close = false,
  });

  final _CaptionGlyph glyph;
  final Color color;
  final String label;
  final VoidCallback onPressed;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hovered = _hover || _pressed;
    // 最小化/最大化不再铺灰底。那层灰底和系统标题按钮的悬停带叠在一起，
    // 看起来就是一条灰条。关闭仍用红色，避免和普通悬停混在一起。
    final background = widget.close && hovered
        ? AppColors.error
        : Colors.transparent;
    final iconColor = widget.close && hovered
        ? Colors.white
        : widget.color.withValues(alpha: hovered ? 0.55 : 1);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: _pressed ? 0.92 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 36,
              height: 28,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: _CaptionGlyphPainter(
                  glyph: widget.glyph,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter({required this.glyph, required this.color});

  final _CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final center = Offset(size.width / 2, size.height / 2);
    switch (glyph) {
      case _CaptionGlyph.minimize:
        canvas.drawLine(
          center + const Offset(-5, 0),
          center + const Offset(5, 0),
          paint,
        );
      case _CaptionGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: 10, height: 10),
            const Radius.circular(2.2),
          ),
          paint,
        );
      case _CaptionGlyph.restore:
        final back = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + const Offset(1.6, -1.6),
            width: 8,
            height: 8,
          ),
          const Radius.circular(1.8),
        );
        final front = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + const Offset(-1.6, 1.6),
            width: 8,
            height: 8,
          ),
          const Radius.circular(1.8),
        );
        canvas.drawRRect(back, paint);
        canvas.drawRRect(front, paint);
      case _CaptionGlyph.close:
        canvas.drawLine(
          center + const Offset(-4.2, -4.2),
          center + const Offset(4.2, 4.2),
          paint,
        );
        canvas.drawLine(
          center + const Offset(4.2, -4.2),
          center + const Offset(-4.2, 4.2),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _CaptionGlyphPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.color != color;
  }
}
