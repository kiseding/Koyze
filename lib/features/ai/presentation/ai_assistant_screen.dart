// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../domain/ai_agent.dart';
import '../domain/ai_chat.dart';
import '../domain/ai_tools.dart';
import 'ai_failure_text.dart';
import 'ai_provider.dart';

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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || ref.read(aiChatProvider).busy) return;
    _input.clear();
    ref.read(aiChatProvider.notifier).send(text);
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
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: s.back,
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.aiAssistantTitle,
              style: TextStyle(
                color: onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              config.model.trim().isEmpty
                  ? s.aiNotConfigured
                  : (config.allowActions
                        ? config.model.trim()
                        : s.aiAssistantReadOnly),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.mutedText(context),
              ),
            ),
          ],
        ),
        actions: [
          FxIconButton(
            tooltip: s.aiAssistantNewChat,
            icon: Icon(Icons.add_comment_outlined, color: onSurface),
            onPressed: chat.isEmpty
                ? null
                : () => ref.read(aiChatProvider.notifier).clear(),
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: chat.entries.length + (chat.busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= chat.entries.length) {
                        return _busyRow(context, s, chat.activeTool);
                      }
                      final entry = chat.entries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: entry.isUser
                            ? _userBubble(context, entry.text)
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

  Widget _userBubble(BuildContext context, String text) {
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
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: AppColors.onScaffold(context),
          ),
        ),
      ),
    );
  }

  Widget _assistantBubble(BuildContext context, S s, AiChatEntry entry) {
    final onSurface = AppColors.onScaffold(context);
    final failure = entry.failure;
    if (failure != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              aiFailureText(s, failure),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }

    final summary = _summarize(entry.toolRuns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final item in summary) _toolPill(context, s, item)],
          ),
          if (entry.text.isNotEmpty) const SizedBox(height: 8),
        ],
        if (entry.text.isNotEmpty)
          Text(
            entry.text,
            style: TextStyle(fontSize: 14, height: 1.6, color: onSurface),
          ),
      ],
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

  Widget _busyRow(BuildContext context, S s, AiToolCategory? activeTool) {
    final label = activeTool == null
        ? s.aiAssistantThinking
        : s.aiAssistantWorking(_categoryLabel(s, activeTool));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accentOf(context),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.mutedText(context)),
          ),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, S s, AiChatState chat) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                enabled: !chat.busy,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: s.aiAssistantPlaceholder,
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
            IgnorePointer(
              ignoring: chat.busy,
              child: IconButton.filled(
                onPressed: _send,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accentOf(context),
                  foregroundColor: AppColors.isDark(context)
                      ? Colors.black
                      : Colors.white,
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
          ],
        ),
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
    AiToolCategory.settings => Icons.tune_rounded,
  };

  static String _categoryLabel(S s, AiToolCategory category) =>
      switch (category) {
        AiToolCategory.library => s.aiCategoryLibrary,
        AiToolCategory.playback => s.aiCategoryPlayback,
        AiToolCategory.playlist => s.aiCategoryPlaylist,
        AiToolCategory.download => s.aiCategoryDownload,
        AiToolCategory.source => s.aiCategorySource,
        AiToolCategory.settings => s.aiCategorySettings,
      };
}
