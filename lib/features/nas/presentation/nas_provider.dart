import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/storage_service.dart';
import '../../local_music/presentation/scrape_provider.dart';
import '../../player/domain/music_item.dart';
import '../domain/nas_config.dart';
import '../domain/nas_kind.dart';
import '../domain/nas_service.dart';
import '../domain/self_hosted_kind.dart';

/// 设置页选中的自建乐库类型。库页只读这个值，不再自己切类型。
const selfHostedKindStorageKey = 'self_hosted_kind_v1';

final selfHostedKindStorageProvider = Provider<StorageLoader>(
  (ref) => () => StorageService.instance,
);

final selfHostedKindProvider =
    StateNotifierProvider<SelfHostedKindNotifier, SelfHostedKind>((ref) {
      return SelfHostedKindNotifier(
        storage: ref.watch(selfHostedKindStorageProvider),
      );
    });

class SelfHostedKindNotifier extends StateNotifier<SelfHostedKind> {
  SelfHostedKindNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(SelfHostedKind.subsonic) {
    _restored = _restore();
  }

  final StorageLoader _storage;
  late final Future<void> _restored;

  @visibleForTesting
  Future<void> get restored => _restored;

  Future<void> _restore() async {
    try {
      final raw = (await _storage()).getString(selfHostedKindStorageKey);
      final parsed = SelfHostedKind.tryParse(raw);
      if (parsed != null && mounted) state = parsed;
    } catch (_) {
      // 坏数据按默认 Subsonic 处理，不挡住进页。
    }
  }

  Future<void> select(SelfHostedKind kind) async {
    if (state == kind) return;
    state = kind;
    try {
      await (await _storage()).setString(selfHostedKindStorageKey, kind.name);
    } catch (_) {
      // 写失败不影响当前这次切换。
    }
  }
}

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

final nasLibrarySongsProvider =
    FutureProvider.autoDispose.family<List<MusicItem>, NasKind>((
      ref,
      kind,
    ) async {
      ref.watch(nasRevisionProvider(kind));
      ref.watch(scrapeRevisionProvider);
      final service = ref.watch(nasServiceProvider(kind));
      await service.init();
      if (!service.isConnected) return const [];
      return overlayScraped(ref, await service.getLibrarySongs());
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
      ref.watch(scrapeRevisionProvider);
      final service = ref.watch(nasServiceProvider(key.kind));
      await service.init();
      if (!service.isConnected || key.playlistId.isEmpty) return const [];
      return overlayScraped(
        ref,
        await service.getPlaylistSongs(key.playlistId),
      );
    });
