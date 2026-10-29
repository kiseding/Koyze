import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/domain/precache_service.dart';

MusicItem _song(String id, {String source = 'tx', Map<String, dynamic>? meta}) {
  return MusicItem(
    id: id,
    name: 'Song $id',
    singer: 'Artist',
    source: source,
    platform: source,
    meta: meta,
  );
}

void main() {
  group('PlaybackPrewarm', () {
    test('reports unwired until a resolver is attached', () async {
      final prewarm = PlaybackPrewarm();
      expect(prewarm.isWired, isFalse);
      expect(await prewarm.prewarm(_song('1'), quality: '320k'), isFalse);
    });

    test('swallows resolver errors', () async {
      final prewarm = PlaybackPrewarm()
        ..wire((song, {required quality}) async => throw StateError('boom'));
      expect(await prewarm.prewarm(_song('1'), quality: '320k'), isFalse);
    });

    test('treats an empty url as a failure', () async {
      final prewarm = PlaybackPrewarm()
        ..wire((song, {required quality}) async => '');
      expect(await prewarm.prewarm(_song('1'), quality: '320k'), isFalse);
    });
  });

  group('PrecacheService.run', () {
    test(
      'stops at the requested limit and passes the quality through',
      () async {
        final resolved = <String>[];
        final service = PrecacheService(
          prewarm: PlaybackPrewarm()
            ..wire((song, {required quality}) async {
              resolved.add('${song.id}:$quality');
              return 'https://cdn/${song.id}';
            }),
          onWifi: () async => true,
        );

        final warmed = await service.run(
          candidates: [_song('1'), _song('2'), _song('3')],
          quality: '320k',
          limit: 2,
        );

        expect(warmed, 2);
        expect(resolved, ['1:320k', '2:320k']);
        expect(service.warmCount, 2);
      },
    );

    test('skips local files and live radio', () async {
      final resolved = <String>[];
      final service = PrecacheService(
        prewarm: PlaybackPrewarm()
          ..wire((song, {required quality}) async {
            resolved.add(song.id);
            return 'https://cdn/${song.id}';
          }),
        onWifi: () async => true,
      );

      await service.run(
        candidates: [
          _song('local', source: 'local'),
          _song('radio', source: 'radio'),
          _song('meta-radio', meta: {'radio': true}),
          _song('meta-local', meta: {'local': true}),
          _song('ok'),
        ],
        quality: '320k',
        limit: 10,
      );

      expect(resolved, ['ok']);
    });

    test('does nothing on a metered connection', () async {
      final resolved = <String>[];
      final service = PrecacheService(
        prewarm: PlaybackPrewarm()
          ..wire((song, {required quality}) async {
            resolved.add(song.id);
            return 'https://cdn/${song.id}';
          }),
        onWifi: () async => false,
      );

      final warmed = await service.run(
        candidates: [_song('1')],
        quality: '320k',
        limit: 5,
      );

      expect(warmed, 0);
      expect(resolved, isEmpty);
    });

    test('never resolves the same song twice', () async {
      var calls = 0;
      final service = PrecacheService(
        prewarm: PlaybackPrewarm()
          ..wire((song, {required quality}) async {
            calls++;
            return 'https://cdn/${song.id}';
          }),
        onWifi: () async => true,
      );

      await service.run(candidates: [_song('1')], quality: '320k', limit: 5);
      await service.run(candidates: [_song('1')], quality: '320k', limit: 5);

      expect(calls, 1);
    });

    test('retries a failure on the next run', () async {
      var calls = 0;
      final service = PrecacheService(
        prewarm: PlaybackPrewarm()
          ..wire((song, {required quality}) async {
            calls++;
            return calls == 1 ? null : 'https://cdn/${song.id}';
          }),
        onWifi: () async => true,
      );

      expect(
        await service.run(candidates: [_song('1')], quality: '320k', limit: 5),
        0,
      );
      expect(
        await service.run(candidates: [_song('1')], quality: '320k', limit: 5),
        1,
      );
    });

    test('does nothing when no resolver has been wired in', () async {
      final service = PrecacheService(onWifi: () async => true);
      expect(
        await service.run(candidates: [_song('1')], quality: '320k', limit: 5),
        0,
      );
    });

    test('skips songs with an empty id', () async {
      final service = PrecacheService(
        prewarm: PlaybackPrewarm()
          ..wire((song, {required quality}) async => 'https://cdn'),
        onWifi: () async => true,
      );
      expect(
        await service.run(candidates: [_song('  ')], quality: '320k', limit: 5),
        0,
      );
    });
  });
}
