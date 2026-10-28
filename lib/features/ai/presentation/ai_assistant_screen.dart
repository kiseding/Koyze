// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ai_agent.dart';
import '../domain/ai_chat.dart';
import '../domain/ai_config.dart';
import '../domain/ai_tools.dart';
import 'ai_failure_text.dart';
import 'ai_provider.dart';
import 'voice_recorder.dart';

/// 对话式助手：一句话说清楚要做什么，模型通过后台接口把操作做完。
///
/// 页面只负责显示和输入，所有动作都发生在 [AiToolbox] 背后的服务层，
/// 所以这里没有任何「模拟点击某个按钮」的路径。
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// 录音状态。录完不再转文字，而是把这段 wav 挂在下一条消息上一起发出去。
  bool _recording = false;
  AiVoiceClip? _clip;
  DateTime? _recordStartedAt;
  Timer? _ticker;

  /// 一口气录满一分钟就自动收尾：再长既费流量也没有更多信息。
  static const Duration _maxRecordLength = Duration(seconds: 60);

  /// 在 initState 里取一次：dispose 时还要用它把麦克风关掉，
  /// 那时候再 ref.read 就已经晚了。
  AiVoiceRecorder? _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = ref.read(aiVoiceRecorderProvider);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _input.dispose();
    _scroll.dispose();
    // 页面退出时还在录的直接放弃，挂着的临时文件一并删掉。
    unawaited(_recorder?.cancel() ?? Future<void>.value());
    unawaited(discardVoiceClip(_clip));
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    final clip = _clip;
    if ((text.isEmpty && clip == null) || ref.read(aiChatProvider).busy) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    if (_recording) {
      _recording = false;
      unawaited(_recorder?.cancel() ?? Future<void>.value());
    }
    _input.clear();
    setState(() => _clip = null);
    ref.read(aiChatProvider.notifier).send(text, voice: clip);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    final s = S.of(context);
    final recorder = _recorder;
    if (recorder == null || !recorder.isSupported) {
      showAppNotification(s.aiVoiceUnavailable, type: AppNotificationType.error);
      return;
    }
    if (_clip != null) await _dropClip();
    unawaited(HapticFeedback.selectionClick());
    final started = await recorder.start();
    if (!mounted) return;
    if (!started) {
      showAppNotification(s.aiVoiceFailed, type: AppNotificationType.error);
      return;
    }
    setState(() {
      _recording = true;
      _recordStartedAt = DateTime.now();
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final started = _recordStartedAt;
      if (started == null) return;
      setState(() {});
      if (DateTime.now().difference(started) >= _maxRecordLength) {
        unawaited(_stopRecording());
      }
    });
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    _ticker = null;
    if (!_recording) return;
    setState(() => _recording = false);
    final clip = await _recorder?.stop();
    if (!mounted) return;
    if (clip == null) {
      showAppNotification(S.of(context).aiVoiceTooShort);
      return;
    }
    setState(() => _clip = clip);
  }

  Future<void> _dropClip() async {
    final clip = _clip;
    if (clip == null) return;
    setState(() => _clip = null);
    unawaited(HapticFeedback.selectionClick());
    await discardVoiceClip(clip);
  }

  /// 录音计时，界面上的 `0:07`。
  Duration get _recordedFor {
    final started = _recordStartedAt;
    if (started == null) return Duration.zero;
    final elapsed = DateTime.now().difference(started);
    return elapsed > _maxRecordLength ? _maxRecordLength : elapsed;
  }

  /// `312 KB` / `1.9 MB`：给气泡看的大小，不用精确到字节。
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  static String _clock(Duration duration) {
    final minutes = duration.inSeconds ~/ 60;
    final rest = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final chat = ref.watch(aiChatProvider);
    final config = ref.watch(aiConfigProvider);
    final onSurface = AppColors.onScaffold(context);

    ref.listen<AiChatState>(aiChatProvider, (previous, next) {
      if (previous?.entries.length != next.entries.length) _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: s.back,
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        // 标题和「用的哪个模型」都居中：这两行是这一页的身份说明，
        // 靠左时会被返回键和右侧两个按钮挤成一小块。
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              s.aiAssistantTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 2),
            _ModelLine(config: config, s: s),
          ],
        ),
        actions: [
          FxIconButton(
            tooltip: s.aiAssistantNewChat,
            icon: Icon(Icons.add_comment_outlined, color: onSurface),
            onPressed: chat.isEmpty
                ? null
                : () {
                    // 新对话等于放弃还没发出的那段语音。
                    _ticker?.cancel();
                    _ticker = null;
                    if (_recording) {
                      _recording = false;
                      unawaited(_recorder?.cancel() ?? Future<void>.value());
                    }
                    unawaited(_dropClip());
                    ref.read(aiChatProvider.notifier).clear();
                  },
          ),
          FxIconButton(
            tooltip: s.aiSettingsTitle,
            icon: Icon(Icons.tune_rounded, color: onSurface),
            onPressed: () => context.push('/ai-settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!config.isConfigured) _configBanner(context, s),
          Expanded(
            child: chat.entries.isEmpty && !chat.busy
                ? _emptyState(context, s)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    itemCount: chat.entries.length + (chat.busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= chat.entries.length) {
                        return _busyBubble(context, s, chat.activeTool);
                      }
                      final entry = chat.entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: entry.isUser
                            ? _userBubble(context, s, entry)
                            : _assistantBubble(context, s, entry),
                      );
                    },
                  ),
          ),
          _composer(context, s, chat),
        ],
      ),
    );
  }

  Widget _configBanner(BuildContext context, S s) {
    final accent = AppColors.accentOf(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.aiNotConfigured,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onScaffold(context),
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/ai-settings'),
            child: Text(s.aiSettingsTitle),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context, S s) {
    final onSurface = AppColors.onScaffold(context);
    final examples = [
      s.aiAssistantExample1,
      s.aiAssistantExample2,
      s.aiAssistantExample3,
      s.aiAssistantExample4,
      s.aiAssistantExample5,
      s.aiAssistantExample6,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Icon(Icons.auto_awesome, size: 32, color: AppColors.accentOf(context)),
        const SizedBox(height: 18),
        Text(
          s.aiAssistantEmptyTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          s.aiAssistantEmptyHint,
          style: TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.mutedText(context),
          ),
        ),
        const SizedBox(height: 22),
        for (final example in examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _send(example),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                side: BorderSide(color: AppColors.cardBorder(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.north_east_rounded,
                    size: 14,
                    color: AppColors.mutedText(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      example,
                      style: TextStyle(fontSize: 13, color: onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _userBubble(BuildContext context, S s, AiChatEntry entry) {
    final accent = AppColors.accentOf(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: AppColors.isDark(context) ? 0.28 : 0.16,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (entry.voiceSeconds case final seconds?) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq_rounded, size: 14, color: accent),
                  const SizedBox(width: 5),
                  Text(
                    // 带上实际发出去的体积：收不到音频时，这一行能直接回答
                    // 「是没传过去还是接口丢了」——有数字就是进了请求体。
                    entry.voiceBytes == null
                        ? s.aiVoiceClip(seconds)
                        : '${s.aiVoiceClip(seconds)} · '
                              '${s.aiVoiceSent(_formatBytes(entry.voiceBytes!))}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onScaffold(context),
                    ),
                  ),
                ],
              ),
              if (entry.text.isNotEmpty) const SizedBox(height: 6),
            ],
            if (entry.text.isNotEmpty)
              Text(
                entry.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.onScaffold(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 助手也用气泡，和用户正好左右对称。
  ///
  /// 里面按「来源 → 做了什么 → 说了什么」竖着排：定时任务的来源标签在最上面，
  /// 工具摘要其次，正文最后。整块用一个气泡包住，滚动时不会看成三条独立的消息。
  /// 「接口把音频丢了」这条提示，附带实际发出去的体积。
  Widget _voiceLostNote(BuildContext context, S s, int? bytes) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.26), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mic_off_rounded, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              s.aiVoiceDropped(bytes == null ? '—' : _formatBytes(bytes)),
              style: TextStyle(fontSize: 11.5, height: 1.5, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantBubble(BuildContext context, S s, AiChatEntry entry) {
    final onSurface = AppColors.onScaffold(context);
    final failure = entry.failure;
    final isError = failure != null;
    final errorColor = Theme.of(context).colorScheme.error;
    final summary = isError
        ? const <({AiToolCategory category, int count, bool ok})>[]
        : _summarize(entry.toolRuns);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
        decoration: BoxDecoration(
          color: isError
              ? errorColor.withValues(alpha: 0.10)
              : AppColors.fill(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: isError
                ? errorColor.withValues(alpha: 0.34)
                : AppColors.cardBorder(context),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.scheduleTitle case final title?) ...[
              _schedulePill(context, s, title),
              const SizedBox(height: 8),
            ],
            if (summary.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in summary) _toolPill(context, s, item),
                ],
              ),
              if (entry.text.isNotEmpty) const SizedBox(height: 9),
            ],
            if (isError)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 15, color: errorColor),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          aiFailureText(s, failure),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: errorColor,
                          ),
                        ),
                        if (entry.detail case final detail?) ...[
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: errorColor.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            else if (entry.text.isNotEmpty)
              Text(
                entry.text,
                style: TextStyle(fontSize: 14, height: 1.55, color: onSurface),
              ),
            // 模型说没收到音频时补一句诊断：录音已经发出去了，是接口丢的。
            // 不加这句，用户只能反复重录，永远查不到原因。
            if (entry.voiceLost) ...[
              if (entry.text.isNotEmpty) const SizedBox(height: 9),
              _voiceLostNote(context, s, entry.voiceBytes),
            ],
          ],
        ),
      ),
    );
  }

  Widget _schedulePill(BuildContext context, S s, String title) {
    final accent = AppColors.accentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppColors.isDark(context) ? 0.20 : 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alarm_rounded, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            s.aiSchedulePill(title),
            style: TextStyle(fontSize: 11, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _toolPill(
    BuildContext context,
    S s,
    ({AiToolCategory category, int count, bool ok}) item,
  ) {
    final accent = AppColors.accentOf(context);
    final color = item.ok ? accent : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fill2(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_categoryIcon(item.category), size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '${_categoryLabel(s, item.category)} · '
            '${s.aiAssistantToolCount(item.count)}',
            style: TextStyle(fontSize: 11, color: AppColors.mutedText(context)),
          ),
        ],
      ),
    );
  }

  Widget _busyBubble(BuildContext context, S s, AiToolCategory? activeTool) {
    final label = activeTool == null
        ? s.aiAssistantThinking
        : s.aiAssistantWorking(_categoryLabel(s, activeTool));
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 10, 14, 10),
        decoration: BoxDecoration(
          color: AppColors.fill(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: AppColors.cardBorder(context), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentOf(context),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.mutedText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, S s, AiChatState chat) {
    final voice = ref.watch(aiVoiceRecorderProvider);
    final accent = AppColors.accentOf(context);
    final clip = _clip;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (clip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _voiceChip(context, s, clip),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (voice.isSupported) ...[
                  _MicButton(
                    recording: _recording,
                    accent: accent,
                    onTap: chat.busy ? null : _toggleRecord,
                    tooltip: _recording ? s.aiVoiceStop : s.aiVoiceStart,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !chat.busy,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _recording
                          ? s.aiVoiceRecording(_clock(_recordedFor))
                          : clip != null
                          ? s.aiVoiceReady
                          : s.aiAssistantPlaceholder,
                      hintStyle: _recording
                          ? TextStyle(fontSize: 14, color: accent)
                          : null,
                      filled: true,
                      fillColor: AppColors.fill(context),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 只有真的有东西可发时按钮才亮：一段语音、一句文字都算。
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, _) {
                    final ready =
                        value.text.trim().isNotEmpty || _clip != null;
                    return IgnorePointer(
                      ignoring: chat.busy || !ready,
                      child: IconButton.filled(
                        onPressed: ready ? _send : null,
                        style: IconButton.styleFrom(
                          backgroundColor: ready
                              ? accent
                              : accent.withValues(alpha: 0.35),
                          foregroundColor: AppColors.isDark(context)
                              ? Colors.black
                              : Colors.white,
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 待发送的那段语音。录音发完就删，所以这里只能放/删，不能重听。
  Widget _voiceChip(BuildContext context, S s, AiVoiceClip clip) {
    final accent = AppColors.accentOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: AppColors.isDark(context) ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq_rounded, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            s.aiVoiceClip(clip.seconds),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.onScaffold(context),
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: s.aiVoiceRemove,
            child: InkResponse(
              onTap: _dropClip,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: AppColors.mutedText(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<({AiToolCategory category, int count, bool ok})> _summarize(
    List<AiToolRun> runs,
  ) {
    final order = <AiToolCategory>[];
    final counts = <AiToolCategory, int>{};
    final failed = <AiToolCategory, int>{};
    for (final run in runs) {
      if (!counts.containsKey(run.category)) order.add(run.category);
      counts[run.category] = (counts[run.category] ?? 0) + 1;
      if (!run.ok) failed[run.category] = (failed[run.category] ?? 0) + 1;
    }
    return [
      for (final category in order)
        (
          category: category,
          count: counts[category] ?? 0,
          ok: (failed[category] ?? 0) == 0,
        ),
    ];
  }

  static IconData _categoryIcon(AiToolCategory category) => switch (category) {
    AiToolCategory.library => Icons.search_rounded,
    AiToolCategory.playback => Icons.play_arrow_rounded,
    AiToolCategory.playlist => Icons.queue_music_rounded,
    AiToolCategory.download => Icons.download_rounded,
    AiToolCategory.source => Icons.extension_rounded,
    AiToolCategory.recommendation => Icons.auto_awesome_rounded,
    AiToolCategory.settings => Icons.tune_rounded,
  };

  static String _categoryLabel(S s, AiToolCategory category) =>
      switch (category) {
        AiToolCategory.library => s.aiCategoryLibrary,
        AiToolCategory.playback => s.aiCategoryPlayback,
        AiToolCategory.playlist => s.aiCategoryPlaylist,
        AiToolCategory.download => s.aiCategoryDownload,
        AiToolCategory.source => s.aiCategorySource,
        AiToolCategory.recommendation => s.aiCategoryRecommendation,
        AiToolCategory.settings => s.aiCategorySettings,
      };
}

/// 标题下面那行：一个小圆点 + 模型名（或状态）。
///
/// 点用颜色说话——能动手是强调色，只读是灰的，没配是错误色——文字仍然只有
/// 一行，居中，长模型名用省略号收尾。
class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.config, required this.s});

  final AiConfig config;
  final S s;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedText(context);
    final (color, label) = config.model.trim().isEmpty
        ? (Theme.of(context).colorScheme.error, s.aiNotConfigured)
        : config.allowActions
        ? (AppColors.accentOf(context), config.model.trim())
        : (muted, s.aiAssistantReadOnly);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted, height: 1.1),
          ),
        ),
      ],
    );
  }
}

/// 输入框左边的麦克风：按住说话那次不做了，点一下开、再点一下收。
class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.recording,
    required this.accent,
    required this.onTap,
    required this.tooltip,
  });

  final bool recording;
  final Color accent;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: recording
                  ? accent.withValues(alpha: 0.16)
                  : AppColors.fill(context),
              shape: BoxShape.circle,
              border: Border.all(
                color: recording ? accent.withValues(alpha: 0.5) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Icon(
              recording ? Icons.stop_rounded : Icons.mic_none_rounded,
              size: 20,
              color: !enabled
                  ? AppColors.mutedText(context).withValues(alpha: 0.4)
                  : recording
                  ? accent
                  : AppColors.secondaryText(context),
            ),
          ),
        ),
      ),
    );
  }
}
