import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/glass_config.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../../player/presentation/player_provider.dart';
import 'settings_provider.dart';

/// 「界面质感」面板：不透明度 + 虚化两根滑杆。
///
/// 以前这两项直接摆在设置列表里，拖的时候只能看周围的分区卡片。可设置页的
/// 卡片是 `solidBehind` 的（背后只有页面底色），虚化那一根在那里拖到底也
/// 看不出任何变化——等于盲调。现在合成一行、点开一个面板，面板顶部放一块
/// 用当前封面渲染的玻璃条：拖动时它同步变透、变糊，两档各自在改什么一眼
/// 就能看见。交互和全屏播放器那张背景面板保持一致。
Future<void> showGlassEffectSheet(BuildContext context) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const GlassEffectSheet(),
  );
}

class GlassEffectSheet extends ConsumerWidget {
  const GlassEffectSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final opacity = ref.watch(glassOpacityProvider);
    final blur = ref.watch(glassBlurProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.glassEffect,
          subtitle: s.glassEffectHint,
          onClose: () => Navigator.pop(context),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            children: [
              const _GlassPreview(),
              const SizedBox(height: 18),
              _GlassEffectSlider(
                label: s.glassOpacity,
                value: opacity,
                min: GlassEffectConfig.minSurfaceOpacity,
                divisions: 14,
                onChanged: (next) {
                  // 立刻写进静态配置，预览和整页的玻璃面同一帧跟着变。
                  GlassEffectConfig.setSurfaceOpacity(next);
                  ref.read(glassOpacityProvider.notifier).setOpacity(next);
                },
                onChangeEnd: () =>
                    ref.read(glassOpacityProvider.notifier).flush(),
              ),
              const SizedBox(height: 10),
              _GlassEffectSlider(
                label: s.glassBlur,
                value: blur,
                min: GlassEffectConfig.minSurfaceBlur,
                divisions: 20,
                onChanged: (next) {
                  GlassEffectConfig.setSurfaceBlur(next);
                  ref.read(glassBlurProvider.notifier).setBlur(next);
                },
                onChangeEnd: () => ref.read(glassBlurProvider.notifier).flush(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    const opacityDefault = GlassEffectConfig
                        .defaultSurfaceOpacity;
                    const blurDefault = GlassEffectConfig.defaultSurfaceBlur;
                    GlassEffectConfig.setSurfaceOpacity(opacityDefault);
                    GlassEffectConfig.setSurfaceBlur(blurDefault);
                    ref
                        .read(glassOpacityProvider.notifier)
                        .setOpacity(opacityDefault);
                    ref.read(glassOpacityProvider.notifier).flush();
                    ref
                        .read(glassBlurProvider.notifier)
                        .setBlur(blurDefault);
                    ref.read(glassBlurProvider.notifier).flush();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.mutedText(context),
                  ),
                  child: Text(
                    s.resetToDefault,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 预览：当前封面 + 一条真正的玻璃迷你播放条。
///
/// 玻璃条走的是页面里同一个 [GlassSurface]，所以不透明度和虚化没有另算一套
/// 近似值——面板里看到的就是顶栏、迷你栏上会发生的事。
class _GlassPreview extends ConsumerWidget {
  const _GlassPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final music = ref.watch(currentMusicProvider);
    final cover = music?.artwork;
    final accent = AppColors.accentOf(context);
    final foreground = AppColors.onScaffold(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null && cover.isNotEmpty)
              ArtworkImage(cover, fit: BoxFit.cover, cacheWidth: 720)
            else
              const _PreviewBackdrop(),
            // 压一层很浅的暗角，浅色封面上的白字才立得住。
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x22000000), Color(0x55000000)],
                ),
              ),
            ),
            Center(
              child: GlassSurface(
                style: AppGlassStyle.regular,
                // 必须真的采样背后的封面，否则「虚化」这根滑杆在预览里
                // 拖到哪都不会有反应。
                backdrop: true,
                solidBehind: false,
                borderRadius: BorderRadius.circular(14),
                border: Border.fromBorderSide(AppGlass.hairline(context)),
                clipContent: true,
                child: SizedBox(
                  width: 236,
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: cover != null && cover.isNotEmpty
                                ? ArtworkImage(cover, fit: BoxFit.cover)
                                : const _PreviewBackdrop(),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                music?.name ?? s.playerBackdropPreviewEmpty,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: foreground,
                                ),
                              ),
                              if (music != null && music.singer.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  music.singer,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.secondaryText(context),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 一圈发丝边：浅色封面糊到浅色面板上时，预览的边界还在。
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.cardBorder(context),
                    width: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 没有封面时的底图：几块硬边色块。
///
/// 不用渐变当底——渐变本来就没有 edges，虚化拖到 100% 也看不出区别。色块
/// 的边越硬，模糊档位的变化越直观。
class _PreviewBackdrop extends StatelessWidget {
  const _PreviewBackdrop();

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2340), Color(0xFF2A1730)],
        ),
      ),
      child: CustomPaint(painter: _BlobPainter(accent)),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.22),
      size.height * 0.46,
      paint..color = const Color(0xFF3E6BE0).withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.78),
      size.height * 0.52,
      paint..color = const Color(0xFFC2457B).withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      Offset(size.width * 0.62, size.height * 0.16),
      size.height * 0.22,
      paint..color = accent.withValues(alpha: 0.55),
    );
    // 一条斜带：虚化拉高时它会先糊开，比圆圈更容易看出档位。
    final band = Path()
      ..moveTo(size.width * 0.05, size.height)
      ..lineTo(size.width * 0.42, 0)
      ..lineTo(size.width * 0.52, 0)
      ..lineTo(size.width * 0.15, size.height)
      ..close();
    canvas.drawPath(band, paint..color = Colors.white.withValues(alpha: 0.10));
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _GlassEffectSlider extends StatelessWidget {
  const _GlassEffectSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, 1.0).toDouble();
    final percent = '${(clamped * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onScaffold(context),
                ),
              ),
            ),
            Text(
              percent,
              style: TextStyle(
                fontSize: 12.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.secondaryText(context),
              ),
            ),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: 1,
          divisions: divisions,
          label: percent,
          activeColor: AppColors.accentOf(context),
          inactiveColor: AppColors.cardBorder(context),
          onChanged: onChanged,
          onChangeEnd: (_) => onChangeEnd(),
        ),
      ],
    );
  }
}
