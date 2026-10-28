import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../l10n/app_strings.dart';
import '../../search/presentation/search_controls.dart';
import '../domain/settings_search.dart';
import 'settings_entry.dart';
import 'settings_section_card.dart';

/// Full-page search over the settings rows.
///
/// Drawn inside the settings page instead of on its own route: the rows stay
/// mounted, so switch results flip the real provider and the list behind the
/// layer is already up to date when the layer closes. A route would have to
/// re-read every provider to stay honest.
class SettingsSearchLayer extends StatefulWidget {
  const SettingsSearchLayer({
    super.key,
    required this.sections,
    required this.topInset,
    required this.bottomInset,
    required this.onClose,
    required this.onActivate,
  });

  final List<SettingsSectionSpec> sections;

  /// Space taken by the root header, so the field starts below it.
  final double topInset;

  /// Space covered by the floating mini player.
  final double bottomInset;

  final VoidCallback onClose;

  /// Runs a row's own action. Switches are flipped in place instead.
  final ValueChanged<SettingsEntry> onActivate;

  @override
  State<SettingsSearchLayer> createState() => _SettingsSearchLayerState();
}

class _SettingsSearchLayerState extends State<SettingsSearchLayer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _activate(SettingsEntry entry) {
    if (entry.isToggle) {
      entry.onToggle!(!entry.toggleValue!);
      return;
    }
    widget.onActivate(entry);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Rebuilt on every keystroke and every provider change: the index holds
    // live closures and live switch values, so it must not be cached.
    final hits = searchSettings(
      buildSettingsIndex(widget.sections),
      _controller.text,
    );
    // Ranked order first, then grouped by section for display: the group that
    // owns the best hit floats to the top, rows inside it keep their rank.
    final grouped = <String, List<SettingsSearchItem>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.sectionLabel, () => []).add(hit);
    }

    final content = Padding(
      padding: EdgeInsets.only(
        top: widget.topInset,
        bottom: widget.bottomInset,
      ),
      child: ShellContentFrame(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: SearchFieldBar(
                controller: _controller,
                focusNode: _focusNode,
                hintText: s.settingsSearchHint,
                autofocus: true,
                clearTooltip: s.clearSearch,
                submitTooltip: s.searchAction,
                cancelLabel: s.cancel,
                onChanged: (_) => setState(() {}),
                onClear: _clear,
                // 回车直取第一条：搜「音质」再敲一下回车就该进到那个面板，
                // 不必再用手指去点结果。
                onSubmit: (_) {
                  if (hits.isNotEmpty) _activate(hits.first.entry);
                },
                onCancel: widget.onClose,
              ),
            ),
            Expanded(
              child: grouped.isEmpty
                  ? _EmptyResult(label: s.settingsSearchEmpty)
                  : ListView(
                      padding: const EdgeInsets.only(top: 6, bottom: 28),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        for (final group in grouped.entries)
                          SettingsSectionCard(
                            title: group.key,
                            children: [
                              for (final item in group.value)
                                _SearchResultTile(
                                  item: item,
                                  onTap: () => _activate(item.entry),
                                ),
                            ],
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      // 页面底层还挂着设置列表：没有这层不透明的手势，落在空白处的点击会
      // 穿到被盖住的行上，看着什么都没点，实际已经进了别的页面。
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {},
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: child,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item, required this.onTap});

  final SettingsSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.secondaryText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.isToggle)
              FxSwitch(value: entry.toggleValue!, onChanged: entry.onToggle)
            else
              // 和列表里那一行保持一致：主题色还是那颗色点，睡眠定时还带
              // 「取消」，没自定义的直接给箭头。
              entry.trailing ??
                  Icon(Icons.chevron_right, color: AppColors.mutedText(context)),
          ],
        ),
      ),
    );
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 30,
              color: AppColors.mutedText(context).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
