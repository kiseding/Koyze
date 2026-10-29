import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../../l10n/app_strings.dart';
import '../../player/presentation/player_provider.dart';
import 'lyric_provider.dart';

/// 生成一张歌词卡片并导出成 PNG。
///
/// 没有引入 `share_plus`：多一个原生依赖就多一份打包风险，而「保存到相册 /
/// 文件」已经能满足分享需求（用户自己再发出去）。截图走离屏
/// `RepaintBoundary`，所以卡片上的字体、圆角与屏幕上看到的完全一致。
void showLyricShareSheet(BuildContext context, WidgetRef ref) {
  final music = ref.read(currentMusicProvider);
  if (music == null) return;
  final lyrics = ref.read(currentLyricProvider);
  final lineIndex = ref.read(currentLineIndexProvider);
  final line = lineIndex >= 0 && lineIndex < lyrics.lines.length
      ? lyrics.lines[lineIndex]
      : null;
  final text = (line?.text ?? '').trim();
  final previous = lineIndex > 0 && lineIndex - 1 < lyrics.lines.length
      ? lyrics.lines[lineIndex - 1].text.trim()
      : '';
  final next = lineIndex >= 0 && lineIndex + 1 < lyrics.lines.length
      ? lyrics.lines[lineIndex + 1].text.trim()
      : '';

  showKoyzeDialog<void>(
    context: context,
    builder: (context) => _LyricCardDialog(
      title: music.name,
      artist: music.singer,
      line: text.isEmpty ? S.of(context).lyricShareNoLine : text,
      previous: previous,
      next: next,
      artwork: music.artwork,
    ),
  );
}

class _LyricCardDialog extends StatefulWidget {
  const _LyricCardDialog({
    required this.title,
    required this.artist,
    required this.line,
    required this.previous,
    required this.next,
    this.artwork,
  });

  final String title;
  final String artist;
  final String line;
  final String previous;
  final String next;
  final String? artwork;

  @override
  State<_LyricCardDialog> createState() => _LyricCardDialogState();
}

class _LyricCardDialogState extends State<_LyricCardDialog> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final s = S.of(context);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = Uint8List.fromList(data.buffer.asUint8List());
      final fileName =
          'koyze_lyric_${DateTime.now().millisecondsSinceEpoch}.png';
      final path = await FilePicker.saveFile(
        dialogTitle: s.lyricShareSave,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: Platform.isIOS || Platform.isAndroid ? bytes : null,
      );
      if (path == null) return;
      if (!Platform.isIOS && !Platform.isAndroid) {
        await File(path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      showAppNotification(s.lyricShareSaved, type: AppNotificationType.success);
    } catch (error) {
      if (!mounted) return;
      showAppNotification(
        s.lyricShareFailed('$error'),
        type: AppNotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final dark = AppColors.isDark(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: _LyricCard(
                    title: widget.title,
                    artist: widget.artist,
                    line: widget.line,
                    previous: widget.previous,
                    next: widget.next,
                    dark: dark,
                    appName: 'Koyze',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(_saving ? s.savingNow : s.lyricShareSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricCard extends StatelessWidget {
  const _LyricCard({
    required this.title,
    required this.artist,
    required this.line,
    required this.previous,
    required this.next,
    required this.dark,
    required this.appName,
  });

  final String title;
  final String artist;
  final String line;
  final String previous;
  final String next;
  final bool dark;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final background = dark ? const Color(0xFF14161C) : const Color(0xFFF7F5F1);
    final foreground = dark ? const Color(0xFFF2F3F5) : const Color(0xFF1B1D22);
    final muted = foreground.withValues(alpha: 0.45);
    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: foreground.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '“',
            style: TextStyle(
              fontSize: 44,
              height: 0.8,
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            line,
            style: TextStyle(
              fontSize: 22,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          if (previous.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              previous,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
          if (next.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              next,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
          const SizedBox(height: 28),
          Container(height: 1, color: foreground.withValues(alpha: 0.08)),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: muted, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(appName, style: TextStyle(fontSize: 10, color: muted)),
            ],
          ),
        ],
      ),
    );
  }
}
