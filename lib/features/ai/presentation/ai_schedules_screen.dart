// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ai_config.dart';
import '../domain/ai_schedule.dart';
import 'ai_failure_text.dart';
import 'ai_schedule_provider.dart';

/// AI 定时任务列表。
///
/// 一条任务就是「一句话 + 一个时间」：到点助手自己去执行那话，结果写回卡片
/// 和对话里。这里不放复杂的编排，任务之间互不依赖。
class AiSchedulesScreen extends ConsumerWidget {
  const AiSchedulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final tasks = ref.watch(aiSchedulesProvider);
    final onSurface = AppColors.onScaffold(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: s.back,
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          s.aiSchedulesTitle,
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          FxIconButton(
            tooltip: s.aiSchedulesNew,
            icon: Icon(Icons.add_rounded, color: onSurface),
            onPressed: () => showAiScheduleEditor(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: tasks.isEmpty
          ? _emptyState(context, s)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
                  child: Text(
                    s.aiSchedulesIntro,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.55,
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ScheduleCard(task: task),
                  ),
              ],
            ),
    );
  }

  Widget _emptyState(BuildContext context, S s) {
    final accent = AppColors.accentOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.alarm_rounded, size: 26, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              s.aiSchedulesEmpty,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onScaffold(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.aiSchedulesEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.mutedText(context),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showAiScheduleEditor(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(s.aiSchedulesNew),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends ConsumerStatefulWidget {
  const _ScheduleCard({required this.task});

  final AiScheduledTask task;

  @override
  ConsumerState<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends ConsumerState<_ScheduleCard> {
  bool _running = false;

  Future<void> _runNow() async {
    if (_running) return;
    setState(() => _running = true);
    final s = S.of(context);
    try {
      final result = await ref
          .read(aiScheduleRunnerProvider)
          .runNow(widget.task);
      if (!mounted || result.skipped) return;
      showAppNotification(
        result.ok
            ? s.aiScheduleRunDone(widget.task.title)
            : s.aiScheduleRunFailedToast(widget.task.title),
        type: result.ok ? AppNotificationType.success : AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final task = widget.task;
    final accent = AppColors.accentOf(context);
    final muted = AppColors.mutedText(context);
    final onSurface = AppColors.onScaffold(context);
    final status = _statusLine(task, s, context);

    return GlassSurface(
      style: AppGlassStyle.regular,
      borderRadius: BorderRadius.circular(18),
      border: Border.fromBorderSide(AppGlass.hairline(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showAiScheduleEditor(context, task: task),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间是这条任务的主语，给足字号。
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.timeLabel,
                        style: TextStyle(
                          fontSize: 21,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: task.enabled
                              ? onSurface
                              : muted.withValues(alpha: 0.6),
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _repeatLabel(task, s),
                        style: TextStyle(fontSize: 10.5, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: task.enabled
                                ? onSurface
                                : muted.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          task.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: muted,
                          ),
                        ),
                        if (status != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                task.lastOk == false
                                    ? Icons.error_outline_rounded
                                    : Icons.history_rounded,
                                size: 11,
                                color: task.lastOk == false
                                    ? Theme.of(context).colorScheme.error
                                    : muted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: task.lastOk == false
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.error
                                        : muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: FxSwitch(
                      value: task.enabled,
                      activeColor: accent,
                      inactiveTrackColor: AppColors.isDark(context)
                          ? AppColors.surfaceVariant
                          : AppColors.lightSurfaceVariant,
                      onChanged: (value) => ref
                          .read(aiSchedulesProvider.notifier)
                          .setEnabled(task.id, value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 12, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task.enabled
                          ? _nextRunText(task, s)
                          : s.aiSchedulePaused,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  if (_running)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            s.aiScheduleRunning,
                            style: TextStyle(fontSize: 11, color: accent),
                          ),
                        ],
                      ),
                    )
                  else
                    IconButton(
                      tooltip: s.aiScheduleRunNow,
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      color: accent,
                      onPressed: _runNow,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  PopupMenuButton<String>(
                    tooltip: '',
                    iconSize: 18,
                    color: AppColors.dialogBg(context),
                    icon: Icon(Icons.more_horiz_rounded, color: muted),
                    onSelected: (value) async {
                      switch (value) {
                        case 'edit':
                          await showAiScheduleEditor(context, task: task);
                        case 'delete':
                          await _confirmDelete(context, s);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          s.aiSchedulesEdit,
                          style: TextStyle(color: onSurface, fontSize: 13),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          s.aiScheduleDelete,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, S s) async {
    final confirmed = await showKoyzeDialog<bool>(
      context: context,
      builder: (dialogContext) => KoyzeDialog(
        backgroundColor: AppColors.dialogBg(context),
        title: Text(
          s.aiScheduleDelete,
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        content: Text(
          s.aiScheduleDeleteConfirm(widget.task.title),
          style: TextStyle(
            color: AppColors.secondaryText(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              s.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(aiSchedulesProvider.notifier).remove(widget.task.id);
    if (!mounted) return;
    showAppNotification(s.aiScheduleDeleted);
  }

  static String _repeatLabel(AiScheduledTask task, S s) =>
      switch (task.cadence) {
        AiScheduleCadence.daily => s.aiScheduleDaily,
        AiScheduleCadence.weekdays => s.aiScheduleWeekdays,
        AiScheduleCadence.weekly =>
          '${s.aiScheduleWeekly} · ${s.weekdayName(task.weekday)}',
      };

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _clock(DateTime time) =>
      '${_two(time.hour)}:${_two(time.minute)}';

  String _nextRunText(AiScheduledTask task, S s) {
    final now = DateTime.now();
    final next = task.nextRunAfter(now);
    return s.aiScheduleNextRun('${s.relativeDay(next, now: now)} ${_clock(next)}');
  }

  /// 卡片上那行「上次…」。失败时把原因说清楚，否则只给结果的第一句。
  static String? _statusLine(
    AiScheduledTask task,
    S s,
    BuildContext context,
  ) {
    final last = task.lastRunAt;
    if (last == null) return s.aiScheduleNeverRun;
    final when = '${s.relativeDay(last)} ${_clock(last)}';
    if (task.lastOk == false) {
      final kind = AiFailureKind.values.firstWhere(
        (value) => value.name == task.lastFailure,
        orElse: () => AiFailureKind.network,
      );
      return s.aiScheduleRunFailed(aiFailureText(s, kind));
    }
    final result = (task.lastResult ?? '').trim();
    if (result.isEmpty) return s.aiScheduleLastRun(when);
    return result.replaceAll('\n', ' ');
  }
}

/// 新建 / 编辑面板。
Future<void> showAiScheduleEditor(
  BuildContext context, {
  AiScheduledTask? task,
}) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ScheduleEditor(task: task),
  );
}

class _ScheduleEditor extends ConsumerStatefulWidget {
  const _ScheduleEditor({this.task});

  final AiScheduledTask? task;

  @override
  ConsumerState<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends ConsumerState<_ScheduleEditor> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late TimeOfDay _time;
  late AiScheduleCadence _cadence;
  late int _weekday;

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _name = TextEditingController(text: task?.title ?? '');
    _prompt = TextEditingController(text: task?.prompt ?? '');
    final hour = task?.hour ?? 8;
    final minute = task?.minute ?? 0;
    _time = TimeOfDay(hour: hour, minute: minute);
    _cadence = task?.cadence ?? AiScheduleCadence.daily;
    _weekday = task?.weekday ?? DateTime.monday;
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _save() async {
    final s = S.of(context);
    final name = _name.text.trim();
    final prompt = _prompt.text.trim();
    if (name.isEmpty) {
      showAppNotification(
        s.aiScheduleNameRequired,
        type: AppNotificationType.error,
      );
      return;
    }
    if (prompt.isEmpty) {
      showAppNotification(
        s.aiSchedulePromptRequired,
        type: AppNotificationType.error,
      );
      return;
    }
    final minuteOfDay = _time.hour * 60 + _time.minute;
    final notifier = ref.read(aiSchedulesProvider.notifier);
    final task = widget.task;
    if (task == null) {
      await notifier.add(
        AiScheduledTask(
          id: AiSchedulesNotifier.newId(),
          title: name,
          prompt: prompt,
          minuteOfDay: minuteOfDay,
          cadence: _cadence,
          weekday: _weekday,
        ),
      );
    } else {
      await notifier.update(
        task.copyWith(
          title: name,
          prompt: prompt,
          minuteOfDay: minuteOfDay,
          cadence: _cadence,
          weekday: _weekday,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    showAppNotification(s.aiScheduleSaved, type: AppNotificationType.success);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final muted = AppColors.mutedText(context);
    return Padding(
      // 键盘顶起来时保存按钮不能被挡住。
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KoyzeSheetGrabber(),
            KoyzeSheetTitle(
              title: _isEditing ? s.aiSchedulesEdit : s.aiSchedulesNew,
              onClose: () => Navigator.pop(context),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      maxLength: AiScheduledTask.maxTitleLength,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: s.aiScheduleName,
                        hintText: s.aiScheduleNameHint,
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _prompt,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: AiScheduledTask.maxPromptLength,
                      decoration: InputDecoration(
                        labelText: s.aiSchedulePrompt,
                        hintText: s.aiSchedulePromptHint,
                        alignLabelWithHint: true,
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      s.aiScheduleTime,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(
                        '${_time.hour.toString().padLeft(2, '0')}:'
                        '${_time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.aiScheduleRepeat,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _cadenceChip(s.aiScheduleDaily, AiScheduleCadence.daily),
                        _cadenceChip(
                          s.aiScheduleWeekdays,
                          AiScheduleCadence.weekdays,
                        ),
                        _cadenceChip(s.aiScheduleWeekly, AiScheduleCadence.weekly),
                      ],
                    ),
                    if (_cadence == AiScheduleCadence.weekly) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var day = 1; day <= 7; day++)
                            _weekdayChip(s.weekdayName(day), day),
                        ],
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _save,
                      child: Text(s.save),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cadenceChip(String label, AiScheduleCadence value) {
    final selected = _cadence == value;
    final accent = AppColors.accentOf(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _cadence = value),
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: selected ? accent : AppColors.onScaffold(context),
      ),
      selectedColor: accent.withValues(
        alpha: AppColors.isDark(context) ? 0.20 : 0.14,
      ),
      backgroundColor: AppColors.fill(context),
      side: BorderSide(
        color: selected ? accent.withValues(alpha: 0.45) : Colors.transparent,
        width: 0.9,
      ),
      showCheckmark: false,
    );
  }

  Widget _weekdayChip(String label, int day) {
    final selected = _weekday == day;
    final accent = AppColors.accentOf(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _weekday = day),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? accent : AppColors.onScaffold(context),
      ),
      selectedColor: accent.withValues(
        alpha: AppColors.isDark(context) ? 0.20 : 0.14,
      ),
      backgroundColor: AppColors.fill(context),
      side: BorderSide(
        color: selected ? accent.withValues(alpha: 0.45) : Colors.transparent,
        width: 0.9,
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }
}
