import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/local_scan_rules.dart';
import 'local_music_provider.dart';

/// 打开「扫描规则」面板。
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

  Future<void> _addExcludedFolder() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).scanRuleAddFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.of(context).scanRuleFolderHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(S.of(context).add),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty || _rules == null) return;
    if (_rules!.excludedFolders.contains(path)) return;
    await _update(
      _rules!.copyWith(excludedFolders: [..._rules!.excludedFolders, path]),
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
                const KoyzeSheetGrabber(),
                KoyzeSheetTitle(
                  title: s.scanRules,
                  subtitle: s.scanRulesHint,
                  onClose: () => Navigator.pop(context),
                ),
                _RuleSection(
                  title: s.scanRuleMinDuration,
                  children: [
                    for (final seconds in _durationOptions)
                      _RuleChip(
                        label: _durationLabel(seconds, s),
                        selected: rules.minDuration.inSeconds == seconds,
                        onTap: () => _update(
                          rules.copyWith(
                            minDuration: Duration(seconds: seconds),
                          ),
                        ),
                      ),
                  ],
                ),
                _RuleSection(
                  title: s.scanRuleMinSize,
                  children: [
                    for (final bytes in _sizeOptions)
                      _RuleChip(
                        label: _sizeLabel(bytes, s),
                        selected: rules.minSizeBytes == bytes,
                        onTap: () =>
                            _update(rules.copyWith(minSizeBytes: bytes)),
                      ),
                  ],
                ),
                SwitchListTile.adaptive(
                  dense: true,
                  value: rules.skipDuplicates,
                  onChanged: (value) =>
                      _update(rules.copyWith(skipDuplicates: value)),
                  title: Text(
                    s.scanRuleSkipDuplicates,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    s.scanRuleSkipDuplicatesHint,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.scanRuleExcludedFolders,
                          style: TextStyle(
                            color: AppColors.onScaffold(context),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addExcludedFolder,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(s.add),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.accentOf(context),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                if (rules.excludedFolders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      s.scanRuleNoExcludedFolders,
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final folder in rules.excludedFolders)
                          ListTile(
                            dense: true,
                            minTileHeight: 40,
                            title: Text(
                              folder,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedText(context),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
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
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Text(
                    _saving ? s.savingNow : s.scanRuleRescanHint,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _RuleSection extends StatelessWidget {
  const _RuleSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.onScaffold(context),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: children),
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? accent : AppColors.onScaffold(context),
      ),
      selectedColor: accent.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected ? accent : AppColors.cardBorder(context),
      ),
      backgroundColor: Colors.transparent,
      showCheckmark: false,
    );
  }
}
