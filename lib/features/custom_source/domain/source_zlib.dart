import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

const int maximumSourceZlibInputBytes = 2 * 1024 * 1024;
const int maximumSourceZlibOutputBytes = 8 * 1024 * 1024;
const int maximumSourceZlibExpansionRatio = 100;
const int _minimumExpansionAllowance = 64 * 1024;
const int _maximumEncodedInputLength =
    ((maximumSourceZlibInputBytes + 2) ~/ 3) * 4;

final class SourceZlibLimitException implements Exception {
  const SourceZlibLimitException(this.message);

  final String message;

  @override
  String toString() => 'SourceZlibLimitException: $message';
}

Future<String> runBoundedSourceZlib(dynamic args) async {
  final data = args is String
      ? json.decode(args) as Map<String, dynamic>
      : Map<String, dynamic>.from(args as Map);
  final encoded = data['data']?.toString() ?? '';
  if (encoded.length > _maximumEncodedInputLength) {
    throw const SourceZlibLimitException('encoded input exceeds limit');
  }
  return compute(_runSourceZlib, {
    'method': data['method']?.toString() ?? '',
    'data': encoded,
  });
}

String _runSourceZlib(Map<String, String> request) {
  final input = base64Decode(request['data']!);
  if (input.length > maximumSourceZlibInputBytes) {
    throw const SourceZlibLimitException('decoded input exceeds limit');
  }

  final method = request['method'];
  final maximumOutput = method == 'inflate'
      ? _maximumInflatedBytes(input.length)
      : maximumSourceZlibOutputBytes;
  final output = _BoundedByteSink(maximumOutput);
  late final ByteConversionSink converter;
  if (method == 'inflate') {
    converter = ZLibDecoder().startChunkedConversion(output);
  } else if (method == 'deflate') {
    converter = ZLibEncoder().startChunkedConversion(output);
  } else {
    throw const FormatException('unsupported zlib method');
  }
  converter
    ..add(input)
    ..close();
  return base64Encode(output.takeBytes());
}

int _maximumInflatedBytes(int inputBytes) {
  final ratioLimit = inputBytes * maximumSourceZlibExpansionRatio;
  final allowed = ratioLimit < _minimumExpansionAllowance
      ? _minimumExpansionAllowance
      : ratioLimit;
  return allowed < maximumSourceZlibOutputBytes
      ? allowed
      : maximumSourceZlibOutputBytes;
}

final class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maximumBytes);

  final int maximumBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_builder.length + data.length > maximumBytes) {
      throw const SourceZlibLimitException('output exceeds limit');
    }
    _builder.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}
