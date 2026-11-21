import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/theme/app_tokens.dart';
import 'package:koyze/core/widgets/fx_icon_button.dart';
import 'package:koyze/core/widgets/fx_switch.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/origo_chrome.dart';

/// 均衡器。频段数由设备决定（Android 上常见 5 段，也有 10 段实现），
/// 所以这里一律按播放器上报的布局渲染。
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  @override
  void initState() {
    super.initState();
    // 播放器可能刚在后台激活，进入页面时补读一次真实频段布局。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(equalizerProvider.notifier).refreshLayout();
    });
  }

  /// 导入 AutoEQ 文件。支持 ParametricEQ.txt 与 GraphicEQ.txt 两种导出。
  Future<void> _importAutoEq() async {
    final s = S.of(context);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'csv', 'eq'],
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return;
      String content;
      final bytes = file.bytes;
      if (bytes != null) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        return;
      }
      final ok = await ref
          .read(equalizerProvider.notifier)
          .importAutoEq(content, name: file.name);
      if (!mounted) return;
      showAppNotification(
        ok ? s.autoEqImported(file.name) : s.autoEqImportFailed,
        type: ok ? AppNotificationType.success : AppNotificationType.error,
      );
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        s.autoEqImportFailed,
        type: AppNotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(equalizerProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: S.of(context).back,
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            S.of(context).equalizer,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            IconButton(
              tooltip: S.of(context).autoEqImport,
              onPressed: state.supported ? () => _importAutoEq() : null,
              icon: Icon(
                Icons.file_open_outlined,
                size: 20,
                color: AppColors.onScaffold(context),
              ),
            ),
            TextButton.icon(
              onPressed: state.supported
                  ? () => ref.read(equalizerProvider.notifier).resetToFlat()
                  : null,
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: Text(S.of(context).reset),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        body: state.loading
            ? const Center(child: AppLoadingIndicator())
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + kToolbarHeight + 8,
                  16,
                  32,
                ),
                children: [
                  _buildSwitchCard(context, state),
                  if (!state.supported) ...[
                    const SizedBox(height: 16),
                    _buildUnsupportedNotice(context),
                  ] else ...[
                    const SizedBox(height: 20),
                    _buildPresetSection(context, state),
                    if (state.settings.usesParametricAutoEq) ...[
                      const SizedBox(height: 16),
                      _buildParametricCard(context, state),
                    ],
                    const SizedBox(height: 20),
                    _buildBandSection(context, state),
                    const SizedBox(height: 14),
                    _buildFootnote(context, state),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildSwitchCard(BuildContext context, EqualizerState state) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).equalizer,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.supported
                        ? S.of(context).equalizerHint
                        : S.of(context).unavailableOnPlatform,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
            FxSwitch(
              value: state.settings.enabled,
              onChanged: state.supported
                  ? (value) =>
                        ref.read(equalizerProvider.notifier).setEnabled(value)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedNotice(BuildContext context) {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 20,
              color: AppColors.secondaryText(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).equalizerUnavailable,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.of(context).equalizerUnavailableBody,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetSection(BuildContext context, EqualizerState state) {
    final notifier = ref.read(equalizerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(text: S.of(context).presets),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in equalizerPresets)
              KoyzeChoicePill(
                label: S.of(context).presetName(preset.id),
                selected: state.settings.presetId == preset.id,
                onPressed: () => notifier.selectPreset(preset.id),
                dense: true,
              ),
            // 「自定义」不是可点的预设，只在手动拖过频段后作为状态提示出现。
            if (state.settings.isCustom)
              KoyzeChoicePill(
                label: S.of(context).customPreset,
                selected: true,
                onPressed: null,
                dense: true,
              ),
          ],
        ),
      ],
    );
  }

  /// 参数化 AutoEQ 的信息卡。
  ///
  /// 每个滤波器按原样下发，滑块就失去了意义——那五个频段不再对应任何真实
  /// 的滤波器，拖动只会覆盖掉刚导入的曲线。所以这里换成一张说明卡加一个
  /// Preamp 调节，而不是继续画一排会骗人的滑块。
  Widget _buildParametricCard(BuildContext context, EqualizerState state) {
    final s = S.of(context);
    final settings = state.settings;
    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppColors.accentOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.autoEqParametric(settings.autoEqBiquads.length),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.autoEqParametricHint,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  s.preamp,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Slider(
                    value: settings.preampDb.clamp(-24.0, 12.0),
                    min: -24,
                    max: 12,
                    divisions: 72,
                    label: '${settings.preampDb.toStringAsFixed(1)} dB',
                    onChanged: state.interactive
                        ? (value) => ref
                              .read(equalizerProvider.notifier)
                              .setPreamp(value)
                        : null,
                  ),
                ),
                SizedBox(
                  width: 62,
                  child: Text(
                    '${settings.preampDb.toStringAsFixed(1)} dB',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            Text(
              s.preampHint,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandSection(BuildContext context, EqualizerState state) {
    final layout = state.effectiveLayout;
    final gains = state.gains;
    final interactive = state.interactive;
    final notifier = ref.read(equalizerProvider.notifier);

    return _Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                for (var i = 0; i < layout.bandCount; i++)
                  Expanded(
                    child: _BandSlider(
                      gain: gains[i],
                      minDecibels: layout.minDecibels,
                      maxDecibels: layout.maxDecibels,
                      centerFrequency: layout.centerFrequencies[i],
                      enabled: interactive,
                      onChanged: (value) => notifier.setBandGain(i, value),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              interactive
                  ? S.of(context).gainDb
                  : S.of(context).enableEqualizerToAdjust,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFootnote(BuildContext context, EqualizerState state) {
    final layout = state.effectiveLayout;
    final range =
        '${layout.minDecibels.toStringAsFixed(0)} ~ '
        '${layout.maxDecibels.toStringAsFixed(0)} dB';
    final text = state.layoutReady
        ? S.of(context).bandsReady(layout.bandCount, range)
        : S.of(context).bandsPending;
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        height: 1.5,
        color: AppColors.mutedText(context),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      style: AppGlassStyle.regular,
      borderRadius: BorderRadius.circular(18),
      border: Border.fromBorderSide(
        AppGlass.hairline(context, emphasized: false),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondaryText(context),
        ),
      ),
    );
  }
}

/// 单个频段的竖直滑块：上大下小，符合均衡器的直觉。
class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.gain,
    required this.minDecibels,
    required this.maxDecibels,
    required this.centerFrequency,
    required this.enabled,
    required this.onChanged,
  });

  final double gain;
  final double minDecibels;
  final double maxDecibels;
  final double centerFrequency;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final value = gain.clamp(minDecibels, maxDecibels);
    final span = maxDecibels - minDecibels;
    // 0.5 dB 步进，便于精确复现预设之外的曲线。
    final divisions = span > 0 ? (span * 2).round() : null;
    final valueColor = enabled
        ? AppColors.onScaffold(context)
        : AppColors.mutedText(context);

    return Column(
      children: [
        Text(
          _formatGain(value),
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 40,
          height: 168,
          child: RotatedBox(
            // 逆时针 90°：滑块右端（最大值）转到上方。
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: accent,
                inactiveTrackColor: AppColors.fill2(context),
                thumbColor: accent,
                overlayColor: accent.withValues(alpha: 0.14),
                disabledActiveTrackColor: AppColors.mutedText(context),
                disabledInactiveTrackColor: AppColors.fill(context),
                disabledThumbColor: AppColors.mutedText(context),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                min: minDecibels,
                max: maxDecibels,
                divisions: divisions,
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatFrequency(centerFrequency),
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.secondaryText(context),
            ),
          ),
        ),
      ],
    );
  }
}

String _formatGain(double gain) {
  final rounded = gain.roundToDouble();
  final text = gain == rounded
      ? rounded.toStringAsFixed(0)
      : gain.toStringAsFixed(1);
  return gain > 0 ? '+$text' : text;
}

String _formatFrequency(double hz) {
  if (hz >= 1000) {
    final kilo = hz / 1000;
    final text = kilo == kilo.roundToDouble()
        ? kilo.toStringAsFixed(0)
        : kilo.toStringAsFixed(1);
    return '${text}kHz';
  }
  return '${hz.toStringAsFixed(0)}Hz';
}
