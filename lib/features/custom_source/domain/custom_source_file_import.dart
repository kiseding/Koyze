import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../core/io/bounded_input.dart';

final class CustomSourceFileReadException implements Exception {
  const CustomSourceFileReadException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class CustomSourceFileContent {
  const CustomSourceFileContent({required this.bytes, required this.source});

  final Uint8List bytes;
  final String source;
}

Future<CustomSourceFileContent> readCustomSourceFileBytes(
  PlatformFile file, {
  required int maximumBytes,
}) async {
  if (file.size > maximumBytes) {
    throw const InputLimitException('bytes', 'file exceeds maximumBytes');
  }

  final path = file.path;
  Object? pathError;
  if (path != null && path.isNotEmpty) {
    try {
      return CustomSourceFileContent(
        bytes: await readFileBytesBounded(
          File(path),
          maximumBytes: maximumBytes,
        ),
        source: 'path',
      );
    } on InputLimitException {
      rethrow;
    } catch (error) {
      pathError = error;
    }
  }

  final bytes = file.bytes;
  if (bytes != null) {
    if (bytes.length > maximumBytes) {
      throw const InputLimitException('bytes', 'file exceeds maximumBytes');
    }
    return CustomSourceFileContent(
      bytes: Uint8List.fromList(bytes),
      source: pathError == null ? 'bytes' : 'bytes (path fallback)',
    );
  }

  final stream = file.readStream;
  if (stream != null) {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (builder.length + chunk.length > maximumBytes) {
        throw const InputLimitException('bytes', 'file exceeds maximumBytes');
      }
      builder.add(chunk);
    }
    return CustomSourceFileContent(
      bytes: builder.takeBytes(),
      source: pathError == null ? 'readStream' : 'readStream (path fallback)',
    );
  }

  if (pathError != null) throw pathError;
  if (file.size > maximumBytes) {
    throw const InputLimitException('bytes', 'file exceeds maximumBytes');
  }
  throw const CustomSourceFileReadException('文件提供器没有返回可读取的路径、字节数据或读取流。');
}

String decodeCustomSourceScript(Uint8List bytes) {
  final contentBytes =
      bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF
      ? bytes.sublist(3)
      : bytes;
  return utf8.decode(contentBytes, allowMalformed: false);
}
