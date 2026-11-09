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
                  child: LyricShareCard(
                    title: widget.title,
                    artist: widget.artist,
                    line: widget.line,
                    previous: widget.previous,
                    next: widget.next,
                    dark: dark,
                    appName: 'Koyze',
                    artwork: widget.artwork,
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

/// 歌词分享卡片本体。
///
/// 单独公开是为了能在测试里直接渲染并导出 PNG：分享图一旦有渲染问题
/// （比如继承了外层的下划线、封面加载失败留空洞），用户保存下来的图就是脏的，
/// 事后无法修补。渲染测试能把这些挡在发布前。
class LyricShareCard extends StatelessWidget {
  const LyricShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.line,
    required this.previous,
    required this.next,
    required this.dark,
    required this.appName,
    this.artwork,
  });

  final String title;
  final String artist;
  final String line;
  final String previous;
  final String next;
  final bool dark;
  final String appName;
  final String? artwork;

  /// 卡片里的所有文字都显式关掉下划线。
  ///
  /// 这里不是多此一举：`Text` 会把自身样式 merge 到上层 `DefaultTextStyle` 上，
  /// 只要祖先（主题、系统文字样式、某个包裹层）带了下划线，卡片上的每一行都会
  /// 被画上一条装饰线——分享图是导出成 PNG 的，脏了就洗不掉。
  TextStyle _text({
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      decoration: TextDecoration.none,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final background = dark
        ? const [Color(0xFF191B22), Color(0xFF0E1014)]
        : const [Color(0xFFFDFCF9), Color(0xFFF1EDE4)];
    final foreground = dark ? const Color(0xFFF3F4F6) : const Color(0xFF14161B);
    final muted = foreground.withValues(alpha: dark ? 0.58 : 0.44);

    return Container(
      width: 336,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: background,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: foreground.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 右上角的柔光：给纯色底一点纵深，同时把主题色带进画面。
          Positioned(
            top: -78,
            right: -56,
            child: IgnorePointer(
              child: Container(
                width: 208,
                height: 208,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: dark ? 0.30 : 0.16),
                      accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      appName.toUpperCase(),
                      style: _text(
                        size: 10,
                        color: muted,
                        weight: FontWeight.w700,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (previous.isNotEmpty) ...[
                  Text(
                    previous,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(size: 13, color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 7),
                ],
                Text(
                  line,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: _text(
                    size: 23,
                    color: foreground,
                    weight: FontWeight.w700,
                    height: 1.35,
                    letterSpacing: -0.3,
                  ),
                ),
                if (next.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    next,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(size: 13, color: muted, height: 1.4),
                  ),
                ],
                const SizedBox(height: 22),
                Container(height: 1, color: foreground.withValues(alpha: 0.08)),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _Artwork(url: artwork, accent: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(
                              size: 14,
                              color: foreground,
                              weight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _text(size: 12, color: muted, height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面缩略图。拿不到图时退回一块主题色渐变 + 波形图标，
/// 导出的 PNG 里也不会留下一个空洞。
class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.accent});

  final String? url;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.92),
            accent.withValues(alpha: 0.48),
          ],
        ),
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: 20,
        color: Colors.white.withValues(alpha: 0.92),
      ),
    );
    final source = url?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 44,
        height: 44,
        child: source.isEmpty
            ? fallback
            : Image.network(
                source,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return fallback;
                },
              ),
      ),
    );
  }
}
