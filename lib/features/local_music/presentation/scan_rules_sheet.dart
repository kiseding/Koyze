import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/local_scan_rules.dart';
import 'local_file_manager_provider.dart';
import 'local_music_provider.dart';

/// 打开「扫描规则」面板。
///
/// 和睡眠定时 / 车机模式 / 音质选择等面板同一套语言：统一标题行 +
/// `KoyzeSheetAction` 动作行，时长和体积各自进一个同样款式的单选面板，
/// 主面板只留四行，不把十几个选项平铺成一堵墙。
void showScanRulesSheet(BuildContext context, WidgetRef ref) {
  showKoyzeSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ScanRulesSheet(),
  );
}

class _ScanRulesSheet extends ConsumerStatefulWidget {
  const _ScanRulesSheet();

  @override
  ConsumerState<_ScanRulesSheet> createState() => _ScanRulesSheetState();
}

class _ScanRulesSheetState extends ConsumerState<_ScanRulesSheet> {
  LocalScanRules? _rules;
  bool _saving = false;

  static const List<int> _durationOptions = <int>[0, 30, 60, 120];
  static const List<int> _sizeOptions = <int>[
    0,
    100 * 1024,
    512 * 1024,
    1024 * 1024,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final library = await ref.read(localMusicLibraryProvider.future);
    await library.init();
    if (!mounted) return;
    setState(() => _rules = library.scanRules);
  }

  Future<void> _update(LocalScanRules next) async {
    setState(() => _rules = next);
    _saving = true;
    try {
      final library = await ref.read(localMusicLibraryProvider.future);
      await library.setScanRules(next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _durationLabel(int seconds, S s) {
    if (seconds == 0) return s.scanRuleNoLimit;
    if (seconds < 60) return s.secondsShort(seconds);
    return s.minutes(seconds ~/ 60);
  }

  String _sizeLabel(int bytes, S s) {
    if (bytes == 0) return s.scanRuleNoLimit;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  /// 排除目录走系统文件夹选择器，不让用户手敲路径。
  ///
  /// iOS / 鸿蒙的 `file_picker` 目录选择器给不出能长期使用的路径，统一按
  /// 文件管理页的约定分派到原生通道；其余平台（桌面 / Android）用系统目录
  /// 选择器，Android 那边拿到的是 SAF 树 URI，扫描器按前缀匹配同样有效。
  Future<void> _addExcludedFolder() async {
    final s = S.of(context);
    final fs = ref.read(localFileSystemProvider);
    String? path;
    try {
      path = fs.needsNativeDirectoryPicker
          ? await fs.pickDirectory()
          : await FilePicker.getDirectoryPath(dialogTitle: s.scanRuleAddFolder);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        '${s.chooseFolderFailed}: $error',
        type: AppNotificationType.error,
      );
      return;
    }

    final folder = path?.trim();
    if (folder == null || folder.isEmpty || !mounted) return;
    final rules = _rules;
    if (rules == null) return;
    // 命中的是「已被现有规则覆盖」的目录，不必重复占一行。
    if (rules.excludes(folder)) return;
    await _update(
      rules.copyWith(excludedFolders: [...rules.excludedFolders, folder]),
    );
  }

  /// 最小时长 / 最小体积共用的单选面板外壳，款式和音质、语言等面板一致。
  Future<void> _showOptionSheet({
    required String title,
    required IconData icon,
    required List<int> options,
    required int current,
    required String Function(int value) labelOf,
    required LocalScanRules Function(int value) apply,
  }) async {
    await showKoyzeSheet<void>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KoyzeSheetTitle(
              title: title,
              onClose: () => Navigator.pop(sheetCtx),
            ),
            for (final value in options)
              KoyzeSheetAction(
                icon: icon,
                label: labelOf(value),
                selected: value == current,
                trailing: value == current
                    ? Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: AppColors.accentOf(sheetCtx),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _update(apply(value));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rules = _rules;
    return SafeArea(
      top: false,
      child: rules == null
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KoyzeSheetTitle(
                  title: s.scanRules,
                  subtitle: s.scanRulesHint,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 10),
                    children: [
                      KoyzeSheetAction(
                        icon: Icons.timer_outlined,
                        label: s.scanRuleMinDuration,
                        subtitle: _durationLabel(
                          rules.minDuration.inSeconds,
                          s,
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                        onTap: () => _showOptionSheet(
                          title: s.scanRuleMinDuration,
                          icon: Icons.timer_outlined,
                          options: _durationOptions,
                          current: rules.minDuration.inSeconds,
                          labelOf: (value) => _durationLabel(value, s),
                          apply: (value) => rules.copyWith(
                            minDuration: Duration(seconds: value),
                          ),
                        ),
                      ),
                      KoyzeSheetAction(
                        icon: Icons.storage_rounded,
                        label: s.scanRuleMinSize,
                        subtitle: _sizeLabel(rules.minSizeBytes, s),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                        onTap: () => _showOptionSheet(
                          title: s.scanRuleMinSize,
                          icon: Icons.storage_rounded,
                          options: _sizeOptions,
                          current: rules.minSizeBytes,
                          labelOf: (value) => _sizeLabel(value, s),
                          apply: (value) => rules.copyWith(minSizeBytes: value),
                        ),
                      ),
                      KoyzeSheetAction(
                        icon: Icons.filter_alt_outlined,
                        label: s.scanRuleSkipDuplicates,
                        subtitle: s.scanRuleSkipDuplicatesHint,
                        selected: rules.skipDuplicates,
                        trailing: rules.skipDuplicates
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: AppColors.accentOf(context),
                              )
                            : null,
                        onTap: () => _update(
                          rules.copyWith(skipDuplicates: !rules.skipDuplicates),
                        ),
                      ),
                      KoyzeSheetAction(
                        icon: Icons.folder_open_rounded,
                        label: s.scanRuleAddFolder,
                        subtitle: rules.excludedFolders.isEmpty
                            ? s.scanRuleNoExcludedFolders
                            : s.scanRuleExcludedFolders,
                        onTap: _addExcludedFolder,
                      ),
                      for (final folder in rules.excludedFolders)
                        KoyzeSheetAction(
                          icon: Icons.folder_outlined,
                          label: folder,
                          onTap: () {},
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            color: AppColors.mutedText(context),
                            tooltip: s.remove,
                            onPressed: () => _update(
                              rules.copyWith(
                                excludedFolders: [
                                  for (final item in rules.excludedFolders)
                                    if (item != folder) item,
                                ],
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
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
                                _saving ? s.savingNow : s.scanRuleRescanHint,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: AppColors.mutedText(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
