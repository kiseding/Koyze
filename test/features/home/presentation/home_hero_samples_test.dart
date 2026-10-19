import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/features/home/presentation/home_hero_card.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/domain/playlist_service.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';

final _now = DateTime.fromMillisecondsSinceEpoch(1785283200000, isUtc: true);

MusicItem _song(String id) => MusicItem(
  id: id,
  name: 'Song $id',
  singer: 'Artist $id',
  source: 'test',
  duration: const Duration(seconds: 3),
);

final class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}

Future<ProviderContainer> _container(List<String> songIds) async {
  final songs = [for (final id in songIds) _song(id)];
  final service = PlaylistService(
    repository: _MemoryRepository(
      PlaylistSnapshot(
        schemaVersion: 1,
        playlists: [
          Playlist(
            id: 'favorites',
            name: 'Favorites',
            songs: songs,
            createdAt: _now,
            updatedAt: _now,
          ),
        ],
      ),
    ),
  );
  await service.init();
  return ProviderContainer(
    overrides: [playlistServiceProvider.overrideWithValue(service)],
  );
}

void main() {
  test('大卡右手那三首不重复，且下标能在源歌单里对上', () async {
    final ids = [for (var i = 0; i < 20; i++) 's$i'];
    final container = await _container(ids);
    addTearDown(container.dispose);

    final sub = container.listen(
      homeHeroSamplesProvider(HomeHeroCardId.favorites),
      (_, __) {},
    );
    addTearDown(sub.close);

    final samples = await container.read(
      homeHeroSamplesProvider(HomeHeroCardId.favorites).future,
    );

    expect(samples.length, 3);
    // 三首互不相同——同一首歌出现两次会读成列表坏了。
    expect(samples.map((sample) => sample.index).toSet().length, 3);
    // 按源歌单顺序摆回来，不是抽到什么顺序就什么顺序。
    final indices = samples.map((sample) => sample.index).toList();
    expect(indices, [...indices]..sort());
    for (final sample in samples) {
      expect(sample.song.id, ids[sample.index]);
    }
  });

  test('歌不够三首时有几首给几首，空歌单给空列表', () async {
    final two = await _container(['a', 'b']);
    addTearDown(two.dispose);
    final twoSub = two.listen(
      homeHeroSamplesProvider(HomeHeroCardId.favorites),
      (_, __) {},
    );
    addTearDown(twoSub.close);
    final picked = await two.read(
      homeHeroSamplesProvider(HomeHeroCardId.favorites).future,
    );
    expect(picked.map((sample) => sample.song.id), ['a', 'b']);

    final empty = await _container(const []);
    addTearDown(empty.dispose);
    final emptySub = empty.listen(
      homeHeroSamplesProvider(HomeHeroCardId.favorites),
      (_, __) {},
    );
    addTearDown(emptySub.close);
    final none = await empty.read(
      homeHeroSamplesProvider(HomeHeroCardId.favorites).future,
    );
    expect(none, isEmpty);
  });
}
