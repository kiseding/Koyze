import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/artwork_disk_cache.dart';
import 'package:koyze/core/widgets/artwork_image.dart';

final class _CountingArtworkLoader extends ArtworkBytesLoader {
  _CountingArtworkLoader(this.gate);

  final Completer<void> gate;
  final started = Completer<void>();
  int calls = 0;

  @override
  Future<Uint8List> load(
    Uri uri,
    Map<String, String> headers,
    void Function(int, int?) onProgress,
  ) async {
    calls++;
    if (!started.isCompleted) started.complete();
    await gate.future;
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'same artwork download is deduplicated and leaves no partial file',
    () async {
      final root = await Directory.systemTemp.createTemp('artwork_cache_');
      addTearDown(() => root.delete(recursive: true));
      final gate = Completer<void>();
      final loader = _CountingArtworkLoader(gate);
      final cache = ArtworkDiskCache(loader: loader, rootOverride: root.path);
      await cache.ensureReady();

      final first = cache.ensureLocalFile('https://images.example/cover.jpg');
      final second = cache.ensureLocalFile('https://images.example/cover.jpg');
      await loader.started.future;
      expect(loader.calls, 1);
      gate.complete();

      final files = await Future.wait([first, second]);
      expect(files.first?.path, files.last?.path);
      expect(await files.first!.readAsBytes(), [1, 2, 3, 4]);
      expect(
        root.listSync().where((entity) => entity.path.endsWith('.part')),
        isEmpty,
      );
    },
  );
}
