import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/domain/music_item.dart';
import '../domain/nas_config.dart';
import '../domain/nas_kind.dart';
import '../domain/nas_service.dart';

final nasServiceProvider = Provider.family<NasService, NasKind>((ref, kind) {
  final service = NasService(kind: kind);
  unawaitedNasInit(service);
  ref.onDispose(service.dispose);
  return service;
});

void unawaitedNasInit(NasService service) {
  service.init();
}

final nasRevisionProvider = StreamProvider.family<int, NasKind>((ref, kind) {
  return ref.watch(nasServiceProvider(kind)).revisions;
});

final nasConfigProvider = Provider.family<NasConfig, NasKind>((ref, kind) {
  ref.watch(nasRevisionProvider(kind));
  return ref.watch(nasServiceProvider(kind)).config;
});

final nasConnectedProvider = Provider.family<bool, NasKind>((ref, kind) {
  ref.watch(nasRevisionProvider(kind));
  return ref.watch(nasServiceProvider(kind)).isConnected;
});

final nasPlaylistsProvider =
    FutureProvider.autoDispose.family<List<NasPlaylistInfo>, NasKind>((
      ref,
      kind,
    ) async {
      ref.watch(nasRevisionProvider(kind));
      final service = ref.watch(nasServiceProvider(kind));
      await service.init();
      if (!service.isConnected) return const [];
      return service.getPlaylists();
    });

class NasPlaylistSongsKey {
  const NasPlaylistSongsKey(this.kind, this.playlistId);

  final NasKind kind;
  final String playlistId;

  @override
  bool operator ==(Object other) {
    return other is NasPlaylistSongsKey &&
        other.kind == kind &&
        other.playlistId == playlistId;
  }

  @override
  int get hashCode => Object.hash(kind, playlistId);
}

final nasPlaylistSongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, NasPlaylistSongsKey>((ref, key) async {
      ref.watch(nasRevisionProvider(key.kind));
      final service = ref.watch(nasServiceProvider(key.kind));
      await service.init();
      if (!service.isConnected || key.playlistId.isEmpty) return const [];
      return service.getPlaylistSongs(key.playlistId);
    });
