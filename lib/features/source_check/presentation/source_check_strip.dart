// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_strings.dart';
import '../../custom_source/domain/custom_source.dart';
import 'source_check_details.dart';
import 'source_check_provider.dart';

/// 音源卡片里的那一栏「音源检测」。
///
/// 检测结论放在脚本自己的卡片上，用户不用跳去检测页才知道这个源通不通；
/// 没测过的显示「未检测」，测过的带上日期，并且可以只测这一个脚本。
class SourceCheckStrip extends ConsumerWidget {
  const SourceCheckStrip({super.key, required this.source});

  final CustomSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final state = ref.watch(sourceCheckControllerProvider);
    final report = state.book.forSource(source.id);
    final running = state.running && state.activeSourceId == source.id;
    // 别的脚本正在测时不让这里开第二条检测：同一个脚本引擎扛不住并发取链。
    final blocked = state.running && !running;

    final tested = report != null && report.perPlatform.isNotEmpty;
    final total = report?.perPlatform.length ?? 0;
    final ok = report?.okPlatformCount ?? 0;
    final (Color tone, IconData icon) = running
        ? (AppColors.accentOf(context), Icons.hourglass_top)
        : !tested
        ? (AppColors.mutedText(context), Icons.help_outline)
        : ok == total
        ? (AppColors.success, Icons.verified)
        : ok == 0
        ? (AppColors.error, Icons.error_outline)
        : (AppColors.warning, Icons.warning_amber);

    final String status = running
        ? s.sourceCheckTesting
        : tested
        ? s.sourceCheckSummary(
            ok,
            total,
            formatSourceCheckTime(report.testedAt),
          )
        : s.sourceCheckNeverRun;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.fill2(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: running
                ? CircularProgressIndicator(strokeWidth: 2, color: tone)
                : Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.sourceCheckTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: tested || running
                        ? tone
                        : AppColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (running)
            TextButton(
              onPressed: ref
                  .read(sourceCheckControllerProvider.notifier)
                  .cancel,
              child: Text(s.cancel),
            )
          else ...[
            TextButton(
              onPressed: blocked
                  ? null
                  : () => ref
                        .read(sourceCheckControllerProvider.notifier)
                        .runSource(source),
              child: Text(tested ? s.sourceCheckRerun : s.sourceCheckStart),
            ),
            // 检测完成后才出现：点开看每个平台、每一档音质的明细。
            if (report != null)
              _DetailsBadge(
                onTap: () => showSourceCheckDetails(
                  context,
                  sourceName: source.name,
                  report: report,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 检测明细的入口：卡片右侧的一枚「?」。
///
/// 只有跑过检测才出现——没测过时右侧仍然是「开始检测」，不给一个点开空的入口。
class _DetailsBadge extends StatelessWidget {
  const _DetailsBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Tooltip(
        message: s.sourceCheckDetailsOpen,
        child: Semantics(
          button: true,
          label: s.sourceCheckDetailsOpen,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // 用卡片底色而不是 fill2：这枚按钮本身就在 fill2 的条上，
                  // 同色会让它看起来只是块描边，像「挖」出来的按钮更清楚。
                  color: AppColors.card(context),
                  border: Border.all(color: AppColors.cardBorder(context)),
                ),
                child: Text(
                  '?',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondaryText(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
