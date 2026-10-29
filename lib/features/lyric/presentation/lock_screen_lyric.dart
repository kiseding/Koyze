import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_handler.dart';
import '../../settings/presentation/settings_provider.dart';
import 'lyric_provider.dart';

/// 把当前歌词行同步到锁屏 / 通知栏。
///
/// 实现方式是改写 `MediaItem.displaySubtitle`——Android 的 MediaStyle 通知与
/// iOS 的 Now Playing 都读这个字段，改它不需要任何原生代码。
///
/// 代价是每次更新都会让 `mediaItem` 流发一次事件，进而重建所有依赖
/// 「当前歌曲」的 provider。所以这里做了三件事：
/// * 默认关闭，用户主动打开才启用；
/// * 只在歌词行变化时写，且两次写入至少间隔 [minInterval]；
/// * 恢复成「歌手 · 专辑」而不是留下最后一句歌词。
///
/// 已知限制：它只是「当前行」，不是滚动的逐字歌词；真要逐字得改 Android
/// 通知布局，那是原生工作量。
const Duration lockScreenLyricMinInterval = Duration(seconds: 8);

final lockScreenLyricProvider = Provider<void>((ref) {
  DateTime lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  int lastIndex = -2;

  ref.listen<int>(currentLineIndexProvider, (_, index) {
    if (!ref.read(lockScreenLyricEnabledProvider)) return;
    if (index == lastIndex) return;
    lastIndex = index;
    final now = DateTime.now();
    if (now.difference(lastWrite) < lockScreenLyricMinInterval) return;

    final handler = audioHandler;
    if (handler is! LxAudioHandler) return;
    final item = handler.mediaItem.value;
    if (item == null) return;

    final lyrics = ref.read(currentLyricProvider);
    final line = index >= 0 && index < lyrics.lines.length
        ? lyrics.lines[index].text.trim()
        : '';
    final base = _baseSubtitle(item);
    final next = line.isEmpty ? base : line;
    if (item.displaySubtitle == next) return;
    lastWrite = now;
    handler.mediaItem.add(item.copyWith(displaySubtitle: next));
  });
});

String _baseSubtitle(MediaItem item) {
  final artist = (item.extras?['singer'] ?? item.artist)?.toString().trim();
  final album = (item.extras?['album'] ?? item.album)?.toString().trim();
  if (artist == null || artist.isEmpty) return album ?? '';
  if (album == null || album.isEmpty) return artist;
  return '$artist · $album';
}
