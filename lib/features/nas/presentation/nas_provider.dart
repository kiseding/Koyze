import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/buildless_notifier.dart';

import '../../../core/storage/storage_service.dart';
import '../../local_music/presentation/scrape_provider.dart';
import '../../player/domain/music_item.dart';
import '../domain/nas_config.dart';
import '../domain/nas_kind.dart';
import '../domain/nas_library_cache.dart';
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

final nasStreamQualityProvider = Provider.family<String, NasKind>((ref, kind) {
  ref.watch(nasRevisionProvider(kind));
  return ref.watch(nasServiceProvider(kind)).streamQuality;
});

Future<void> setNasStreamQuality(
  WidgetRef ref,
  NasKind kind,
  String quality,
) async {
  final service = ref.read(nasServiceProvider(kind));
  await service.init();
  await service.setStreamQuality(quality);
}

final nasServersProvider = Provider.family<List<NasConfig>, NasKind>((
  ref,
  kind,
) {
  ref.watch(nasRevisionProvider(kind));
  return ref.watch(nasServiceProvider(kind)).servers;
});

/// 缓存文件按「协议 + 服务器地址」分开，否则同一个协议换服务器会读到
/// 上一台的曲库。
final nasLibraryCacheProvider = Provider.family<NasLibraryCache, NasKind>((
  ref,
  kind,
) {
  final config = ref.watch(nasConfigProvider(kind));
  return NasLibraryCache(serverId: nasCacheIdOf(kind, config));
});

String nasCacheIdOf(NasKind kind, NasConfig config) {
  if (!config.isConfigured) return kind.id;
  return '${kind.id}@${config.baseUrl}';
}

/// 缓存超过这个时长就在后台重扫，首屏仍然先给缓存。
const kNasLibraryCacheTtl = Duration(minutes: 10);

/// 正在后台刷新中的服务器，避免多次进入页面触发并发整库扫描。
final Set<String> _nasLibraryRefreshing = {};

/// 先给缓存，再在后台补扫。
///
/// WebDAV 整库扫描是「每个目录一次 PROPFIND」，几千首的库要好幾秒；
/// 以前每次进页面都重扫一遍，退出去再进来还要再等一次。
final nasLibrarySongsProvider = FutureProvider.autoDispose
    .family<List<MusicItem>, NasKind>((ref, kind) async {
      ref.watch(nasRevisionProvider(kind));
      ref.watch(scrapeRevisionProvider);
      // 页面退出后保留结果，返回时不再重扫。
      ref.keepAlive();
      final service = ref.watch(nasServiceProvider(kind));
      await service.init();
      if (!service.isConnected) return const [];
      final cache = ref.watch(nasLibraryCacheProvider(kind));
      final cached = await cache.read();
      if (cached != null) {
        if (cached.age > kNasLibraryCacheTtl) {
          unawaited(_refreshNasLibraryInBackground(ref, kind, service, cache));
        }
        return overlayScraped(ref, cached.songs);
      }
      final songs = await service.getLibrarySongs();
      unawaited(cache.write(songs));
      return overlayScraped(ref, songs);
    });

Future<void> _refreshNasLibraryInBackground(
  Ref ref,
  NasKind kind,
  NasService service,
  NasLibraryCache cache,
) async {
  final cacheId = cache.serverId;
  if (!_nasLibraryRefreshing.add(cacheId)) return;
  try {
    final songs = await service.getLibrarySongs();
    if (songs.isEmpty) return;
    await cache.write(songs);
    ref.invalidateSelf();
  } catch (_) {
    // 服务器暂时不可达：继续用缓存。
  } finally {
    _nasLibraryRefreshing.remove(cacheId);
  }
}

/// 用户主动点刷新：绕过缓存整库重扫，结果落盘后再让页面重建。
Future<void> refreshNasLibrary(WidgetRef ref, NasKind kind) async {
  final service = ref.read(nasServiceProvider(kind));
  final cache = ref.read(nasLibraryCacheProvider(kind));
  await service.init();
  final songs = await service.getLibrarySongs();
  if (songs.isNotEmpty) await cache.write(songs);
  ref.invalidate(nasLibrarySongsProvider(kind));
}

/// 切到同一协议下另一台服务器。
Future<bool> switchNasServer(
  WidgetRef ref,
  NasKind kind,
  String baseUrl,
) async {
  final service = ref.read(nasServiceProvider(kind));
  await service.init();
  final ok = await service.switchTo(baseUrl);
  if (ok) ref.invalidate(nasLibrarySongsProvider(kind));
  return ok;
}

Future<void> removeNasServer(
  WidgetRef ref,
  NasKind kind,
  String baseUrl,
) async {
  final service = ref.read(nasServiceProvider(kind));
  await service.init();
  await service.removeServer(baseUrl);
  ref.invalidate(nasLibrarySongsProvider(kind));
}

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
