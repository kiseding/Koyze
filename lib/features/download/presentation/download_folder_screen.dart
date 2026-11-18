import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../../local_music/domain/local_file_system.dart';
import '../../local_music/presentation/local_file_manager_provider.dart';
import '../domain/download_service.dart';
import 'download_provider.dart';
import 'export_downloads_card.dart';

/// 下载目录：一个整页，不是弹窗。
///
/// 页面上要做的事不止「选一下」：看清当前落在哪、看清默认位置、能不能换、
/// 换了影响哪些文件。这些内容塞进中心弹窗里，桌面端一屏放不下要滚动，移动端
/// 更挤；而且换目录是个会改变文件去向的操作，值得占一页说明白。
///
/// 四个平台共用同一个页面，按能力渲染：只有
/// [LocalFileSystem.supportsDartIoDirectory] 为真的平台才有「选择文件夹」。
///
/// 移动端写不进系统公共目录（iOS 沙盒、鸿蒙手机、Android 分区存储各有一道墙），
/// 只能先落私有目录再导出副本。导出本身不在这页——它处理的是「已经下好的歌」，
/// 那是本地音乐库的事，入口在「本地音乐设置」里（见 [ExportDownloadsCard]）。
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

  String? _error;

  bool get _busy => _applying || _picking;

  LocalFileSystem get _fs => ref.read(localFileSystemProvider);

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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final canSwitchDirectory = _fs.supportsDartIoDirectory;
    // 用来决定要不要留「导出搬到哪了」那一句：Android 既能换目录也能导出。
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
            if (canSwitchDirectory)
              _DownloadDirectoryHint(
                icon: Icons.info_outline,
                text: s.downloadDirectoryNote,
              )
            else
              // 走不到「选择文件夹」的都是移动端，也正是「导出」存在的场景：
              // 先从系统层面解释为什么路径长这样。
              _DownloadDirectoryHint(
                icon: Icons.info_outline,
                text: exportDownloadsExplanation(s),
              ),
            // 导出按钮不在这页了（它在「本地音乐设置」里），但那些本来有导出
            // 的平台都得留一句指路——Android 既能换目录又能导出，不能只在
            // 「不能换目录」那一支里说。
            if (canExport) ...[
              const SizedBox(height: 10),
              _DownloadDirectoryHint(
                icon: Icons.save_alt_rounded,
                text: s.downloadDirectoryExportMoved,
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
