import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final service = ref.watch(subsonicServiceProvider);
  await service.init();
  if (!service.isConnected) return const [];
  return service.getLibrarySongs();
});

final subsonicPlaylistSongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, String>((ref, playlistId) async {
  ref.watch(subsonicRevisionProvider);
  final service = ref.watch(subsonicServiceProvider);
  await service.init();
  if (!service.isConnected || playlistId.isEmpty) return const [];
  return service.getPlaylistSongs(playlistId);
});
