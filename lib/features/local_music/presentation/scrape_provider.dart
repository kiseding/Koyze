import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_service.dart';
import '../../player/domain/music_item.dart';
import '../domain/music_scrape_store.dart';

final musicScrapeStoreProvider = FutureProvider<MusicScrapeStore>((ref) async {
  final store = MusicScrapeStore(storage: await StorageService.instance);
  await store.init();
  return store;
});

final scrapeRevisionProvider = StateProvider<int>((ref) => 0);

Future<List<MusicItem>> overlayScraped(
  Ref ref,
  List<MusicItem> songs,
) async {
  if (songs.isEmpty) return songs;
  final store = await ref.read(musicScrapeStoreProvider.future);
  return store.overlayAll(songs);
}
