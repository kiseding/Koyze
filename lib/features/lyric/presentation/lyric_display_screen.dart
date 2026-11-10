import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/lyric_font.dart';
import '../presentation/lyric_effects.dart';
import '../presentation/lyric_font_provider.dart';
import 'lyric_preview.dart';

/// 打开歌词显示设置页。
///
/// 从底部弹窗改成整页：这一页现在有模糊、字号、偏移、字体、附加行好几组，
/// 弹窗里挤下来只会一直滚，而且弹窗的关闭手势和滑杆拖动会互相抢。
Future<void> openLyricDisplaySettings(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => const LyricDisplayScreen()));
}

class LyricDisplayScreen extends ConsumerStatefulWidget {
  const LyricDisplayScreen({super.key});

  @override
  ConsumerState<LyricDisplayScreen> createState() => _LyricDisplayScreenState();
}

class _LyricDisplayScreenState extends ConsumerState<LyricDisplayScreen> {
  bool _pickingFont = false;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final offset = ref.watch(lyricOffsetProvider);
    final scale = ref.watch(lyricScaleProvider);
    final align = ref.watch(lyricAlignProvider);
    final translation = ref.watch(lyricTranslationProvider);
    final roman = ref.watch(lyricRomanProvider);
    final blur = ref.watch(lyricBlurProvider);
    final entrance =
        LyricEntranceStyle.values[ref.watch(lyricEntranceProvider).clamp(0, 3)];
    final font = ref.watch(lyricFontProvider);

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: s.back,
          icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.lyricDisplay,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
      body: ListView(
        padding: koyzeAppBarContentPadding(context, bottom: 40),
        children: [
          LyricPreview(
            scale: scale,
            blur: blur,
            showRoman: roman,
            showTranslation: translation,
            entrance: entrance,
            fontFamily: font.family,
          ),
          const SizedBox(height: 6),
          _GroupTitle(s.lyricDistortion),
          _LyricSlider(
            label: s.lyricBlur,
            valueText: '${(blur * 100).round()}%',
            value: blur,
            min: LyricBlurNotifier.minBlur,
            max: LyricBlurNotifier.maxBlur,
            divisions: 20,
            onChanged: (value) =>
                ref.read(lyricBlurProvider.notifier).setBlur(value),
            hint: s.lyricBlurHint,
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
          const SizedBox(height: 4),
          _GroupTitle(s.lyricTiming),
          _LyricSlider(
            label: s.lyricOffset,
            valueText: _offsetLabel(offset),
            value: offset.toDouble(),
            min: LyricOffsetNotifier.minOffsetMs.toDouble(),
            max: LyricOffsetNotifier.maxOffsetMs.toDouble(),
            divisions: 40,
            onChanged: (value) =>
                ref.read(lyricOffsetProvider.notifier).setOffset(value.round()),
            hint: s.lyricOffsetHint,
          ),
          const SizedBox(height: 4),
          _GroupTitle(s.lyricFont),
          _FontTile(
            fontName: font.displayName,
            loading: font.loading || _pickingFont,
            onPick: _pickFont,
            onClear: font.isCustom
                ? () => ref.read(lyricFontProvider.notifier).clear()
                : null,
          ),
          const SizedBox(height: 4),
          _GroupTitle(s.lyricExtras),
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
          _LyricChoiceRow(
            label: s.lyricEntrance,
            values: [
              (0, s.lyricEntranceSlide),
              (1, s.lyricEntranceFade),
              (2, s.lyricEntranceZoom),
              (3, s.lyricEntranceBlur),
            ],
            selected: entrance.index,
            onSelected: (value) =>
                ref.read(lyricEntranceProvider.notifier).setAnimation(value),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ref.read(lyricOffsetProvider.notifier).setOffset(0);
                ref.read(lyricScaleProvider.notifier).setScale(1);
                ref.read(lyricAlignProvider.notifier).setAlign(0.38);
                ref
                    .read(lyricBlurProvider.notifier)
                    .setBlur(LyricBlurNotifier.defaultBlur);
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
    );
  }

  /// 选字体：立刻弹系统文件选择器，选完立即生效。
  ///
  /// 三种非正常路径都各有明确反馈：取消什么都不做（不弹提示，用户自己知道
  /// 取消了）；格式不支持 / 内容不是字体 / 太大，各给一条对应文案；读取异常
  /// 走兜底的通用失败提示，并把细节写进诊断日志。
  Future<void> _pickFont() async {
    final s = S.of(context);
    setState(() => _pickingFont = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: kLyricFontExtensions.toList(growable: false),
        withData: true,
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        AppLog.instance.record('lyric.font', 'font pick cancelled');
        return;
      }
      final picked = result.files.single;
      final bytes = picked.bytes;
      if (bytes == null) {
        showAppNotification(
          s.lyricFontReadFailed,
          type: AppNotificationType.error,
        );
        return;
      }
      await ref
          .read(lyricFontProvider.notifier)
          .adopt(fileName: picked.name, bytes: bytes);
      if (!mounted) return;
      showAppNotification(
        s.lyricFontApplied,
        type: AppNotificationType.success,
      );
    } on LyricFontException catch (error) {
      if (!mounted) return;
      AppLog.instance.record(
        'lyric.font',
        'font rejected: ${error.issue.name} ${error.detail ?? ''}',
        level: AppLogLevel.warning,
      );
      showAppNotification(
        _messageFor(s, error),
        type: AppNotificationType.error,
      );
    } on Object catch (error, stackTrace) {
      if (!mounted) return;
      AppLog.instance.record(
        'lyric.font',
        'font pick failed: $error',
        level: AppLogLevel.error,
        stackTrace: stackTrace,
      );
      showAppNotification(
        s.lyricFontReadFailed,
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _pickingFont = false);
    }
  }

  String _messageFor(S s, LyricFontException error) {
    return switch (error.issue) {
      LyricFontIssue.unsupportedFormat => s.lyricFontUnsupported,
      LyricFontIssue.tooLarge => s.lyricFontTooLarge,
      LyricFontIssue.emptyFile => s.lyricFontEmpty,
      LyricFontIssue.invalidData => s.lyricFontInvalid,
      LyricFontIssue.unavailablePath => s.lyricFontReadFailed,
      LyricFontIssue.loadFailed => s.lyricFontLoadFailed,
    };
  }

  static String _offsetLabel(int ms) {
    if (ms == 0) return '0 ms';
    final sign = ms > 0 ? '+' : '−';
    return '$sign${ms.abs()} ms';
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppColors.mutedText(context),
        ),
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
            padding: const EdgeInsets.only(bottom: 2),
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

/// 一行横向可选项（入场动画）。
///
/// 用 [SegmentedButton] 而不是下拉：可选项只有 4 个，摊开比多一次点击好，
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
            selectedBackgroundColor: AppColors.accentOf(
              context,
            ).withValues(alpha: 0.16),
            selectedForegroundColor: AppColors.accentOf(context),
            foregroundColor: AppColors.secondaryText(context),
            side: BorderSide(color: AppColors.cardBorder(context)),
            textStyle: const TextStyle(fontSize: 12.5),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

/// 自定义字体这一行：一句当前状态 + 「选择」「恢复默认」。
class _FontTile extends StatelessWidget {
  const _FontTile({
    required this.fontName,
    required this.loading,
    required this.onPick,
    required this.onClear,
  });

  final String? fontName;
  final bool loading;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    return GlassSurface(
      style: AppGlassStyle.regular,
      backdrop: false,
      borderRadius: BorderRadius.circular(16),
      border: Border.fromBorderSide(AppGlass.hairline(context)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(
                        Icons.font_download_outlined,
                        size: 20,
                        color: fontName == null
                            ? AppColors.secondaryText(context)
                            : accent,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fontName ?? s.lyricFontDefaultName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.lyricFontFormats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              TextButton(
                key: const Key('lyric-font-reset'),
                onPressed: loading ? null : onClear,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.mutedText(context),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  s.lyricFontReset,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(width: 6),
            FilledButton.tonal(
              onPressed: loading ? null : onPick,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 34),
              ),
              child: Text(
                s.lyricFontPick,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
