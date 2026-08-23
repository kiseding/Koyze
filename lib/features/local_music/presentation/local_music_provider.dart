import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/domain/local_music_scraper.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';
import 'package:koyze/features/search/presentation/search_provider.dart';

final localMusicLibraryProvider = FutureProvider<LocalMusicLibrary>((
  ref,
) async {
  final storage = await StorageService.instance;
  final library = LocalMusicLibrary(storage: storage);
  return library;
});

final localMusicScraperProvider = Provider<LocalMusicScraper>((ref) {
  return LocalMusicScraper(ref.watch(musicSourceServiceProvider));
});

/// 本地音乐库是否已初始化（供启动流程调用）。
final localMusicInitProvider = Provider<Future<void>>((ref) async {
  final library = await ref.watch(localMusicLibraryProvider.future);
  await library.init();
});

/// 当前本地歌曲列表（由索引派生，重扫后自动刷新）。
final localSongsProvider = FutureProvider<List<LocalTrack>>((ref) async {
  final library = await ref.watch(localMusicLibraryProvider.future);
  ref.watch(localMusicRevisionProvider);
  await library.init();
  return library.files.values.map((entry) {
    return LocalTrack(
      path: entry['path']?.toString() ?? '',
      fileName: entry['fileName']?.toString() ?? '',
      extension: entry['extension']?.toString() ?? '',
      size: entry['size'] ?? 0,
      modifiedAt:
          DateTime.tryParse(entry['modifiedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      title: entry['title']?.toString() ?? '',
      artist: entry['artist']?.toString() ?? '',
      album: entry['album']?.toString() ?? '',
      duration: Duration(seconds: entry['duration'] ?? 0),
      bitrate: entry['bitrate'] is int ? entry['bitrate'] as int : null,
      hasEmbeddedTags: entry['hasEmbeddedTags'] == true,
      hasEmbeddedArtwork: entry['hasEmbeddedArtwork'] == true,
      contentUri: entry['contentUri']?.toString(),
      androidSource: entry['androidSource']?.toString(),
      safRoot: entry['safRoot']?.toString(),
      mimeType: entry['mimeType']?.toString(),
    );
  }).toList();
});

/// 本地库变更版本（重扫 / 删除目录后自增，驱动 UI 刷新）。
final localMusicRevisionProvider = StateProvider<int>((ref) => 0);
