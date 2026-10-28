import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';

OverlayEntry? _diagnosticLogEntry;
final _diagnosticLogKey = GlobalKey<_DiagnosticLogOverlayState>();

/// 打开诊断浮层。记录从这一刻开始——不打开就一条日志都不收。
void showDiagnosticLogOverlay(BuildContext context) {
  final existing = _diagnosticLogKey.currentState;
  if (existing != null) {
    existing.expand();
    return;
  }
  final overlay = Overlay.of(context, rootOverlay: true);
  final log = AppLog.instance;
  log.start();
  log.record('app', 'diagnostic log opened');
  _diagnosticLogEntry = OverlayEntry(
    builder: (_) => _DiagnosticLogOverlay(key: _diagnosticLogKey, log: log),
  );
  overlay.insert(_diagnosticLogEntry!);
}

void _closeDiagnosticLogOverlay() {
  AppLog.instance.stop();
  _diagnosticLogEntry?.remove();
  _diagnosticLogEntry = null;
}

class _DiagnosticLogOverlay extends StatefulWidget {
  const _DiagnosticLogOverlay({super.key, required this.log});

  final AppLog log;

  @override
  State<_DiagnosticLogOverlay> createState() => _DiagnosticLogOverlayState();
}

class _DiagnosticLogOverlayState extends State<_DiagnosticLogOverlay> {
  bool _minimized = false;
  Offset? _position;

  void expand() => setState(() => _minimized = false);

  @override
  Widget build(BuildContext context) {
    if (!_minimized) {
      final media = MediaQuery.of(context);
      final compact = media.size.width < 600;
      return Material(
        color: Colors.black.withValues(alpha: 0.32),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 24,
              vertical: compact ? 6 : 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: media.size.height * (compact ? 0.92 : 0.82),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(compact ? 20 : 18),
                  child: AppLogScreen(
                    log: widget.log,
                    onMinimize: () => setState(() => _minimized = true),
                    onClose: _closeDiagnosticLogOverlay,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final media = MediaQuery.of(context);
    const size = Size(116, 38);
    final safeTop = media.padding.top + 8;
    final maxLeft = media.size.width - size.width - 8;
    final maxTop = media.size.height - media.padding.bottom - size.height - 8;
    final position = _position ?? Offset(maxLeft, safeTop + 72);
    return Positioned(
      left: position.dx.clamp(8, maxLeft),
      top: position.dy.clamp(safeTop, maxTop),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final next = position + details.delta;
            _position = Offset(
              next.dx.clamp(8, maxLeft),
              next.dy.clamp(safeTop, maxTop),
            );
          });
        },
        onTap: expand,
        child: GlassSurface(
          style: AppGlassStyle.chrome,
          borderRadius: BorderRadius.circular(22),
          border: Border.fromBorderSide(
            AppGlass.hairline(context, emphasized: true),
          ),
          emphasized: true,
          child: ValueListenableBuilder<List<AppLogEntry>>(
            valueListenable: widget.log.entries,
            builder: (context, entries, _) {
              final hasError = entries.any(
                (entry) => entry.level == AppLogLevel.error,
              );
              return SizedBox(
                width: size.width,
                height: size.height,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bug_report_outlined,
                      size: 15,
                      color: AppColors.accentOf(context),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      S.of(context).diagnosticsCount(entries.length),
                      style: TextStyle(
                        color: AppColors.onScaffold(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasError ? AppColors.error : AppColors.success,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 诊断面板。自己管筛选与滚动，方便单独塞进浮层或测试里。
class AppLogScreen extends StatefulWidget {
  AppLogScreen({super.key, AppLog? log, this.onMinimize, this.onClose})
    : log = log ?? AppLog.instance;

  final AppLog log;
  final VoidCallback? onMinimize;
  final VoidCallback? onClose;

  @override
  State<AppLogScreen> createState() => _AppLogScreenState();
}

enum _LevelFilter { all, warning, error }

class _AppLogScreenState extends State<AppLogScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _followLatest = true;
  _LevelFilter _filter = _LevelFilter.all;

  @override
  void initState() {
    super.initState();
    widget.log.entries.addListener(_onEntriesChanged);
  }

  @override
  void dispose() {
    widget.log.entries.removeListener(_onEntriesChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onEntriesChanged() {
    if (!_followLatest) return;
    _jumpToLatest(animate: false);
  }

  void _jumpToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (!animate) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _selectFilter(_LevelFilter filter) {
    setState(() {
      _filter = filter;
      _followLatest = true;
    });
    _jumpToLatest();
  }

  Future<void> _copyLogs(List<AppLogEntry> entries) async {
    if (entries.isEmpty) return;
    final text = entries.map((entry) => entry.text).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppNotification(
      S.of(context).logCopied,
      type: AppNotificationType.success,
    );
  }

  List<AppLogEntry> _apply(List<AppLogEntry> entries) {
    return switch (_filter) {
      _LevelFilter.all => entries,
      _LevelFilter.warning =>
        entries
            .where((entry) => entry.level == AppLogLevel.warning)
            .toList(growable: false),
      _LevelFilter.error =>
        entries
            .where((entry) => entry.level == AppLogLevel.error)
            .toList(growable: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ValueListenableBuilder<List<AppLogEntry>>(
      valueListenable: widget.log.entries,
      builder: (context, entries, _) {
        final visible = _apply(entries);
        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              _buildHeader(context, s, entries),
              _buildFilters(context, s, entries),
              Expanded(child: _buildList(context, s, entries, visible)),
              _buildFooter(context, s, visible),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, S s, List<AppLogEntry> entries) {
    final onSurface = AppColors.onScaffold(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.cardBorder(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentOf(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.terminal,
              size: 18,
              color: AppColors.accentOf(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.diagnosticsTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${s.diagnosticsRecording} · ${entries.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.mutedText(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onMinimize != null)
            FxIconButton(
              tooltip: s.minimize,
              onPressed: widget.onMinimize,
              icon: const Icon(Icons.remove),
            ),
          FxIconButton(
            tooltip: s.copyAll,
            onPressed: entries.isEmpty ? null : () => _copyLogs(entries),
            icon: const Icon(Icons.copy_all_outlined),
          ),
          FxIconButton(
            tooltip: s.clearMemoryLog,
            onPressed: entries.isEmpty ? null : widget.log.clear,
            icon: const Icon(Icons.delete_outline),
          ),
          if (widget.onClose != null)
            FxIconButton(
              tooltip: s.closeDiagnostics,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, S s, List<AppLogEntry> entries) {
    int count(AppLogLevel level) =>
        entries.where((entry) => entry.level == level).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          _LevelPill(
            label: s.diagnosticsFilterAll,
            count: entries.length,
            selected: _filter == _LevelFilter.all,
            onTap: () => _selectFilter(_LevelFilter.all),
          ),
          const SizedBox(width: 8),
          _LevelPill(
            label: s.diagnosticsFilterWarnings,
            count: count(AppLogLevel.warning),
            tone: AppColors.warning,
            selected: _filter == _LevelFilter.warning,
            onTap: () => _selectFilter(_LevelFilter.warning),
          ),
          const SizedBox(width: 8),
          _LevelPill(
            label: s.diagnosticsFilterErrors,
            count: count(AppLogLevel.error),
            tone: AppColors.error,
            selected: _filter == _LevelFilter.error,
            onTap: () => _selectFilter(_LevelFilter.error),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    S s,
    List<AppLogEntry> entries,
    List<AppLogEntry> visible,
  ) {
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 34,
                color: AppColors.mutedText(context).withValues(alpha: 0.5),
              ),
              const SizedBox(height: 10),
              Text(
                s.noLog,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.mutedText(context),
                ),
              ),
              if (entries.isEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  s.diagnosticsEmptyHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.mutedText(context).withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            _scrollController.hasClients) {
          final position = _scrollController.position;
          final follow = position.maxScrollExtent - position.pixels < 48;
          if (follow != _followLatest) setState(() => _followLatest = follow);
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        itemCount: visible.length,
        itemBuilder: (context, index) => _LogRow(entry: visible[index]),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, S s, List<AppLogEntry> visible) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.cardBorder(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.diagnosticsHint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: AppColors.mutedText(context),
              ),
            ),
          ),
          if (!_followLatest)
            TextButton(
              onPressed: () {
                setState(() => _followLatest = true);
                _jumpToLatest();
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.accentOf(context),
              ),
              child: Text(
                s.diagnosticsJumpLatest,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.tone,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final accent = tone ?? AppColors.accentOf(context);
    final dim = count == 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : AppColors.fill2(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : AppColors.cardBorder(context),
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: dim
                ? AppColors.mutedText(context)
                : (selected ? accent : AppColors.secondaryText(context)),
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      AppLogLevel.info => AppColors.secondaryText(context),
      AppLogLevel.warning => AppColors.warning,
      AppLogLevel.error => AppColors.error,
    };
    final hasDetail = (entry.stackTrace ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.fill2(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: hasDetail ? 46 : 30,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.75),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatTime(entry.timestamp),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: AppColors.mutedText(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                entry.category,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  entry.message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.35,
                    color: color,
                  ),
                ),
                if (hasDetail) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    entry.stackTrace!,
                    maxLines: 6,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      height: 1.3,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
