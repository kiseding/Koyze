import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../../local_music/domain/local_file_system.dart';
import '../../local_music/presentation/local_file_manager_provider.dart';
import '../domain/download_service.dart';
import '../domain/download_task.dart';
import 'download_provider.dart';

/// 下载目录：一个整页，不是弹窗。
///
/// 页面上要做的事不止「选一下」：看清当前落在哪、看清默认位置、能不能换、
/// 换了影响哪些文件、已经下好的能不能导出。这些内容塞进中心弹窗里，桌面端
/// 一屏放不下要滚动，移动端更挤；而且换目录是个会改变文件去向的操作，值得
/// 占一页说明白。
///
/// 四个平台共用同一个页面，按能力渲染：
/// - [LocalFileSystem.supportsDartIoDirectory] → 能换目录（桌面、Android 部分情况）
/// - [LocalFileSystem.supportsPublicDownloadsExport] → 能把已下好的导出到公共「下载」
///
/// 移动端写不进系统公共目录（iOS 沙盒、鸿蒙手机、Android 分区存储各有一道墙），
/// 只能先落私有目录再导出副本，所以那边没有「选择文件夹」。
class DownloadFolderScreen extends ConsumerStatefulWidget {
  const DownloadFolderScreen({super.key});

  @override
  ConsumerState<DownloadFolderScreen> createState() =>
      _DownloadFolderScreenState();
}

class _DownloadFolderScreenState extends ConsumerState<DownloadFolderScreen> {
  /// 切换目录进行中（建目录 + 写探针 + 持久化）。
  bool _applying = false;

  /// 目录选择器开着。
  bool _picking = false;

  /// 导出进行中。
  bool _exporting = false;

  String? _error;

  bool get _busy => _applying || _picking || _exporting;

  LocalFileSystem get _fs => ref.read(localFileSystemProvider);

  /// 已下载完成、且有落盘路径的任务。
  List<DownloadTask> get _exportable => ref
      .read(downloadServiceProvider)
      .tasks
      .where(
        (task) =>
            task.status == DownloadStatus.completed &&
            (task.savePath?.isNotEmpty ?? false),
      )
      .toList(growable: false);

  Future<void> _apply(String? path, {required bool restoreDefault}) async {
    if (_busy) return;
    final s = S.of(context);
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await ref.read(switchDownloadDirectoryProvider)(
        restoreDefault ? null : path,
      );
      if (!mounted) return;
      // 页面不关：用户刚换完目录，就该停在原地看到「当前目录」已经变了。
      setState(() => _applying = false);
      showAppNotification(
        restoreDefault
            ? s.downloadDirectoryRestored
            : s.downloadDirectoryChanged,
        type: AppNotificationType.success,
      );
    } on DownloadDirectoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = error.reason == 'unsupported_scheme'
            ? s.downloadDirectoryUnsupported
            : s.downloadDirectoryNotWritable;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _error = s.downloadDirectoryNotWritable;
      });
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    final s = S.of(context);
    setState(() {
      _picking = true;
      _error = null;
    });
    String? path;
    try {
      // 各平台的选择器不一样：iOS / 鸿蒙要走原生通道（file_picker 在那边
      // 给不出能写进去的目录），其余平台用系统目录选择器。
      path = _fs.needsNativeDirectoryPicker
          ? await _fs.pickDirectory()
          : await FilePicker.getDirectoryPath(
              dialogTitle: s.downloadDirectoryPickerTitle,
            );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = s.downloadDirectoryNotWritable;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _picking = false);
    // null / 空串 = 用户取消，保持原样，不当成错误。
    if (path == null || path.trim().isEmpty) return;
    await _apply(path, restoreDefault: false);
  }

  Future<void> _export() async {
    if (_busy) return;
    final s = S.of(context);
    final tasks = _exportable;
    if (tasks.isEmpty) {
      setState(() => _error = s.downloadLocationEmpty);
      return;
    }
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
    final canSwitchDirectory = _fs.supportsDartIoDirectory;
    final canExport = _fs.supportsPublicDownloadsExport;
    final info = ref.watch(downloadDirectoryInfoProvider).valueOrNull;
    final custom = info?.custom;
    final current =
        info?.current ?? ref.watch(downloadServiceProvider).downloadDirectory;

    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        title: Text(
          s.downloadLocation,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            koyzeAppBarExtent(context) + 10,
            16,
            40,
          ),
          children: [
            _DownloadPathBox(
              label: canSwitchDirectory
                  ? s.downloadDirectoryCurrent
                  : s.downloadLocationPrivate,
              path: current,
            ),
            // 自定义目录时才列默认位置：两个路径一模一样还再写一遍，只会让人
            // 以为「恢复默认」会换到别的地方去。
            if (canSwitchDirectory && info != null && !info.isDefault) ...[
              const SizedBox(height: 10),
              _DownloadPathBox(
                label: s.downloadDirectoryDefaultLocation,
                path: info.defaultPath,
                subtle: true,
              ),
            ],
            const SizedBox(height: 14),
            // 选了自定义目录、但本次运行降级到默认目录：必须显式说出来。
            // 用户看到「当前目录」是默认位置，会以为自己的选择丢了。
            if (info != null && info.isFallbackActive) ...[
              _DownloadDirectoryHint(
                icon: Icons.warning_amber_rounded,
                text: s.downloadDirectoryFallbackActive,
                error: true,
              ),
              const SizedBox(height: 8),
              _DownloadPathBox(
                label: s.downloadDirectoryUnavailable,
                path: info.custom,
                subtle: true,
              ),
              const SizedBox(height: 14),
            ],
            _DownloadDirectoryHint(
              icon: Icons.info_outline,
              text: canSwitchDirectory
                  ? s.downloadDirectoryNote
                  : _exportExplanation(s),
            ),
            if (canExport) ...[
              // 能换目录的平台（Android / iOS）还要额外说清「导出」是什么：
              // 上面那句讲的是「改了目录之后新下载去哪」，跟导出无关。
              if (canSwitchDirectory) ...[
                const SizedBox(height: 10),
                _DownloadDirectoryHint(
                  icon: Icons.save_alt_rounded,
                  text: _exportExplanation(s),
                ),
              ],
              const SizedBox(height: 14),
              _DownloadExportRow(
                count: _exportable.length,
                busy: _exporting,
                // 移动端没有「选择文件夹」这个主动作，导出就是页面上唯一的
                // 操作，所以整行可点；有主动作时同理，点击即导出。
                onTap: _busy ? null : _export,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _DownloadDirectoryHint(
                icon: Icons.error_outline,
                text: _error!,
                error: true,
              ),
            ],
            if (canSwitchDirectory) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _busy ? null : _pick,
                  child: _picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(s.downloadDirectoryChoose),
                ),
              ),
              // 「恢复默认」只在当前确实是自定义目录时才有意义。做成一行
              // 文字按钮而不是第二个实心按钮：换目录是主动作，恢复是退路。
              if (custom != null) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _apply(null, restoreDefault: true),
                  child: Text(
                    s.resetToDefault,
                    style: TextStyle(
                      color: _busy
                          ? AppColors.mutedText(context).withValues(alpha: 0.55)
                          : AppColors.accentOf(context),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 移动端为什么要先落私有目录。各平台的墙不一样，说对了才有用。
  String _exportExplanation(S s) {
    if (Platform.isAndroid) return s.downloadLocationBodyAndroid;
    if (Platform.isIOS) return s.downloadLocationBodyIos;
    return s.downloadLocationBody;
  }
}

/// 页面上的一行「导出已下载的歌」：左边一句话，右边数量和箭头。
///
/// 做成行而不是实心按钮：Android / iOS 页面上另有「选择文件夹」这个主动作，
/// 两个同等重要的按钮上下并排会让用户不知道点哪个。导出作为一次性的附加
/// 操作，放在内容区更合适。
class _DownloadExportRow extends StatelessWidget {
  const _DownloadExportRow({
    required this.count,
    required this.busy,
    required this.onTap,
  });

  final int count;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.isDark(context)
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.028),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.cardBorder(context),
              width: 0.7,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.save_alt_rounded,
                size: 17,
                color: enabled
                    ? AppColors.accentOf(context)
                    : AppColors.mutedText(context).withValues(alpha: 0.55),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.downloadLocationExport,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: enabled
                            ? AppColors.onScaffold(context)
                            : AppColors.mutedText(
                                context,
                              ).withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count == 0
                          ? s.downloadLocationEmpty
                          : s.downloadLocationExportCount(count),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: AppColors.mutedText(context),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一块路径展示：标签 + 可换行的路径。
class _DownloadPathBox extends StatelessWidget {
  const _DownloadPathBox({
    required this.label,
    required this.path,
    this.subtle = false,
  });

  final String label;
  final String? path;

  /// 次要路径（默认位置）用更轻的字色，避免和当前目录抢注意力。
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.isDark(context)
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.2,
              color: AppColors.mutedText(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            path ?? '…',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: subtle
                  ? AppColors.secondaryText(context)
                  : AppColors.onScaffold(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 图标 + 一段说明。用于「影响范围」提示与错误提示。
class _DownloadDirectoryHint extends StatelessWidget {
  const _DownloadDirectoryHint({
    required this.icon,
    required this.text,
    this.error = false,
  });

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.error : AppColors.mutedText(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.4, color: color),
          ),
        ),
      ],
    );
  }
}
