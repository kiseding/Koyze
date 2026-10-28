import 'package:flutter/widgets.dart';

import '../domain/settings_search.dart';

/// One row of the settings list.
///
/// Settings used to be hand-built inside `SettingsScreen.build`; the rows are
/// now data so the same list can be rendered *and* indexed for search. A row
/// added here shows up in the page and in search at once — there is no second
/// place to forget.
class SettingsEntry {
  const SettingsEntry({
    required this.title,
    this.subtitle = '',
    this.keywords = const [],
    this.onTap,
    this.trailing,
    this.toggleValue,
    this.onToggle,
    this.captureExpandOrigin = false,
  });

  final String title;
  final String subtitle;
  final List<String> keywords;

  /// Opens a sub-page or a picker. Null on rows that only carry a switch.
  final VoidCallback? onTap;

  /// Replaces the chevron on the right.
  final Widget? trailing;

  /// Both null on navigation rows, both set on switch rows.
  final bool? toggleValue;
  final ValueChanged<bool>? onToggle;

  /// Record the row's screen rect before pushing, so the sub-page grows out
  /// of the row instead of sliding in from the edge.
  final bool captureExpandOrigin;

  bool get isToggle => onToggle != null;
}

/// A titled block of rows.
class SettingsSectionSpec {
  const SettingsSectionSpec({
    required this.title,
    required this.entries,
    this.leadIn = const [],
  });

  final String title;
  final List<SettingsEntry> entries;

  /// Read-only rows drawn above [entries] (version, device id). They are not
  /// settings, so they stay out of the search index.
  final List<Widget> leadIn;
}

/// A row paired with the section it sits under — what search actually matches.
class SettingsSearchItem implements SettingsSearchTarget {
  const SettingsSearchItem({required this.sectionLabel, required this.entry});

  @override
  final String sectionLabel;

  final SettingsEntry entry;

  @override
  String get title => entry.title;

  @override
  String get subtitle => entry.subtitle;

  @override
  List<String> get keywords => entry.keywords;
}

List<SettingsSearchItem> buildSettingsIndex(
  List<SettingsSectionSpec> sections,
) {
  return [
    for (final section in sections)
      for (final entry in section.entries)
        SettingsSearchItem(sectionLabel: section.title, entry: entry),
  ];
}
