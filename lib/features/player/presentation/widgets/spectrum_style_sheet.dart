import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import '../../domain/player_spectrum_settings.dart';
import 'player_spectrum_painter.dart';

/// 频谱样式在界面上的名字。
String spectrumStyleLabel(S s, SpectrumStyle style) => switch (style) {
  SpectrumStyle.bars => s.playerSpectrumStyleBars,
  SpectrumStyle.leds => s.playerSpectrumStyleLeds,
  SpectrumStyle.dots => s.playerSpectrumStyleDots,
  SpectrumStyle.ridges => s.playerSpectrumStyleRidges,
  SpectrumStyle.steps => s.playerSpectrumStyleSteps,
};

/// 频谱样式的选择面板。
///
/// 每项都带一张实时预览：这五种样式的差别全在几何形状上，靠文字
/// （「柱状」「曲线」）选不准，看到才选得出来。预览用的是合成的固定波形，
/// 不依赖播放状态——挑样式时候很可能根本没在放歌，那时候拿不到帧，
/// 预览会是空的，而空预览等于没预览。
///
/// 只在设置页「播放」区打开。它一度也挂在均衡器页，但频谱不改声音，
/// 和调音色的那一页不是一件事；两处入口还会让同一组选项各写一份。
///
/// 面板和其它选择弹窗一样带右上角关闭键：这一层只有「选项」和「离开」两种
/// 动作，没有确定键，不给关闭键就只能下滑或点遮罩。
Future<void> showSpectrumStyleSheet(BuildContext context, WidgetRef ref) {
  final s = S.of(context);
  // 面板里不 watch：选中即 pop，不需要跟着 provider 重建；而且
  // `ref.watch` 在 build 之外调用会在调试模式下断言。
  final current = ref.read(playerSpectrumProvider).style;
  return showKoyzeSheet<void>(
    context: context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.playerSpectrumStyle,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final style in SpectrumStyle.values)
                _SpectrumStyleTile(
                  style: style,
                  label: spectrumStyleLabel(s, style),
                  selected: current == style,
                  onTap: () {
                    ref.read(playerSpectrumProvider.notifier).setStyle(style);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// 样式选择面板里的一行：左边是名字，右边是这块样式的实时预览。
class _SpectrumStyleTile extends StatefulWidget {
  const _SpectrumStyleTile({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SpectrumStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SpectrumStyleTile> createState() => _SpectrumStyleTileState();
}

class _SpectrumStyleTileState extends State<_SpectrumStyleTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  /// 合成一帧：几个固定频段的叠加，随时间缓慢起伏。
  ///
  /// 形状刻意做成「低频强、高频弱」的倾斜，跟真实音乐的能量分布一致，
  /// 这样预览里的柱高关系和播放页看到的不会差太多。
  List<double> _syntheticBands(double t, {int count = 48}) {
    final values = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final x = i / (count - 1);
      var e = 0.0;
      e += 0.95 * _bump(x, 0.04 + 0.03 * math.sin(t * 1.7), 0.10);
      e += 0.72 * _bump(x, 0.22 + 0.07 * math.sin(t * 1.1 + 1.3), 0.14);
      e += 0.48 * _bump(x, 0.46 + 0.09 * math.sin(t * 0.9 + 2.1), 0.16);
      e += 0.30 * _bump(x, 0.72 + 0.06 * math.sin(t * 1.4 + 0.5), 0.15);
      final pulse = 0.55 + 0.45 * math.pow(1 - (t * 2.4 % 1), 2).toDouble();
      values[i] = (e * pulse).clamp(0.0, 1.0);
    }
    return values;
  }

  double _bump(double x, double center, double width) {
    final d = (x - center) / width;
    return math.exp(-d * d);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final border = AppColors.cardBorder(context);

    return Semantics(
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: widget.selected
                  ? accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.selected
                    ? accent.withValues(alpha: 0.55)
                    : border.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 118,
                  height: 34,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      final t = _controller.value * 2.6;
                      return CustomPaint(
                        painter: SpectrumPainter(
                          display: _syntheticBands(t),
                          peak: _syntheticBands(t),
                          style: widget.style,
                          accent: accent,
                          trackColor: border,
                          // 预览每秒重排一百多帧，靠控制器进度当版本号，
                          // 保证 `shouldRepaint` 每次都放行。
                          revision: (_controller.value * 100000).round(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (widget.selected) Icon(Icons.check, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
