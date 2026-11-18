import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../l10n/app_strings.dart';
import '../../local_music/domain/local_file_system.dart';
import '../../local_music/presentation/local_file_manager_provider.dart';
import '../domain/download_task.dart';
import 'download_provider.dart';

/// 「导出已下载的歌」：把私有目录里已经下好的歌，往系统公共「下载」放一份副本。
///
/// 只有移动端需要这一步。桌面端本来就直接写在公共下载目录里，
/// [LocalFileSystem.supportsPublicDownloadsExport] 为 false，这张卡不出现。
///
/// 这块原来长在「下载目录」页上。但导出处理的是「已经下好的歌」——那是本地
/// 音乐库的事；改目录是设置，导出是动作，两件事挤在同一页，会让人以为导出是
/// 改目录的附带步骤。现在放回本地音乐设置页，紧挨着本地音乐库那张卡。
class ExportDownloadsCard extends ConsumerStatefulWidget {
  const ExportDownloadsCard({super.key});

  @override
  ConsumerState<ExportDownloadsCard> createState() => _ExportDownloadsCardState();
}

class _ExportDownloadsCardState extends ConsumerState<ExportDownloadsCard> {
  bool _exporting = false;
  String? _error;

  LocalFileSystem get _fs => ref.read(localFileSystemProvider);

  /// 已下载完成、且有落盘路径的任务。
  List<DownloadTask> get _exportable => ref
      .read(downloadTasksProvider)
      .where(
        (task) =>
            task.status == DownloadStatus.completed &&
            (task.savePath?.isNotEmpty ?? false),
      )
      .toList(growable: false);

  Future<void> _export() async {
    if (_exporting) return;
    final s = S.of(context);
    final tasks = _exportable;
    if (tasks.isEmpty) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    var done = 0;
    var failed = 0;
    var cancelled = false;
    for (final task in tasks) {
      if (!mounted) return;
      try {
        final landed = await _fs.exportToPublicDownloads(task.savePath!);
        // null = 用户在系统对话框里点了取消。这时候继续问下一首只会更烦，
        // 直接停下来，已经导出去的照常算数。
        if (landed == null) {
          cancelled = true;
          break;
        }
        done++;
      } catch (error) {
        failed++;
        AppLog.instance.record(
          'download.export',
          'export ${task.name} failed: $error',
          level: AppLogLevel.warning,
        );
      }
    }
    if (!mounted) return;
    setState(() => _exporting = false);
    if (cancelled && done == 0) {
      setState(() => _error = s.downloadLocationCancelled);
      return;
    }
    if (failed > 0) {
      setState(() => _error = s.downloadLocationPartial(done, failed));
      return;
    }
    showAppNotification(
      s.downloadLocationExported(done),
      type: AppNotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    // watch 而不是 read：下载完成后数量要跟着变，否则用户下完新歌回到这页
    // 还看到「10 首可导出」。
    final count = ref
        .watch(downloadTasksProvider)
        .where(
          (task) =>
              task.status == DownloadStatus.completed &&
              (task.savePath?.isNotEmpty ?? false),
        )
        .length;
    final enabled = count > 0 && !_exporting;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GlassSurface(
        style: AppGlassStyle.regular,
        borderRadius: BorderRadius.circular(18),
        border: Border.fromBorderSide(
          AppGlass.hairline(context, emphasized: false),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.save_alt_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.downloadLocationExport,
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        count == 0
                            ? s.downloadLocationEmpty
                            : s.downloadLocationExportCount(count),
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: enabled ? _export : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 40),
                  ),
                  child: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(s.start),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              exportDownloadsExplanation(s),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.mutedText(context),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(
                _error!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 移动端为什么要先落私有目录，以及导出到底往哪放。
///
/// 各平台的墙不一样，说对了才有用：Android 是分区存储、iOS 是应用沙盒、
/// 其余平台给一句通用说明。
String exportDownloadsExplanation(S s) {
  if (Platform.isAndroid) return s.downloadLocationBodyAndroid;
  if (Platform.isIOS) return s.downloadLocationBodyIos;
  return s.downloadLocationBody;
}
