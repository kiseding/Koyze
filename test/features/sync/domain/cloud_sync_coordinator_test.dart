import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/cloud/domain/cloud_api_client.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/domain/playlist_service.dart';
import 'package:koyze/features/sync/domain/cloud_sync_coordinator.dart';
import 'package:koyze/features/sync/presentation/cloud_playlist_merge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first sync merges cloud into empty local without conflict', () async {
    final cloudSong = _song('cloud');
    final api = _FakeCloudApi(love: [encodeCloudSong(cloudSong)]);
    final service = await _service();
    final coordinator = CloudSyncCoordinator(api: api, service: service);

    await coordinator.sync();

    expect(service.favorites!.songs.single.identityKey, cloudSong.identityKey);
    expect(api.love, hasLength(1));
  });

  test(
    'two-sided changes merge without conflict and dedup by identity',
    () async {
      final api = _FakeCloudApi(love: [encodeCloudSong(_song('cloud'))]);
      final service = await _service();
      final coordinator = CloudSyncCoordinator(api: api, service: service);
      await coordinator.sync(choice: CloudSyncChoice.cloud);

      await service.addSongToPlaylist('favorites', _song('local'));
      await coordinator.sync();
      expect(
        api.love.map((song) => song['songmid']),
        containsAll(['cloud', 'local']),
      );

      await service.addSongToPlaylist('favorites', _song('device-a'));
      api.addRemote(_song('device-b'));

      // Both sides changed — merge should union without throwing.
      await coordinator.sync();

      final ids = service.favorites!.songs.map((song) => song.id).toSet();
      expect(ids, containsAll({'cloud', 'local', 'device-a', 'device-b'}));
      expect(api.love.map((song) => song['songmid']).toSet(), containsAll(ids));
    },
  );
}

Future<PlaylistService> _service() async {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final service = PlaylistService(
    repository: _MemoryRepository(
      PlaylistSnapshot(
        schemaVersion: 1,
        playlists: [
          Playlist(
            id: 'favorites',
            name: '收藏列表',
            songs: const [],
            createdAt: epoch,
            updatedAt: epoch,
          ),
          Playlist(
            id: 'recent',
            name: '最近播放',
            songs: const [],
            createdAt: epoch,
            updatedAt: epoch,
          ),
          Playlist(
            id: 'local',
            name: '本地音乐',
            songs: const [],
            createdAt: epoch,
            updatedAt: epoch,
          ),
        ],
      ),
    ),
  );
  await service.init();
  return service;
}

MusicItem _song(String id) => MusicItem(
  id: id,
  name: id,
  singer: 'Singer',
  source: 'tx',
  platform: 'tx',
  songmid: id,
  hash: id,
);

final class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}

final class _FakeCloudApi extends CloudApiClient {
  _FakeCloudApi({required List<Map<String, dynamic>> love})
    : love = [for (final song in love) Map<String, dynamic>.from(song)];

  final List<Map<String, dynamic>> love;
  int revision = 0;

  @override
  String? get baseUrl => 'https://cloud.test';

  @override
  String? get username => 'user';

  void addRemote(MusicItem song) {
    love.add(encodeCloudSong(song));
    revision++;
  }

  @override
  Future<Map<String, dynamic>> fetchUserList() async => {
    'loveList': [for (final song in love) Map<String, dynamic>.from(song)],
    'userList': <Map<String, dynamic>>[],
    'revision': revision,
    'complete': true,
  };

  @override
  Future<int> fetchSyncRevision() async => revision;

  @override
  Future<int> addLoveSongs(
    List<Map<String, dynamic>> songs, {
    int? baseRevision,
  }) async {
    love.addAll(songs.map(Map<String, dynamic>.from));
    return ++revision;
  }

  @override
  Future<int> removeLoveSongs(
    List<Map<String, dynamic>> songs, {
    required int baseRevision,
  }) async {
    final ids = songs
        .map((song) => '${song['songmid']}|${song['source']}')
        .toSet();
    love.removeWhere(
      (song) => ids.contains('${song['songmid']}|${song['source']}'),
    );
    return ++revision;
  }

  @override
  Future<int> deletePlaylist(String id, {int? baseRevision}) async =>
      ++revision;

  @override
  Future<int> appendPlaylistSongs({
    required String id,
    required String name,
    required int position,
    required List<Map<String, dynamic>> songs,
    int? baseRevision,
  }) async => ++revision;

  @override
  Future<int> replaceCloudSnapshot({
    required List<Map<String, dynamic>> loveList,
    required List<Map<String, dynamic>> userList,
    required int baseRevision,
    required int expectedSessionRevision,
  }) async {
    love
      ..clear()
      ..addAll(loveList.map(Map<String, dynamic>.from));
    return ++revision;
  }
}
