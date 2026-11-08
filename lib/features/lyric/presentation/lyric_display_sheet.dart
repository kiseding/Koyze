import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../../settings/presentation/settings_provider.dart';

/// 歌词显示面板。
///
/// 这几项都是「同一份歌词、不同的设备/耳朵」问题：偏移对不上人声，字号在
/// 小屏或老花眼下看不清，音译行只对日语歌有用。放在设置里盲调没有意义，
/// 所以面板顶部直接放一个能用当前歌词预览的区域——拖动时立刻看到效果。
Future<void> showLyricDisplaySheet(BuildContext context) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const LyricDisplaySheet(),
  );
}

class LyricDisplaySheet extends ConsumerWidget {
  const LyricDisplaySheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final offset = ref.watch(lyricOffsetProvider);
    final scale = ref.watch(lyricScaleProvider);
    final align = ref.watch(lyricAlignProvider);
    final translation = ref.watch(lyricTranslationProvider);
    final roman = ref.watch(lyricRomanProvider);
    final layoutIndex = ref.watch(lyricLayoutProvider);
    final entranceIndex = ref.watch(singleLineAnimationProvider);
    final themeIndex = ref.watch(lyricThemeProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.lyricDisplay,
          subtitle: s.lyricDisplaySubtitle,
          onClose: () => Navigator.pop(context),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              _LyricPreview(scale: scale, showRoman: roman, showTranslation: translation),
              const SizedBox(height: 18),
              _LyricChoiceRow(
                label: s.lyricLayout,
                values: [
                  (0, s.lyricLayoutScroll),
                  (1, s.lyricLayoutSingle),
                  (2, s.lyricLayoutRoulette),
                ],
                selected: layoutIndex,
                onSelected: (value) =>
                    ref.read(lyricLayoutProvider.notifier).setLayout(value),
              ),
              if (layoutIndex == 1) ...[
                const SizedBox(height: 6),
                _LyricChoiceRow(
                  label: s.lyricEntrance,
                  values: [
                    (0, s.lyricEntranceSlide),
                    (1, s.lyricEntranceFade),
                    (2, s.lyricEntranceZoom),
                    (3, s.lyricEntranceBlur),
                  ],
                  selected: entranceIndex,
                  onSelected: (value) => ref
                      .read(singleLineAnimationProvider.notifier)
                      .setAnimation(value),
                ),
              ],
              const SizedBox(height: 10),
              _LyricChoiceRow(
                label: s.lyricTheme,
                values: [
                  (0, s.lyricThemeDefault),
                  (1, s.lyricThemePixel),
                ],
                selected: themeIndex,
                onSelected: (value) =>
                    ref.read(lyricThemeProvider.notifier).setTheme(value),
              ),
              _LyricSlider(
                label: s.lyricOffset,
                valueText: _offsetLabel(offset),
                value: offset.toDouble(),
                min: LyricOffsetNotifier.minOffsetMs.toDouble(),
                max: LyricOffsetNotifier.maxOffsetMs.toDouble(),
                divisions: 40,
                onChanged: (value) => ref
                    .read(lyricOffsetProvider.notifier)
                    .setOffset(value.round()),
                hint: s.lyricOffsetHint,
              ),
              _LyricSlider(
                label: s.lyricFontScale,
                valueText: '${(scale * 100).round()}%',
                value: scale,
                min: LyricScaleNotifier.minScale,
                max: LyricScaleNotifier.maxScale,
                divisions: 10,
                onChanged: (value) =>
                    ref.read(lyricScaleProvider.notifier).setScale(value),
              ),
              _LyricSlider(
                label: s.lyricAlign,
                valueText: '${(align * 100).round()}%',
                value: align,
                min: LyricAlignNotifier.minAlign,
                max: LyricAlignNotifier.maxAlign,
                divisions: 20,
                onChanged: (value) =>
                    ref.read(lyricAlignProvider.notifier).setAlign(value),
              ),
              const SizedBox(height: 6),
              _LyricSwitch(
                label: s.lyricTranslation,
                value: translation,
                onChanged: (value) =>
                    ref.read(lyricTranslationProvider.notifier).setEnabled(value),
              ),
              _LyricSwitch(
                label: s.lyricRoman,
                value: roman,
                onChanged: (value) =>
                    ref.read(lyricRomanProvider.notifier).setEnabled(value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ref.read(lyricOffsetProvider.notifier).setOffset(0);
                    ref.read(lyricScaleProvider.notifier).setScale(1);
                    ref.read(lyricAlignProvider.notifier).setAlign(0.38);
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

  static String _offsetLabel(int ms) {
    if (ms == 0) return '0 ms';
    final sign = ms > 0 ? '+' : '−';
    return '$sign${ms.abs()} ms';
  }
}

/// 用真实歌词样式做的静态预览。
///
/// 不接播放位置：面板打开时播放可能是暂停的，让一行"正在唱"卡住反而更奇怪。
/// 这里只演示三层文字（原文 / 音译 / 翻译）与字号、位置的关系。
class _LyricPreview extends StatelessWidget {
  const _LyricPreview({
    required this.scale,
    required this.showRoman,
    required this.showTranslation,
  });

  final double scale;
  final bool showRoman;
  final bool showTranslation;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder(context), width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '夜に駆ける',
            style: TextStyle(
              color: primary.withValues(alpha: 0.35),
              fontSize: 16 * scale,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '沈むように溶けてゆくように',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 20 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (showRoman)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'shizumu you ni tokete yuku you ni',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary, fontSize: 10.5 * scale),
              ),
            ),
          if (showTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '像要沉下去一般 像要融化一般',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary, fontSize: 12 * scale),
              ),
            ),
        ],
      ),
    );
  }
}

class _LyricSlider extends StatelessWidget {
  const _LyricSlider({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.hint,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? hint;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
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
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.accentOf(context),
          inactiveColor: AppColors.cardBorder(context),
          onChanged: onChanged,
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 0, bottom: 2),
            child: Text(
              hint!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.mutedText(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _LyricSwitch extends StatelessWidget {
  const _LyricSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: AppColors.onScaffold(context),
        ),
      ),
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.accentOf(context),
    );
  }
}

/// 一行横向可选项（布局 / 入场动画）。
///
/// 用 [SegmentedButton] 而不是下拉：可选项都只有 2~4 个，摊开比多一次点击好，
/// 而且当前值一眼可见。
class _LyricChoiceRow extends StatelessWidget {
  const _LyricChoiceRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<(int, String)> values;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            for (final (value, text) in values)
              ButtonSegment<int>(value: value, label: Text(text)),
          ],
          selected: {selected},
          onSelectionChanged: (next) {
            if (next.isNotEmpty) onSelected(next.first);
          },
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.accentOf(context).withValues(
              alpha: 0.16,
            ),
            selectedForegroundColor: AppColors.accentOf(context),
            foregroundColor: AppColors.secondaryText(context),
            side: BorderSide(color: AppColors.cardBorder(context)),
            textStyle: const TextStyle(fontSize: 12.5),
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}
