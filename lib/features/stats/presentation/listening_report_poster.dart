import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../../core/platform/save_file_target.dart';
import '../../../l10n/app_strings.dart';
import '../data/play_history_store.dart';

/// 从播放历史聚合出海报所需的全部数据。
///
/// 单独提出来是为了能脱离 Flutter 直接单测：时段分桶、最常听歌手这类
/// 逻辑一旦算错，海报上就是错的，事后无法从图片反推。
ListeningReportData buildListeningReportData(
  PlayHistoryStore store,
  StatsRange range, {
  DateTime? now,
}) {
  final summary = store.summary(range, now: now);
  final hours = store.hourlySeconds(range, now: now);
  final artists = store.topArtists(range, limit: 1, now: now);
  final songs = store.topSongs(range, limit: 5, now: now);
  return ListeningReportData(
    range: range,
    totalPlays: summary.totalPlays,
    totalSec: summary.totalSec,
    activeDays: summary.activeDays,
    uniqueSongs: summary.uniqueSongs,
    topSongs: songs,
    topArtist: artists.isEmpty ? null : artists.first,
    hourlySeconds: hours,
    favoriteHour: store.favoriteHour(range, now: now),
  );
}

class ListeningReportData {
  const ListeningReportData({
    required this.range,
    required this.totalPlays,
    required this.totalSec,
    required this.activeDays,
    required this.uniqueSongs,
    required this.topSongs,
    required this.topArtist,
    required this.hourlySeconds,
    required this.favoriteHour,
  });

  final StatsRange range;
  final int totalPlays;
  final double totalSec;
  final int activeDays;
  final int uniqueSongs;
  final List<RankedItem> topSongs;
  final RankedItem? topArtist;
  final List<double> hourlySeconds;
  final int? favoriteHour;
}

/// 打开听歌报告海报预览。
///
/// 和歌词卡片一样走离屏 [RepaintBoundary]：截图上的字体、圆角与屏幕上
/// 所见一致；不引入分享类原生依赖，保存由 [FilePicker] 落盘，用户自行分享。
Future<void> showListeningReportSheet(
  BuildContext context,
  ListeningReportData data,
) {
  return showKoyzeDialog<void>(
    context: context,
    builder: (ctx) => _ListeningReportDialog(data: data),
  );
}

class _ListeningReportDialog extends StatefulWidget {
  const _ListeningReportDialog({required this.data});

  final ListeningReportData data;

  @override
  State<_ListeningReportDialog> createState() => _ListeningReportDialogState();
}

class _ListeningReportDialogState extends State<_ListeningReportDialog> {
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
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = Uint8List.fromList(byteData.buffer.asUint8List());
      final path = await FilePicker.saveFile(
        dialogTitle: s.lyricShareSave,
        fileName:
            'koyze_listening_${DateTime.now().millisecondsSinceEpoch}.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: saveFileNeedsBytes ? bytes : null,
      );
      if (path == null) return;
      if (callerWritesSavedFile) await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      showAppNotification(
        s.statsPosterSaved,
        type: AppNotificationType.success,
      );
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
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: _boundaryKey,
              child: ListeningReportPoster(
                data: widget.data,
                accent: AppColors.accentOf(context),
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

/// 听歌报告海报本体：固定 360 × 640 逻辑像素，导出为 1080 × 1920。
///
/// 公开是为了能在测试里直接渲染并导出 PNG——分享图一旦有渲染问题
/// （继承外层下划线、时段条越界、长歌名撑破卡片），用户保存下来的就是脏图。
class ListeningReportPoster extends StatelessWidget {
  const ListeningReportPoster({
    super.key,
    required this.data,
    required this.accent,
  });

  final ListeningReportData data;
  final Color accent;

  static const double width = 360;
  static const double height = 640;

  String _periodLabel(S s) => switch (data.range) {
    StatsRange.week => s.statsPosterPeriodWeek,
    StatsRange.month => s.statsPosterPeriodMonth,
    StatsRange.year => s.statsPosterPeriodYear,
    StatsRange.all => s.statsPosterPeriodAll,
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    const white = Color(0xFFFFFFFF);
    final dim = white.withValues(alpha: 0.72);
    final totalMinutes = (data.totalSec / 60).round();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    final peak = data.hourlySeconds.fold<double>(0, (a, b) => a > b ? a : b);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(accent, const Color(0xFF101018), 0.25)!,
              Color.lerp(accent, const Color(0xFF0B0B10), 0.72)!,
              const Color(0xFF0B0B10),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
          child: DefaultTextStyle(
            style: const TextStyle(color: white, fontFamily: 'sans-serif'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.statsPosterTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dim,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _periodLabel(s),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(color: white),
                    children: [
                      if (hours > 0) ...[
                        TextSpan(
                          text: '$hours',
                          style: const TextStyle(
                            fontSize: 54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: ' h ',
                          style: TextStyle(fontSize: 16, color: dim),
                        ),
                      ],
                      TextSpan(
                        text: '$minutes',
                        style: const TextStyle(
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' m',
                        style: TextStyle(fontSize: 16, color: dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    s.statsPosterFacts(data.activeDays, data.uniqueSongs),
                    if (data.favoriteHour != null)
                      s.statsPosterFavoriteHour(data.favoriteHour!),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: dim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Text(
                  s.statsPosterHourChart,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 8),
                _HourBars(hours: data.hourlySeconds, peak: peak, accent: white),
                const SizedBox(height: 18),
                Text(
                  s.statsPosterTopSongs,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: dim,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < data.topSongs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: i < 3 ? white : dim,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data.topSongs[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                data.topSongs[i].subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: dim),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.statPlayCount(data.topSongs[i].playCount),
                          style: TextStyle(fontSize: 12, color: dim),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (data.topArtist != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.statsPosterTopArtist,
                          style: TextStyle(fontSize: 11, color: dim),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.topArtist!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 24 小时收听分布条。每根高度按峰值归一，空时段保留一条细底。
class _HourBars extends StatelessWidget {
  const _HourBars({
    required this.hours,
    required this.peak,
    required this.accent,
  });

  final List<double> hours;
  final double peak;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final top = peak > 0 ? peak : 1;
    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 24; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  height: hours[i] <= 0 ? 2 : 6 + 28 * (hours[i] / top),
                  decoration: BoxDecoration(
                    color: hours[i] <= 0
                        ? accent.withValues(alpha: 0.18)
                        : accent.withValues(
                            alpha: 0.45 + 0.55 * (hours[i] / top),
                          ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
