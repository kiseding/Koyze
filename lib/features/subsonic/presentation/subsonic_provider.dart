import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local_music/presentation/scrape_provider.dart';
import '../../player/domain/music_item.dart';
import '../domain/subsonic_config.dart';
import '../domain/subsonic_service.dart';

final subsonicServiceProvider = Provider<SubsonicService>((ref) {
  final service = SubsonicService();
  unawaitedInit(service);
  ref.onDispose(service.dispose);
  return service;
});

void unawaitedInit(SubsonicService service) {
  service.init();
}

final subsonicRevisionProvider = StreamProvider<int>((ref) {
  return ref.watch(subsonicServiceProvider).revisions;
});

final subsonicConfigProvider = Provider<SubsonicConfig>((ref) {
  ref.watch(subsonicRevisionProvider);
  return ref.watch(subsonicServiceProvider).config;
});

final subsonicConnectedProvider = Provider<bool>((ref) {
  ref.watch(subsonicRevisionProvider);
  return ref.watch(subsonicServiceProvider).isConnected;
});

final subsonicStreamQualityProvider = Provider<String>((ref) {
  ref.watch(subsonicRevisionProvider);
  return ref.watch(subsonicServiceProvider).streamQuality;
});

Future<void> setSubsonicStreamQuality(WidgetRef ref, String quality) async {
  final service = ref.read(subsonicServiceProvider);
  await service.init();
  await service.setStreamQuality(quality);
}

final subsonicServersProvider = Provider<List<SubsonicConfig>>((ref) {
  ref.watch(subsonicRevisionProvider);
  return ref.watch(subsonicServiceProvider).servers;
});

/// 切到另一台 Navidrome / Subsonic。密码按 origin 分开存在钥匙串里。
Future<bool> switchSubsonicServer(WidgetRef ref, String baseUrl) async {
  final service = ref.read(subsonicServiceProvider);
  await service.init();
  final ok = await service.switchTo(baseUrl);
  if (ok) ref.invalidate(subsonicLibrarySongsProvider);
  return ok;
}

Future<void> removeSubsonicServer(WidgetRef ref, String baseUrl) async {
  final service = ref.read(subsonicServiceProvider);
  await service.init();
  await service.removeServer(baseUrl);
  ref.invalidate(subsonicLibrarySongsProvider);
}

final subsonicPlaylistsProvider =
    FutureProvider.autoDispose<List<SubsonicPlaylistInfo>>((ref) async {
  ref.watch(subsonicRevisionProvider);
  final service = ref.watch(subsonicServiceProvider);
  await service.init();
  if (!service.isConnected) return const [];
  return service.getPlaylists();
});

final subsonicLibrarySongsProvider =
    FutureProvider.autoDispose<List<MusicItem>>((ref) async {
  ref.watch(subsonicRevisionProvider);
  ref.watch(scrapeRevisionProvider);
  final service = ref.watch(subsonicServiceProvider);
  await service.init();
  if (!service.isConnected) return const [];
  return overlayScraped(ref, await service.getLibrarySongs());
});

final subsonicPlaylistSongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, String>((ref, playlistId) async {
  ref.watch(subsonicRevisionProvider);
  ref.watch(scrapeRevisionProvider);
  final service = ref.watch(subsonicServiceProvider);
  await service.init();
  if (!service.isConnected || playlistId.isEmpty) return const [];
  return overlayScraped(ref, await service.getPlaylistSongs(playlistId));
});
