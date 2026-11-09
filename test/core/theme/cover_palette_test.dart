import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/cover_palette.dart';
import 'package:koyze/core/theme/cover_palette_provider.dart';
import 'package:koyze/core/widgets/artwork_disk_cache.dart';
import 'package:koyze/core/widgets/artwork_image.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

/// 纯色方块 PNG，足够让取色器挑出一个确定的主色。
Future<Uint8List> _squarePng(Color color) async {
  const size = 16;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

final class _FakeBytesLoader extends ArtworkBytesLoader {
  _FakeBytesLoader(this.bytes);

  final Future<Uint8List?> Function(Uri uri) bytes;
  final List<Uri> calls = [];

  @override
  Future<Uint8List> load(
    Uri uri,
    Map<String, String> headers,
    void Function(int, int?) onProgress,
  ) async {
    calls.add(uri);
    final result = await bytes(uri);
    if (result == null) throw StateError('no bytes for $uri');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoverPaletteService', () {
    test('同一张封面只算一次', () async {
      var calls = 0;
      final service = CoverPaletteService(
        bytesLoader: (url) async {
          calls++;
          return _squarePng(const Color(0xFFCC2222));
        },
      );

      final first = await service.paletteFor('https://cdn.example/a.jpg');
      final second = await service.paletteFor('https://cdn.example/a.jpg');

      expect(first, isNotNull);
      expect(second, same(first));
      expect(calls, 1);
    });

    test('取色失败不会把封面地址永久判死', () async {
      var calls = 0;
      final service = CoverPaletteService(
        bytesLoader: (url) async {
          calls++;
          // 第一次模拟"封面还没下载完"，之后才拿得到字节。
          if (calls == 1) return null;
          return _squarePng(const Color(0xFF22CC22));
        },
      );

      expect(await service.paletteFor('https://cdn.example/a.jpg'), isNull);
      expect(calls, 1);

      // 同一次播放里的补试要能穿过冷却期。
      final retried = await service.paletteFor(
        'https://cdn.example/a.jpg',
        ignoreFailureCooldown: true,
      );
      expect(retried, isNotNull);
      expect(calls, 2);
    });

    test('冷却期内不重复下载坏封面', () async {
      var calls = 0;
      final service = CoverPaletteService(
        bytesLoader: (url) async {
          calls++;
          return null;
        },
      );

      expect(await service.paletteFor('https://cdn.example/bad.jpg'), isNull);
      expect(await service.paletteFor('https://cdn.example/bad.jpg'), isNull);
      expect(calls, 1);
    });

    test('冷却期过后会重新尝试', () async {
      var now = DateTime(2026);
      var calls = 0;
      final service = CoverPaletteService(
        clock: () => now,
        bytesLoader: (url) async {
          calls++;
          return null;
        },
      );

      await service.paletteFor('https://cdn.example/bad.jpg');
      now = now.add(CoverPaletteService.failureCooldown * 2);
      await service.paletteFor('https://cdn.example/bad.jpg');
      expect(calls, 2);
    });

    test('磁盘缓存没有这张封面时会自己去下，而不是直接返回 null', () async {
      final root = await Directory.systemTemp.createTemp('palette_cache_');
      addTearDown(() => root.delete(recursive: true));
      final loader = _FakeBytesLoader(
        (_) async => _squarePng(const Color(0xFF2222CC)),
      );
      final previous = ArtworkDiskCache.instance;
      ArtworkDiskCache.instance = ArtworkDiskCache(
        loader: loader,
        rootOverride: root.path,
      );
      addTearDown(() => ArtworkDiskCache.instance = previous);

      final service = CoverPaletteService();
      final palette = await service.paletteFor('https://cdn.example/fresh.jpg');

      expect(palette, isNotNull);
      expect(loader.calls, hasLength(1));
      // 顺手落盘：播放页随后解封面能直接命中，不用再下一遍。
      expect(
        await ArtworkDiskCache.instance.bytesForUrl(
          'https://cdn.example/fresh.jpg',
        ),
        isNotNull,
      );
    });
  });

  group('coverPaletteProvider', () {
    test('换歌就换一套颜色', () async {
      final items = StreamController<MediaItem?>();
      addTearDown(items.close);
      final service = CoverPaletteService(
        bytesLoader: (url) async => _squarePng(
          url.contains('a.jpg') ? const Color(0xFFCC2222) : const Color(0xFF2222CC),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          currentMediaItemProvider.overrideWith((ref) => items.stream),
          coverPaletteServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      container.listen(coverPaletteProvider, (_, _) {});

      MediaItem song(String id, String art) => MediaItem(
        id: id,
        title: id,
        extras: MusicItem(
          id: id,
          name: id,
          singer: '',
          source: 'test',
          artwork: art,
        ).toJson(),
      );

      items.add(song('1', 'https://cdn.example/a.jpg'));
      await pumpEventQueue();
      final first = await container.read(coverPaletteProvider.future);
      expect(first, isNotNull, reason: '第一首要取到自己的颜色');

      items.add(song('2', 'https://cdn.example/b.jpg'));
      await pumpEventQueue();
      final second = await container.read(coverPaletteProvider.future);
      expect(second, isNotNull, reason: '换歌不能把颜色丢回手选色');
      expect(second!.accent, isNot(first!.accent));
    });

    test('封面稍后才下载完也会补上颜色', () async {
      final items = StreamController<MediaItem?>();
      addTearDown(items.close);
      var calls = 0;
      final service = CoverPaletteService(
        bytesLoader: (url) async {
          calls++;
          // 换歌那一瞬封面还没落盘，第一次取色必然失败。
          if (calls == 1) return null;
          return _squarePng(const Color(0xFFCC2222));
        },
      );
      final container = ProviderContainer(
        overrides: [
          currentMediaItemProvider.overrideWith((ref) => items.stream),
          coverPaletteServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      container.listen(coverPaletteProvider, (_, _) {});

      items.add(
        MediaItem(
          id: 'late',
          title: 'late',
          extras: MusicItem(
            id: 'late',
            name: 'late',
            singer: '',
            source: 'test',
            artwork: 'https://cdn.example/late.jpg',
          ).toJson(),
        ),
      );
      await pumpEventQueue();
      final palette = await container.read(coverPaletteProvider.future);

      expect(palette, isNotNull, reason: '重试后应该拿到颜色，而不是整首弃疗');
      expect(calls, greaterThan(1));
    });
  });
}
