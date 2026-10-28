// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../l10n/app_strings.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../domain/ai_config.dart';
import '../domain/ai_playlist_planner.dart';
import '../domain/ai_tools.dart';
import 'ai_failure_text.dart';
import 'ai_provider.dart';

enum _Stage { idle, planning, matching, ready }

/// 一句话描述 → AI 给歌单 → 逐首搜到真歌 → 建歌单。
class AiPlaylistScreen extends ConsumerStatefulWidget {
  const AiPlaylistScreen({super.key});

  @override
  ConsumerState<AiPlaylistScreen> createState() => _AiPlaylistScreenState();
}

class _AiPlaylistScreenState extends ConsumerState<AiPlaylistScreen> {
  final _prompt = TextEditingController();
  final Set<int> _selected = {};

  _Stage _stage = _Stage.idle;
  AiPlaylistDraft? _draft;
  List<AiSongMatch> _matches = const [];
  int _matchedDone = 0;
  int _matchedTotal = 0;
  String? _activeTool;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  bool get _busy => _stage == _Stage.planning || _stage == _Stage.matching;

  Future<void> _generate() async {
    final s = S.of(context);
    final request = _prompt.text.trim();
    if (request.isEmpty) return;

    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      showAppNotification(s.aiNotConfigured, type: AppNotificationType.warning);
      return;
    }
    final notifier = ref.read(aiConfigProvider.notifier);
    final key = await notifier.loadKey();
    if (key == null || key.isEmpty) {
      if (!mounted) return;
      showAppNotification(s.aiNotConfigured, type: AppNotificationType.warning);
      return;
    }

    setState(() {
      _stage = _Stage.planning;
      _draft = null;
      _matches = const [];
      _selected.clear();
      _activeTool = null;
    });

    try {
      final planner = ref.read(aiPlannerProvider);
      final draft = config.toolsEnabled
          ? await planner.planWithTools(
              config: config,
              apiKey: key,
              request: request,
              toolbox: ref.read(aiToolboxProvider),
              onToolCall: (call) {
                if (!mounted) return;
                setState(() => _activeTool = _toolLabel(s, call.name));
              },
            )
          : await planner.plan(config: config, apiKey: key, request: request);
      if (!mounted) return;
      if (draft.isEmpty) {
        setState(() => _stage = _Stage.idle);
        showAppNotification(s.aiEmptyResult, type: AppNotificationType.warning);
        return;
      }
      setState(() {
        _draft = draft;
        _stage = _Stage.matching;
        _matchedDone = 0;
        _matchedTotal = draft.songs.length;
      });

      final matches = await ref
          .read(aiMatcherProvider)
          .match(
            draft.songs,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _matchedDone = done;
                _matchedTotal = total;
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _stage = _Stage.ready;
        for (var index = 0; index < matches.length; index++) {
          if (matches[index].matched) _selected.add(index);
        }
      });
      if (_selected.isEmpty) {
        showAppNotification(s.aiEmptyResult, type: AppNotificationType.warning);
      }
    } on AiException catch (error) {
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      showAppNotification(
        aiFailureText(s, error.kind),
        type: AppNotificationType.error,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.idle);
      showAppNotification(s.aiErrorNetwork, type: AppNotificationType.error);
    }
  }

  Future<void> _create() async {
    final s = S.of(context);
    final draft = _draft;
    if (draft == null || _selected.isEmpty) return;
    final songs = [
      for (final index in _selected.toList()..sort())
        if (_matches[index].song != null) _matches[index].song!,
    ];
    if (songs.isEmpty) return;

    setState(() => _stage = _Stage.planning);
    try {
      await ref
          .read(playlistServiceProvider)
          .createPlaylist(
            name: draft.name,
            description: draft.description.isEmpty ? null : draft.description,
            songs: songs,
          );
      if (!mounted) return;
      showAppNotification(
        s.aiCreated(draft.name),
        type: AppNotificationType.success,
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      showAppNotification(s.aiErrorNetwork, type: AppNotificationType.error);
    }
  }

  /// 工具名 → 界面上的中文动作名，没登记的直接显示原名。
  static String _toolLabel(S s, String name) => switch (name) {
    AiToolbox.searchLibrary => s.aiToolSearchLibrary,
    AiToolbox.listPlaylists => s.aiToolListPlaylists,
    AiToolbox.getPlaylist => s.aiToolGetPlaylist,
    AiToolbox.sourceStatus => s.aiToolSourceStatus,
    AiToolbox.createPlaylistTool => s.aiToolCreatePlaylist,
    _ => name,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onSurface = AppColors.onScaffold(context);
    final draft = _draft;

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
          s.aiPlaylistTitle,
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _prompt,
            enabled: !_busy,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: s.aiPromptLabel,
              hintText: s.aiPromptHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(_busy ? s.aiGenerating : s.aiGenerate),
          ),
          if (_stage == _Stage.planning) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 4),
            if (_activeTool != null) ...[
              const SizedBox(height: 8),
              Text(
                s.aiToolRunning(_activeTool!),
                style: TextStyle(
                  fontSize: 12,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
          if (_stage == _Stage.matching) ...[
            const SizedBox(height: 16),
            Text(
              s.aiMatching(_matchedDone, _matchedTotal),
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _matchedTotal == 0 ? null : _matchedDone / _matchedTotal,
              minHeight: 4,
            ),
          ],
          if (draft != null) ...[
            const SizedBox(height: 24),
            Text(
              draft.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
            if (draft.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                draft.description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              s.aiMatchedCount(
                _matches.where((match) => match.matched).length,
                _matches.length,
              ),
              style: TextStyle(
                fontSize: 12,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < _matches.length; index++)
              _MatchRow(
                match: _matches[index],
                selected: _selected.contains(index),
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          if (value) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        });
                      },
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _create,
              child: Text(s.aiCreatePlaylist),
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.selected,
    required this.onChanged,
  });

  final AiSongMatch match;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final onSurface = AppColors.onScaffold(context);
    final song = match.song;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            onChanged: song == null || onChanged == null
                ? null
                : (value) => onChanged!(value ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song?.name ?? match.request.title,
                    style: TextStyle(
                      fontSize: 14,
                      color: onSurface.withValues(
                        alpha: song == null ? 0.45 : 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song == null
                        ? s.aiSongUnmatched(
                            match.request.artist.isEmpty
                                ? match.request.title
                                : '${match.request.title} · ${match.request.artist}',
                          )
                        : '${song.singer} · ${s.platformText(song.platform)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  if (match.request.reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      match.request.reason,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
