import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';

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
  (ref) =>
      () => StorageService.instance,
);

final selfHostedKindProvider =
    NotifierProvider<SelfHostedKindNotifier, SelfHostedKind>(
      SelfHostedKindNotifier.new,
    );

class SelfHostedKindNotifier extends BuildlessNotifier<SelfHostedKind> {
  SelfHostedKindNotifier({StorageLoader? storage})
    : _storageOverride = storage,
      super(SelfHostedKind.subsonic) {
    // Direct instantiation (tests) has no provider to read from, so the
    // restore starts here. Under Riverpod `build()` starts it with the
    // provider-supplied seam instead and this is skipped.
    if (_storageOverride != null) _startRestore(_storageOverride);
  }

  final StorageLoader? _storageOverride;
  StorageLoader _storage = () => StorageService.instance;
  Future<void> _restored = Future<void>.value();
  bool _restoreStarted = false;

  @override
  SelfHostedKind build() {
    _startRestore(ref.watch(selfHostedKindStorageProvider));
    return super.build();
  }

  /// Completes once the persisted kind has been read, so tests can await it
  /// instead of guessing at a delay.
  @visibleForTesting
  Future<void> get restored => _restored;

  void _startRestore(StorageLoader storage) {
    if (_restoreStarted) return;
    _restoreStarted = true;
    _storage = storage;
    _restored = _restore();
  }

  Future<void> _restore() async {
    try {
      final raw = (await _storage()).getString(selfHostedKindStorageKey);
      final parsed = SelfHostedKind.tryParse(raw);
      if (parsed != null) publish(parsed);
    } catch (_) {
      // 坏数据按默认 Subsonic 处理，不挡住进页。
    }
  }

  Future<void> select(SelfHostedKind kind) async {
    if (value == kind) return;
    publish(kind);
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

final nasPlaylistsProvider = FutureProvider.autoDispose
    .family<List<NasPlaylistInfo>, NasKind>((ref, kind) async {
      ref.watch(nasRevisionProvider(kind));
      final service = ref.watch(nasServiceProvider(kind));
      await service.init();
      if (!service.isConnected) return const [];
      return service.getPlaylists();
    });

final nasLibrarySongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, NasKind>((ref, kind) async {
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
