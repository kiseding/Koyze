// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../../l10n/app_strings.dart';
import '../domain/source_check_report.dart';

/// 统一的检测时间写法：`10/28 11:20`。卡片和详情弹窗共用，避免两处格式漂移。
String formatSourceCheckTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}

/// 检测完成后的明细：每个平台、每一档音质实际跑出来的结果。
///
/// 卡片上只有一句「2/4 个平台可用」，用户想知道到底哪一档慢了、报了什么错时，
/// 从右侧的问号点进来。内容全部来自 [SourceCheckReport]，不发新请求。
Future<void> showSourceCheckDetails(
  BuildContext context, {
  required String sourceName,
  required SourceCheckReport report,
}) {
  return showKoyzeDialog<void>(
    context: context,
    builder: (context) =>
        SourceCheckDetailsDialog(sourceName: sourceName, report: report),
  );
}

class SourceCheckDetailsDialog extends StatelessWidget {
  const SourceCheckDetailsDialog({
    super.key,
    required this.sourceName,
    required this.report,
  });

  final String sourceName;
  final SourceCheckReport report;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final platforms = report.perPlatform.values.toList(growable: false);
    final skipped = report.skippedPlatforms;

    return KoyzeDialog(
      icon: const Icon(Icons.fact_check_outlined),
      title: Text(s.sourceCheckDetails),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            s.sourceCheckSummary(
              report.okPlatformCount,
              platforms.length,
              formatSourceCheckTime(report.testedAt),
            ),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s.sourceCheckDetailsIntro,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.mutedText(context),
            ),
          ),
          if (platforms.isNotEmpty) const SizedBox(height: 12),
          for (final platform in platforms) _platformCard(context, platform),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              s.sourceCheckSkipped(
                skipped.map(s.platformText).join(s.en ? ', ' : '、'),
              ),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.mutedText(context),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.close),
        ),
      ],
    );
  }

  Widget _platformCard(
    BuildContext context,
    SourceCheckPlatformReport platform,
  ) {
    final results = platform.qualities.entries.toList(growable: false);
    final verdict = platform.anyOk
        ? SourceCheckVerdict.ok
        : platform.hasSoftFail
        ? SourceCheckVerdict.softFail
        : SourceCheckVerdict.hardFail;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.of(context).platformText(platform.platform),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onScaffold(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _VerdictPill(verdict: verdict),
            ],
          ),
          for (final entry in results)
            _qualityRow(context, entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _qualityRow(
    BuildContext context,
    String quality,
    SourceCheckResult result,
  ) {
    final s = S.of(context);
    final tone = _toneOf(result.verdict);

    final meta = <String>[
      '${result.latencyMs} ms',
      if (result.sizeMb case final sizeMb?) '${_formatSize(sizeMb)} MB',
      if (result.extension case final extension? when extension.isNotEmpty)
        extension.startsWith('.') ? extension : '.$extension',
      if (result.coldStart) s.sourceCheckColdStart,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(_iconOf(result.verdict), size: 14, color: tone),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      quality.isEmpty
                          ? s.sourceCheckDefaultQuality
                          : s.qualityText(quality),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText(context),
                      ),
                    ),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
                if (result.message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      result.message,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(double sizeMb) =>
      sizeMb >= 10 ? sizeMb.toStringAsFixed(0) : sizeMb.toStringAsFixed(1);

  static IconData _iconOf(SourceCheckVerdict verdict) => switch (verdict) {
    SourceCheckVerdict.ok => Icons.check_circle,
    SourceCheckVerdict.softFail => Icons.schedule,
    SourceCheckVerdict.hardFail => Icons.error,
  };

  static Color _toneOf(SourceCheckVerdict verdict) => switch (verdict) {
    SourceCheckVerdict.ok => AppColors.success,
    SourceCheckVerdict.softFail => AppColors.warning,
    SourceCheckVerdict.hardFail => AppColors.error,
  };
}

class _VerdictPill extends StatelessWidget {
  const _VerdictPill({required this.verdict});

  final SourceCheckVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final tone = SourceCheckDetailsDialog._toneOf(verdict);
    final label = switch (verdict) {
      SourceCheckVerdict.ok => s.sourceCheckVerdictOk,
      SourceCheckVerdict.softFail => s.sourceCheckVerdictSoft,
      SourceCheckVerdict.hardFail => s.sourceCheckVerdictHard,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}
