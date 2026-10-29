import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../stats/data/play_history_store.dart';
import '../../stats/presentation/play_history_provider.dart';
import '../data/playable_song_store.dart';
import '../domain/music_item.dart';
import '../domain/precache_service.dart';

final playbackPrewarmProvider = Provider<PlaybackPrewarm>(
  (ref) => PlaybackPrewarm(),
);

final precacheServiceProvider = Provider<PrecacheService>(
  (ref) => PrecacheService(prewarm: ref.watch(playbackPrewarmProvider)),
);

/// 常听预缓存调度器。挂载即生效，开关或数量变化会重排。
///
/// 延迟启动是必须的：冷启动时首页要拉封面、要恢复会话，预取如果再挤进来，
/// 用户看到的就是「打开就卡」——这正是这个功能本可以避免的问题。
final precacheRunnerProvider = Provider<void>((ref) {
  final enabled = ref.watch(precacheEnabledProvider);
  final limit = ref.watch(precacheCountProvider);
  if (!enabled) return;
  final timer = Timer(
    const Duration(seconds: 12),
    () => unawaited(_runPrecache(ref, limit)),
  );
  ref.onDispose(timer.cancel);
});

Future<void> _runPrecache(Ref ref, int limit) async {
  try {
    final store = ref.read(playableSongStoreProvider);
    await store.load();
    final candidates = _mostPlayed(ref.read(playHistoryStoreProvider), store);
    if (candidates.isEmpty) return;
    final quality = audioQualityToken(ref.read(audioQualityProvider));
    final warmed = await ref
        .read(precacheServiceProvider)
        .run(candidates: candidates, quality: quality, limit: limit);
    if (warmed > 0) {
      AppLog.instance.record(
        'precache.recent',
        'warmed=$warmed quality=$quality',
      );
    }
  } catch (error) {
    AppLog.instance.record(
      'precache.recent',
      'failed: $error',
      level: AppLogLevel.warning,
    );
  }
}

/// 按播放次数从高到低取候选曲目。
///
/// 历史里只有 id 与文字，真正能拿去解析播放地址的完整曲目来自
/// [PlayableSongStore]；两者用「来源 + 原始 id」对齐，缺档案的条目直接跳过。
List<MusicItem> _mostPlayed(PlayHistoryStore history, PlayableSongStore store) {
  final counts = <String, int>{};
  final exemplar = <String, PlayHistoryEntry>{};
  for (final entry in history.entries) {
    final key = PlayableSongStore.keyOf(entry.source, entry.songId);
    counts.update(key, (value) => value + 1, ifAbsent: () => 1);
    exemplar[key] = entry;
  }
  final ordered = counts.keys.toList()
    ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  final songs = <MusicItem>[];
  for (final key in ordered) {
    final entry = exemplar[key];
    if (entry == null) continue;
    final song = store.byKey(entry.source, entry.songId);
    if (song == null) continue;
    songs.add(song);
  }
  return songs;
}
