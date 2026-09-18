import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/widgets/fx_icon_button.dart';
import 'package:koyze/core/widgets/fx_switch.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/presentation/equalizer_provider.dart';

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
            tooltip: '返回',
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '均衡器',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: state.supported
                  ? () => ref.read(equalizerProvider.notifier).resetToFlat()
                  : null,
              icon: const Icon(Icons.restart_alt_rounded, size: 17),
              label: const Text('重置'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentOf(context),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '均衡器',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.supported
                        ? '按频段调整播放音色，对所有音源生效'
                        : '当前平台不可用',
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
                    '当前平台不支持均衡器',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '均衡器需要播放引擎开放音频特效通道。iOS / macOS 的 '
                    'AVPlayer 与 Windows 的 Media Foundation 都没有暴露这一层，'
                    '因此暂时只在 Android 上生效。',
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
        const _SectionTitle(text: '预设'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in equalizerPresets)
              ChoiceChip(
                label: Text(preset.label, style: const TextStyle(fontSize: 13)),
                selected: state.settings.presetId == preset.id,
                onSelected: (_) => notifier.selectPreset(preset.id),
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: AppColors.onScaffold(context),
                  fontSize: 13,
                ),
                visualDensity: VisualDensity.compact,
              ),
            // 「自定义」不是可点的预设，只在手动拖过频段后作为状态提示出现。
            if (state.settings.isCustom)
              ChoiceChip(
                label: const Text('自定义', style: TextStyle(fontSize: 13)),
                selected: true,
                onSelected: null,
                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                labelStyle: TextStyle(
                  color: AppColors.onScaffold(context),
                  fontSize: 13,
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBandSection(BuildContext context, EqualizerState state) {
    final layout = state.effectiveLayout;
    final gains = state.gains;
    final interactive = state.interactive;
    final notifier = ref.read(equalizerProvider.notifier);

    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 12),
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
              interactive ? '增益（dB）' : '开启均衡器后可调节',
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
        ? '已读取设备频段：${layout.bandCount} 段（$range）'
        : '播放器尚未连接，暂按常见 5 段展示；开始播放后会自动读取设备频段';
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
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
