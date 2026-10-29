import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/player_backdrop.dart';
import 'player_backdrop_surface.dart';
import 'player_provider.dart';

/// 全屏播放页背景的调节面板。
///
/// 之所以是一个面板而不是列表里两根滑杆：这两个值调的是「整屏观感」，
/// 在设置页里拖着看不见任何变化，等于盲调。面板顶部放一块用当前封面渲染
/// 的预览，拖动时它同步变化，用户才有判断依据。
Future<void> showPlayerBackdropSheet(BuildContext context) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const PlayerBackdropSheet(),
  );
}

class PlayerBackdropSheet extends ConsumerWidget {
  const PlayerBackdropSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final blur = ref.watch(playerBackdropBlurProvider);
    final scrim = ref.watch(playerBackdropScrimProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.playerBackdrop,
          subtitle: s.playerBackdropSubtitle,
          onClose: () => Navigator.pop(context),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            children: [
              const _BackdropPreview(),
              const SizedBox(height: 20),
              _BackdropSlider(
                label: s.playerBackdropBlur,
                valueText: PlayerBackdrop.blurLabel(blur),
                value: blur,
                min: PlayerBackdrop.minBlur,
                max: PlayerBackdrop.maxBlur,
                onChanged: (value) => ref
                    .read(playerBackdropBlurProvider.notifier)
                    .setBlur(value),
              ),
              const SizedBox(height: 10),
              _BackdropSlider(
                label: s.playerBackdropScrim,
                valueText: PlayerBackdrop.scrimLabel(scrim),
                value: scrim,
                min: PlayerBackdrop.minScrim,
                max: PlayerBackdrop.maxScrim,
                onChanged: (value) => ref
                    .read(playerBackdropScrimProvider.notifier)
                    .setScrim(value),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ref
                        .read(playerBackdropBlurProvider.notifier)
                        .commitBlur(PlayerBackdrop.defaultBlur);
                    ref
                        .read(playerBackdropScrimProvider.notifier)
                        .commitScrim(PlayerBackdrop.defaultScrim);
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

/// 用当前封面渲染一块 16:9 的播放页缩影。
///
/// 走的是播放页同一个 [PlayerBackdropSurface]，所以预览与真页面只可能
/// 因为屏幕尺寸不同而略有差别，不会因为参数换算不同而对不上。
class _BackdropPreview extends ConsumerWidget {
  const _BackdropPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final music = ref.watch(currentMusicProvider);
    final blur = PlayerBackdrop.effectiveBlur(
      ref.watch(playerBackdropBlurProvider),
    );
    final scrim = PlayerBackdrop.clampScrim(
      ref.watch(playerBackdropScrimProvider),
    );
    final accent = AppColors.accentOf(context);
    final foreground = AppColors.onScaffold(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 手机上保持 16:9；平板 / 横屏时封顶 220，否则预览会占掉半屏，
          // 把两根滑杆和「恢复默认」挤到折叠线以下。
          final height = (constraints.maxWidth * 9 / 16).clamp(120.0, 220.0);
          return SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlayerBackdropSurface(
                  artwork: music?.artwork,
                  blur: blur,
                  scrim: scrim,
                ),
                // 前景只放三样东西：歌名、歌手、一条进度条。再多就会伪装成
                // 一个能点的播放器，用户会去点它。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music?.name ?? s.playerBackdropPreviewEmpty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
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
                            fontSize: 11.5,
                            color: AppColors.secondaryText(context),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: 0.36,
                          minHeight: 3,
                          backgroundColor: foreground.withValues(alpha: 0.18),
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ],
                  ),
                ),
                // 一圈发丝边，避免浅色封面糊到白色面板上时看不出预览的边界。
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
          );
        },
      ),
    );
  }
}

class _BackdropSlider extends StatelessWidget {
  const _BackdropSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
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
              valueText,
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
          max: max,
          activeColor: AppColors.accentOf(context),
          inactiveColor: AppColors.cardBorder(context),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
