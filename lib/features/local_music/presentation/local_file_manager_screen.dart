import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/core/widgets/fx_icon_button.dart';
import 'package:koyze/core/widgets/gradient_bar_backgrounds.dart';
import 'package:koyze/core/widgets/koyze_sheet.dart';
import 'package:koyze/features/local_music/domain/local_file_manager.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';
import 'package:koyze/features/local_music/domain/local_music_debug_log.dart';
import 'package:koyze/features/local_music/presentation/local_file_manager_provider.dart';
import 'package:koyze/features/local_music/presentation/local_music_provider.dart';
import 'package:koyze/l10n/app_strings.dart';

/// 本地音乐文件管理。
///
/// 目的很具体：移动端应用的数据目录在系统文件管理器里看不到，用户想把
/// 下载好的歌搬到「音乐」这类公共目录时，没有别的手段。所以这个页面的
/// 主线是「选文件 → 选目标目录 → 搬过去」，不是曲库整理工具。
///
/// 搬走之后曲库就扫不到它了——这正是用户想要的，索引由下次重扫收敛。
class LocalFileManagerScreen extends ConsumerStatefulWidget {
  const LocalFileManagerScreen({super.key});

  @override
  ConsumerState<LocalFileManagerScreen> createState() =>
      _LocalFileManagerScreenState();
}

class _LocalFileManagerScreenState
    extends ConsumerState<LocalFileManagerScreen> {
  String? _directory;
  List<LocalFileEntry> _entries = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 默认落在下载目录：绝大多数要导出的文件都在那儿。
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialDirectory());
  }

  Future<void> _openInitialDirectory() async {
    final library = await ref.read(localMusicLibraryProvider.future);
    final start = library.downloadDirectory ?? library.directories.firstOrNull;
    if (start == null || !mounted) return;
    await _open(start);
  }

  Future<void> _open(String directory) async {
    setState(() {
      _loading = true;
      _directory = directory;
      _selected.clear();
    });
    try {
      final manager = ref.read(localFileManagerProvider);
      final entries = await manager.list(directory);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'file_manager.list.failed',
        'dir=${LocalMusicDebugLog.quote(directory)} error=$error',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _loading = false;
      });
      showAppNotification(
        '${S.of(context).fileManagerListFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  /// 选目录。各平台的路子不一样，统一在这里分派。
  ///
  /// 鸿蒙不能用 `file_picker` 的目录选择器：它的移植版把「选目录」实现成了
  /// 「选文件读进缓存」，返回的是缓存副本路径，当目录用会立刻失败。
  Future<String?> _selectDirectory(String title) async {
    final fs = ref.read(localFileSystemProvider);
    if (fs.needsNativeDirectoryPicker) return fs.pickDirectory();
    return FilePicker.getDirectoryPath(dialogTitle: title);
  }

  Future<void> _pickDirectory() async {
    try {
      // 这里只用来「切换浏览位置」，所以统一用目录选择器，
      // 它在各平台都能返回一个可读路径或 content:// 树。
      final path = await _selectDirectory(S.of(context).fileManagerPickFolder);
      if (path == null || !mounted) return;
      await _open(path);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).fileManagerPickFailed}: $error',
        type: AppNotificationType.error,
      );
    }
  }

  /// 选一个「搬到哪里」。与浏览位置分开：用户经常是「在私有目录看，
  /// 搬到公共目录去」。
  Future<String?> _pickTargetDirectory() async {
    try {
      return await _selectDirectory(S.of(context).fileManagerPickTarget);
    } catch (error) {
      if (!mounted) return null;
      showAppNotification(
        '${S.of(context).fileManagerPickFailed}: $error',
        type: AppNotificationType.error,
      );
      return null;
    }
  }

  Future<void> _copySelected() async {
    final target = await _pickTargetDirectory();
    if (target == null || !mounted) return;
    await _run(
      (manager) => manager.copy(_selected.toList(), target),
      S.of(context).fileManagerCopied,
    );
  }

  Future<void> _moveSelected() async {
    final target = await _pickTargetDirectory();
    if (target == null || !mounted) return;
    await _run(
      (manager) => manager.move(_selected.toList(), target),
      S.of(context).fileManagerMoved,
    );
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).fileManagerDeleteTitle),
        content: Text(S.of(ctx).fileManagerDeleteConfirm(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(S.of(ctx).delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      (manager) => manager.delete(_selected.toList()),
      S.of(context).fileManagerDeleted,
    );
  }

  Future<void> _rename(LocalFileEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).fileManagerRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: S.of(ctx).fileManagerFileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(S.of(ctx).save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == entry.name || !mounted) return;

    final manager = ref.read(localFileManagerProvider);
    final result = await manager.rename(entry.path, name);
    if (!mounted) return;
    if (result.succeeded) {
      showAppNotification(
        S.of(context).fileManagerRenamed,
        type: AppNotificationType.success,
      );
      await _open(_directory!);
    } else {
      showAppNotification(
        '${S.of(context).fileManagerRenameFailed}: ${result.error}',
        type: AppNotificationType.error,
      );
    }
  }

  Future<void> _run(
    Future<LocalFileBatchResult> Function(LocalFileManager manager) action,
    String successMessage,
  ) async {
    if (_selected.isEmpty || _directory == null) return;
    setState(() => _busy = true);
    try {
      final manager = ref.read(localFileManagerProvider);
      final result = await action(manager);
      if (!mounted) return;
      if (result.allSucceeded) {
        showAppNotification(
          '$successMessage（${result.succeeded}）',
          type: AppNotificationType.success,
        );
      } else {
        // 部分失败要说清楚数量，只说「失败」用户不知道到底成没成；
        // 再补一句失败原因，否则「失败 1 个」等于什么都没说。
        final reason = _failureReason(result.failures.first.error);
        showAppNotification(
          '${S.of(context).fileManagerPartialResult(result.succeeded, result.failed)}'
          '${reason == null ? '' : '：$reason'}',
          type: AppNotificationType.warning,
        );
      }
      await _open(_directory!);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${S.of(context).fileManagerListFailed}: $error',
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把异常翻成一句人话。
  ///
  /// 直接把 `Exception: xxx` 甩给用户没用——「重名」和「没权限」是完全不同
  /// 的处理方式，前者改名重试，后者得去设置里授权。
  String? _failureReason(Object? error) {
    if (error == null) return null;
    final s = S.of(context);
    if (error is LocalFileConflictException) {
      return '${s.fileManagerConflict}（${error.path.split(RegExp(r'[/\\]')).last}）';
    }
    if (error is LocalFileAccessDeniedException) {
      return s.fileManagerAccessDenied;
    }
    if (error is LocalFileUnsupportedException) {
      return s.fileManagerUnsupported;
    }
    return error.toString();
  }

  /// 当前目录里能选中的条目。
  ///
  /// 文件夹不参与批量搬运：点它是「进去」而不是「选中」。混在一起的话，
  /// 「全选」会把目录也选上，用户的意图就被猜错了。
  List<LocalFileEntry> get _selectableEntries =>
      _entries.where((entry) => !entry.isDirectory).toList(growable: false);

  bool get _allSelected {
    final selectable = _selectableEntries;
    return selectable.isNotEmpty &&
        selectable.every((entry) => _selected.contains(entry.path));
  }

  void _toggleAll() {
    final selectable = _selectableEntries;
    setState(() {
      if (_allSelected) {
        for (final entry in selectable) {
          _selected.remove(entry.path);
        }
      } else {
        _selected.addAll(selectable.map((entry) => entry.path));
      }
    });
  }

  void _toggle(LocalFileEntry entry) {
    setState(() {
      if (!_selected.remove(entry.path)) _selected.add(entry.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(localFileManagerProvider).isSupported;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => context.pop(),
          ),
          title: Text(
            S.of(context).fileManagerTitle,
            style: TextStyle(
              fontSize: 18,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            FxIconButton(
              tooltip: S.of(context).fileManagerPickFolder,
              icon: Icon(
                Icons.folder_open_rounded,
                color: AppColors.onScaffold(context),
                size: 22,
              ),
              onPressed: _busy ? null : _pickDirectory,
            ),
          ],
        ),
        extendBodyBehindAppBar: true,
        // 开了 extendBodyBehindAppBar，body 就从屏幕最顶开始画——那是为了让
        // 列表能从磨砂栏底下穿过去。代价是内容起点必须自己下移一个栏高
        // （状态栏 + toolbar），否则路径条和第一行会直接压在标题底下。
        body: KoyzeAppBarBody(
          child: !supported
              ? _buildUnsupported(context)
              : Column(
                  children: [
                    if (_directory != null) _buildPathBar(context),
                    Expanded(child: _buildList(context)),
                    if (_selected.isNotEmpty) _buildActionBar(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildUnsupported(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          S.of(context).fileManagerUnsupported,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildPathBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_rounded,
            size: 18,
            color: AppColors.mutedText(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _directory ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText(context),
              ),
            ),
          ),
          if (_selectableEntries.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildSelectAll(context),
          ],
        ],
      ),
    );
  }

  /// 全选 / 取消全选。
  ///
  /// 放在路径条右侧而不是动作栏里：动作栏只在有选中项时才出现，把「全选」
  /// 藏在里面就变成「先选一个才能全选」——多选看起来像没做。
  Widget _buildSelectAll(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _toggleAll,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          _allSelected
              ? S.of(context).fileManagerSelectNone
              : S.of(context).fileManagerSelectAll,
          style: TextStyle(
            fontSize: 12,
            color: _busy
                ? AppColors.mutedText(context)
                : AppColors.accentOf(context),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          S.of(context).fileManagerEmpty,
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final selected = _selected.contains(entry.path);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          tileColor: selected
              ? AppColors.accentOf(context).withValues(alpha: 0.10)
              : null,
          // 文件行左边换成勾选圈：`ListTile.selected` 只改一点底色，在这个
          // 主题里几乎看不出来，用户会以为点了没反应、多选没做。目录行保留
          // 文件夹图标——点它是「进去」，没有选中这回事。
          leading: entry.isDirectory
              ? Icon(
                  Icons.folder_rounded,
                  color: AppColors.accentOf(context),
                )
              : _SelectionMark(selected: selected),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.onScaffold(context),
            ),
          ),
          subtitle: entry.isDirectory
              ? null
              : Text(
                  _formatSize(entry.size),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedText(context),
                  ),
                ),
          trailing: entry.isDirectory
              ? const Icon(Icons.chevron_right, size: 18)
              : IconButton(
                  icon: const Icon(Icons.more_vert, size: 18),
                  onPressed: _busy ? null : () => _showEntryMenu(entry),
                ),
          selected: selected,
          onTap: _busy
              ? null
              : (entry.isDirectory
                    ? () => _open(entry.path)
                    : () => _toggle(entry)),
          // 长按仍然给单项菜单（改名 / 删除）。批量操作走「选中 → 动作栏」，
          // 两条路不抢同一个手势。
          onLongPress: (_busy || entry.isDirectory)
              ? null
              : () => _showEntryMenu(entry),
        );
      },
    );
  }

  void _showEntryMenu(LocalFileEntry entry) {
    showKoyzeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KoyzeSheetHeader(title: entry.name, onClose: () => Navigator.pop(ctx)),
            koyzeSheetActionGap,
            KoyzeSheetAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: S.of(context).fileManagerRename,
              onTap: () {
                Navigator.pop(ctx);
                _rename(entry);
              },
            ),
            KoyzeSheetAction(
              icon: Icons.delete_outline_rounded,
              label: S.of(context).delete,
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                _selected
                  ..clear()
                  ..add(entry.path);
                _deleteSelected();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder(context)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 选中数量单独一行、用强调色：动作栏出现本身就是「选中生效」的
          // 反馈，但用户更需要知道到底选了几个——搬完才发现漏了一首很恼人。
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              S.of(context).fileManagerSelectedCount(_selected.length),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accentOf(context),
              ),
            ),
          ),
          // 只在选中文件时出现，也就是「正要搬」的那一刻。放个对话框拦一道
          // 太重——目录是用户刚在系统选择器里挑的，已经是有意为之；但这句
          // 话得说到，否则搬完回曲库还看得见、点了播不了，会以为文件丢了。
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.mutedText(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S.of(context).fileManagerMoveHint,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.content_copy_rounded,
                  label: S.of(context).fileManagerCopy,
                  onTap: _busy ? null : _copySelected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.drive_file_move_rounded,
                  label: S.of(context).fileManagerMove,
                  onTap: _busy ? null : _moveSelected,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: S.of(context).delete,
                  danger: true,
                  onTap: _busy ? null : _deleteSelected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Icon(
      selected
          ? Icons.check_circle_rounded
          : Icons.radio_button_unchecked_rounded,
      size: 22,
      color: selected
          ? AppColors.accentOf(context)
          : AppColors.mutedText(context).withValues(alpha: 0.6),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Colors.redAccent
        : (onTap == null
              ? AppColors.mutedText(context)
              : AppColors.accentOf(context));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
