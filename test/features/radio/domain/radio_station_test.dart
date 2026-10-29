import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/radio/domain/radio_station.dart';

void main() {
  group('RadioStation.fromJson', () {
    test('prefers the resolved url', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc',
        'name': 'Radio One',
        'url': 'http://example.com/raw',
        'url_resolved': 'https://example.com/live.mp3',
        'favicon': 'https://example.com/icon.png',
        'tags': 'jazz,soul',
        'country': 'France',
        'codec': 'MP3',
        'bitrate': 128,
        'votes': 12,
      });
      expect(station, isNotNull);
      expect(station!.id, 'abc');
      expect(station.streamUrl, 'https://example.com/live.mp3');
      expect(station.favicon, 'https://example.com/icon.png');
      expect(station.bitrate, 128);
      expect(station.votes, 12);
    });

    test('falls back to the raw url', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc',
        'name': 'Radio',
        'url': 'http://example.com/raw',
        'url_resolved': '',
      });
      expect(station!.streamUrl, 'http://example.com/raw');
    });

    test('drops stations that cannot be played', () {
      expect(
        RadioStation.fromJson({'stationuuid': 'abc', 'name': 'No URL'}),
        isNull,
      );
      expect(
        RadioStation.fromJson({'stationuuid': '', 'name': 'x', 'url': 'y'}),
        isNull,
      );
      expect(
        RadioStation.fromJson({'stationuuid': 'abc', 'name': '', 'url': 'y'}),
        isNull,
      );
    });

    test('tolerates string numbers and blank favicons', () {
      final station = RadioStation.fromJson({
        'stationuuid': 'abc',
        'name': 'Radio',
        'url': 'https://example.com/a',
        'bitrate': '96',
        'votes': '7',
        'favicon': '   ',
      })!;
      expect(station.bitrate, 96);
      expect(station.votes, 7);
      expect(station.favicon, isNull);
    });
  });

  group('subtitleParts', () {
    test('joins country, bitrate and codec', () {
      const station = RadioStation(
        id: 'a',
        name: 'n',
        streamUrl: 'u',
        country: 'France',
        codec: 'aac',
        bitrate: 192,
      );
      expect(station.subtitleParts, 'France · 192k · AAC');
    });

    test('omits missing pieces without leaving separators', () {
      const station = RadioStation(id: 'a', name: 'n', streamUrl: 'u');
      expect(station.subtitleParts, '');
      const partial = RadioStation(
        id: 'a',
        name: 'n',
        streamUrl: 'u',
        country: 'CN',
      );
      expect(partial.subtitleParts, 'CN');
    });
  });

  group('toMusicItem', () {
    const station = RadioStation(
      id: 'uuid-1',
      name: 'Late Night Jazz',
      streamUrl: 'https://example.com/live.mp3',
      favicon: 'https://example.com/icon.png',
      tags: 'jazz',
      country: 'US',
      codec: 'MP3',
      bitrate: 128,
    );

    test('marks the item as radio and keeps the direct link', () {
      final item = station.toMusicItem();
      expect(item.id, 'uuid-1');
      expect(item.name, 'Late Night Jazz');
      expect(item.source, RadioStation.radioSourceId);
      expect(item.platform, RadioStation.radioSourceId);
      expect(item.url, 'https://example.com/live.mp3');
      expect(item.meta?['radio'], isTrue);
      // 播放器会剥掉 extras['url']，所以直链必须也留在 meta 里。
      expect(item.meta?['streamUrl'], 'https://example.com/live.mp3');
    });

    test('has no duration because a stream is unbounded', () {
      expect(station.toMusicItem().duration, Duration.zero);
    });

    test(
      'uses tags as the artist line so the player shows something useful',
      () {
        expect(station.toMusicItem().singer, 'jazz');
        const untagged = RadioStation(
          id: 'a',
          name: 'n',
          streamUrl: 'u',
          country: 'DE',
        );
        expect(untagged.toMusicItem().singer, 'DE');
      },
    );

    test('survives a JSON round trip through the queue', () {
      final again = station.toMusicItem().toJson();
      final meta = again['meta'] as Map<String, dynamic>;
      expect(meta['streamUrl'], 'https://example.com/live.mp3');
      expect(again['source'], RadioStation.radioSourceId);
    });
  });
}
