import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/source_media_transport.dart';
import 'package:koyze/core/network/source_request_policy.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('source_media_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  SourceMediaTransport client(SourceTransport handler, {int maximumBytes = 8}) {
    return SourceMediaTransport(
      maximumBytes: maximumBytes,
      sandbox: SourceStreamSandbox(
        policy: SourceRequestPolicy(
          resolve: (_) async => [InternetAddress('93.184.216.34')],
        ),
        transport: handler,
      ),
    );
  }

  test('rejects declared oversized media before creating a file', () async {
    final transport = client(
      (request, cancellation) async => SourceTransportResponse(
        statusCode: 200,
        headers: const {
          'content-length': ['9'],
        },
        body: Stream.value([1, 2]),
      ),
    );
    final destination = '${tempDir.path}/media.part';

    await expectLater(
      transport.download(
        'http://media.example/song.mp3',
        destination,
        headers: const {},
      ),
      throwsA(isA<MediaTransferLimitException>()),
    );
    expect(File(destination).existsSync(), isFalse);
  });

  test('rejects aggregate streamed bytes and removes partial file', () async {
    final transport = client(
      (request, cancellation) async => SourceTransportResponse(
        statusCode: 200,
        headers: const {},
        body: Stream.fromIterable(const [
          [1, 2, 3, 4],
          [5, 6, 7, 8, 9],
        ]),
      ),
    );
    final destination = '${tempDir.path}/media.part';

    await expectLater(
      transport.download(
        'http://media.example/song.mp3',
        destination,
        headers: const {},
      ),
      throwsA(isA<MediaTransferLimitException>()),
    );
    expect(File(destination).existsSync(), isFalse);
  });

  test('revalidates redirect and strips non-safe media headers', () async {
    final requests = <ValidatedSourceRequest>[];
    final transport = client((request, cancellation) async {
      requests.add(request);
      if (requests.length == 1) {
        return SourceTransportResponse(
          statusCode: 302,
          headers: const {
            'location': ['http://cdn.example/song.mp3'],
          },
          body: const Stream.empty(),
        );
      }
      return SourceTransportResponse(
        statusCode: 200,
        headers: const {
          'content-length': ['4'],
        },
        body: Stream.value([1, 2, 3, 4]),
      );
    });

    await transport.download(
      'http://media.example/song.mp3',
      '${tempDir.path}/media.part',
      headers: const {
        'User-Agent': 'media-agent',
        'Referer': 'https://source.example/',
        'Authorization': 'Bearer private',
        'X-Api-Key': 'private',
        'X-Custom': 'private',
      },
    );

    expect(requests, hasLength(2));
    expect(requests.last.headers['User-Agent'], 'media-agent');
    expect(requests.last.headers, isNot(contains('Referer')));
    expect(requests.last.headers, isNot(contains('Authorization')));
    expect(requests.last.headers, isNot(contains('X-Api-Key')));
    expect(requests.last.headers, isNot(contains('X-Custom')));
  });
}
