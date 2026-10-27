// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../../custom_source/domain/custom_source.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../domain/source_check_report.dart';
import 'source_check_provider.dart';

/// 音源检测页：给每个脚本跑一次取链，把「能不能用、多快、多大」摊开给用户看。
class SourceCheckScreen extends ConsumerWidget {
  const SourceCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final sources = ref.watch(customSourcesProvider);
    final state = ref.watch(sourceCheckControllerProvider);
    final controller = ref.read(sourceCheckControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
          s.sourceCheckTitle,
          style: TextStyle(
            color: AppColors.onScaffold(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: sources.isEmpty
          ? _EmptyState(message: s.sourceCheckNoSources)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  s.sourceCheckIntro,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.onScaffold(context).withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                _RunCard(
                  state: state,
                  sourceCount: sources.length,
                  // 未启用的脚本一起测：卡片上就在列它们，不给结论只会一直显示
                  // 「没测过」；取链本身也不看启用状态。
                  onStart: () => controller.runAll(sources),
                  onCancel: controller.cancel,
                ),
                const SizedBox(height: 20),
                for (final source in sources) ...[
                  _SourceCard(
                    source: source,
                    report: state.book.forSource(source.id),
                    running: state.running && state.activeSourceId == source.id,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.state,
    required this.sourceCount,
    required this.onStart,
    required this.onCancel,
  });

  final SourceCheckState state;
  final int sourceCount;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onSurface = AppColors.onScaffold(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.running) ...[
            Text(
              state.current.isEmpty
                  ? s.sourceCheckPreparing
                  : s.sourceCheckRunning(
                      s.platformText(state.current.split(' · ').first) +
                          (state.current.contains(' · ')
                              ? ' · ${_qualityLabel(s, state.current.split(' · ').last)}'
                              : ''),
                    ),
              style: TextStyle(fontSize: 14, color: onSurface),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.total <= 0 ? null : state.fraction,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.sourceCheckProgress(state.done, state.total),
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onCancel, child: Text(s.cancel)),
          ] else ...[
            Text(
              s.sourceCheckAffectsSelection,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: sourceCount == 0 ? null : onStart,
              icon: const Icon(Icons.playlist_add_check, size: 18),
              label: Text(s.sourceCheckStart),
            ),
            if (state.cancelled) ...[
              const SizedBox(height: 8),
              Text(
                s.sourceCheckCancelled,
                style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _qualityLabel(S s, String raw) =>
      raw == 'default' ? s.sourceCheckDefaultQuality : s.qualityText(raw);
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.report,
    required this.running,
  });

  final CustomSource source;
  final SourceCheckReport? report;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onSurface = AppColors.onScaffold(context);
    final report = this.report;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
              if (!source.isEnabled)
                Text(
                  s.sourceCheckDisabledBadge,
                  style: TextStyle(
                    fontSize: 11,
                    color: onSurface.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _summary(s, report, running),
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          children: [
            if (report == null || report.perPlatform.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.sourceCheckNeverRun,
                    style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            else
              for (final platform in report.perPlatform.values)
                _PlatformRows(platform: platform),
            if (report != null && report.skippedPlatforms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.sourceCheckSkipped(
                      report.skippedPlatforms.join(' / '),
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      color: onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _summary(S s, SourceCheckReport? report, bool running) {
    if (running) return s.sourceCheckTesting;
    if (report == null || report.perPlatform.isEmpty) {
      return s.sourceCheckNeverRun;
    }
    final total = report.perPlatform.length;
    return s.sourceCheckSummary(
      report.okPlatformCount,
      total,
      _formatTime(report.testedAt),
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _PlatformRows extends StatelessWidget {
  const _PlatformRows({required this.platform});

  final SourceCheckPlatformReport platform;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onSurface = AppColors.onScaffold(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          s.platformText(platform.platform),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: onSurface.withValues(alpha: 0.8),
          ),
        ),
        for (final entry in platform.qualities.entries)
          _ResultRow(
            quality: entry.key,
            result: entry.value,
          ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.quality, required this.result});

  final String quality;
  final SourceCheckResult result;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onSurface = AppColors.onScaffold(context);
    final (icon, color) = switch (result.verdict) {
      SourceCheckVerdict.ok => (Icons.check_circle, const Color(0xFF34C759)),
      SourceCheckVerdict.softFail => (
        Icons.hourglass_bottom,
        const Color(0xFFFF9F0A),
      ),
      SourceCheckVerdict.hardFail => (Icons.cancel, const Color(0xFFFF3B30)),
    };
    final parts = <String>[
      result.latencyMs > 0 ? '${result.latencyMs} ms' : '',
      if (result.sizeMb != null) '${result.sizeMb!.toStringAsFixed(1)} MB',
      if (result.coldStart) s.sourceCheckColdStart,
      if (result.message.isNotEmpty) result.message,
    ].where((part) => part.isNotEmpty).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
            child: Text(
              quality.isEmpty ? s.sourceCheckDefaultQuality : s.qualityText(quality),
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.75)),
            ),
          ),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final onSurface = AppColors.onScaffold(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension_outlined,
              size: 48,
              color: onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
