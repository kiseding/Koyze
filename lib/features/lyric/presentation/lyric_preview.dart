// 文件说明：歌词设置的实时预览。
//
// 这个组件必须用和 [LyricView] 完全一样的公式（模糊半径、字号层级、间距），
// 否则设置页调完进播放页会发现「不是刚才那样」。所以它直接复用
// [lyricBlurSigmaFor] 与同一套字号比例，只在外面套一层卡片。

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'lyric_effects.dart';

class LyricPreview extends StatefulWidget {
  const LyricPreview({
    super.key,
    required this.scale,
    required this.blur,
    required this.showRoman,
    required this.showTranslation,
    this.entrance = LyricEntranceStyle.fade,
    this.fontFamily,
  });

  final double scale;

  /// 0~1 的模糊档位，和设置里那根滑杆是同一个值。
  final double blur;
  final bool showRoman;
  final bool showTranslation;
  final LyricEntranceStyle entrance;
  final String? fontFamily;

  @override
  State<LyricPreview> createState() => _LyricPreviewState();
}

class _LyricPreviewState extends State<LyricPreview> {
  /// 预览里「当前行」固定在第 2 行（0 基），上下各有两行。
  static const int _currentIndex = 2;

  static const List<(String, String?, String?)> _lines = [
    ('夜に駆ける', null, null),
    ('沈むように溶けてゆくように', 'shizumu you ni', '像要沉下去一般'),
    ('揺れた恋と愛の渦の中', 'yureta koi to ai no uzu', '在摇晃的恋与爱的漩涡中'),
    ('思い出だけが邪魔をする', 'omoide dake ga jama o suru', '只有回忆在碍事'),
    ('このまま忘れてしまえたら', null, '若能就这样忘掉'),
  ];

  /// 换歌 / 换字体时让预览整体重放一次入场，用户能立刻看到那个动画。
  Object _playKey = 0;

  @override
  void didUpdateWidget(covariant LyricPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entrance != widget.entrance ||
        oldWidget.fontFamily != widget.fontFamily) {
      _playKey = _playKey.hashCode + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 只带字体族：字号、颜色每行都不一样，在行内 copyWith 出来。
    final baseStyle = TextStyle(fontFamily: widget.fontFamily);

    return Container(
      // 高度跟着内容走：5 行 × 每种字号的组合在不同 scale 下差很多，写死一个
      // 高度总有一档会溢出（放大到 135% 就装不下了）。
      padding: const EdgeInsets.symmetric(vertical: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder(context), width: 0.8),
      ),
      child: Stack(
        children: [
          // 中间一条淡淡的参考线，说明「当前行」在哪。
          Positioned.fill(child: CustomPaint(painter: _CenterGuidePainter())),
          Center(
            child: LyricEntrance(
              style: widget.entrance,
              playKey: _playKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _lines.length; i++)
                    _PreviewLine(
                      text: _lines[i].$1,
                      roman: _lines[i].$2,
                      translation: _lines[i].$3,
                      distance: (i - _currentIndex).abs(),
                      scale: widget.scale,
                      blur: widget.blur,
                      showRoman: widget.showRoman,
                      showTranslation: widget.showTranslation,
                      baseStyle: baseStyle,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({
    required this.text,
    required this.roman,
    required this.translation,
    required this.distance,
    required this.scale,
    required this.blur,
    required this.showRoman,
    required this.showTranslation,
    required this.baseStyle,
  });

  final String text;
  final String? roman;
  final String? translation;
  final int distance;
  final double scale;
  final double blur;
  final bool showRoman;
  final bool showTranslation;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final isCurrent = distance == 0;
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);

    // 与列表一致的「离得越远越淡」，只是预览里只有 5 行，跨度看起来更紧凑。
    final fade = isCurrent ? 1.0 : (1.0 - (distance - 1) * 0.2).clamp(0.2, 1.0);
    final color = (isCurrent ? accent : primary.withValues(alpha: 0.35))
        .withValues(alpha: (isCurrent ? 1.0 : 0.35) * fade);
    final fontSize = (isCurrent ? 20.0 : 16.0) * scale;
    final sigma = lyricBlurSigmaFor(distance: distance, amount: blur);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: (isCurrent ? 7 : 4) * scale),
      child: lyricBlurred(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: baseStyle.copyWith(
                color: color,
                fontSize: fontSize,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                height: 1.15,
              ),
            ),
            if (showRoman && roman != null)
              Text(
                roman!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle.copyWith(
                  color:
                      (isCurrent
                              ? secondary
                              : secondary.withValues(alpha: 0.55))
                          .withValues(alpha: fade * 0.85),
                  fontSize: (isCurrent ? 11.5 : 10.0) * scale,
                  fontWeight: FontWeight.normal,
                  height: 1.15,
                ),
              ),
            if (showTranslation && translation != null)
              Text(
                translation!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: baseStyle.copyWith(
                  color:
                      (isCurrent
                              ? secondary
                              : secondary.withValues(alpha: 0.55))
                          .withValues(alpha: fade),
                  fontSize: (isCurrent ? 13.0 : 11.0) * scale,
                  fontWeight: FontWeight.normal,
                  height: 1.15,
                ),
              ),
          ],
        ),
        sigma,
      ),
    );
  }
}

/// 当前行位置的虚线参考。
class _CenterGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.05);
    final y = size.height / 2;
    const dash = 4.0;
    const gap = 5.0;
    var x = 12.0;
    while (x < size.width - 12) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _CenterGuidePainter oldDelegate) => false;
}
