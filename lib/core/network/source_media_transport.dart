import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'source_pinned_transport.dart';
import 'source_request_policy.dart';

final class MediaTransferLimitException implements Exception {
  const MediaTransferLimitException(this.maximumBytes);

  final int maximumBytes;

  @override
  String toString() => 'Media response exceeds the configured byte limit';
}

final class MediaTransferHttpException implements Exception {
  const MediaTransferHttpException(this.statusCode);

  final int statusCode;
}

final class SourceMediaTransport {
  SourceMediaTransport({
    SourceStreamSandbox? sandbox,
    this.maximumBytes = 512 * 1024 * 1024,
  }) : _sandbox =
           sandbox ??
           SourceStreamSandbox(
             policy: SourceRequestPolicy(),
             transport: SourcePinnedTransport().call,
           );

  final SourceStreamSandbox _sandbox;
  final int maximumBytes;

  Future<int> download(
    String url,
    String destination, {
    required Map<String, String> headers,
    CancelToken? cancelToken,
    int? byteLimit,
  }) async {
    final limit = byteLimit == null || byteLimit > maximumBytes
        ? maximumBytes
        : byteLimit;
    final cancellation = SourceRequestCancellation();
    unawaited(
      cancelToken?.whenCancel.then((_) => cancellation.cancel('cancelled')),
    );
    final response = await _sandbox.open(Uri.parse(url), {
      'method': 'GET',
      'headers': headers,
      'timeout': const Duration(minutes: 5).inMilliseconds,
    }, cancellation: cancellation);
    RandomAccessFile? output;
    var completed = false;
    try {
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw MediaTransferHttpException(status ?? 0);
      }
      final declared = int.tryParse(response.header('content-length') ?? '');
      if (declared != null && declared > limit) {
        throw MediaTransferLimitException(limit);
      }
      output = await File(destination).open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.body) {
        if (cancelToken?.isCancelled == true) {
          throw cancelToken!.cancelError!;
        }
        if (chunk.length > limit - received) {
          throw MediaTransferLimitException(limit);
        }
        received += chunk.length;
        await output.writeFrom(chunk);
      }
      await output.flush();
      completed = true;
      return received;
    } finally {
      await output?.close();
      response.close();
      if (!completed) {
        final partial = File(destination);
        if (await partial.exists()) await partial.delete();
      }
    }
  }

  Future<List<int>> read(
    String url, {
    required Map<String, String> headers,
    required int maximumBytes,
    int? requiredStatusCode,
  }) async {
    final response = await _sandbox.open(Uri.parse(url), {
      'method': 'GET',
      'headers': headers,
      'timeout': const Duration(seconds: 15).inMilliseconds,
    });
    try {
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw MediaTransferHttpException(status ?? 0);
      }
      if (requiredStatusCode != null && status != requiredStatusCode) {
        throw MediaTransferHttpException(status);
      }
      final declared = int.tryParse(response.header('content-length') ?? '');
      if (declared != null && declared > maximumBytes) {
        throw MediaTransferLimitException(maximumBytes);
      }
      final bytes = <int>[];
      await for (final chunk in response.body) {
        if (chunk.length > maximumBytes - bytes.length) {
          throw MediaTransferLimitException(maximumBytes);
        }
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      response.close();
    }
  }
}
