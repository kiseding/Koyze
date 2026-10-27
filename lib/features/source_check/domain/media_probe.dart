// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/audio/playback_cache_service.dart';
import '../../../core/network/source_media_transport.dart';

/// 一次地址探测的结论。
@immutable
class MediaProbeResult {
  const MediaProbeResult({
    required this.ok,
    required this.message,
    this.sizeBytes,
    this.extension,
    this.latencyMs = 0,
    this.timedOut = false,
  });

  const MediaProbeResult.failed(
    this.message, {
    this.latencyMs = 0,
    this.timedOut = false,
    this.sizeBytes,
  }) : ok = false,
       extension = null;

  final bool ok;
  final String message;
  final int? sizeBytes;
  final String? extension;
  final int latencyMs;
  final bool timedOut;
}

/// 只看「这个地址此刻能不能读到音频」，不落盘、不解析播放器。
abstract interface class MediaProbe {
  Future<MediaProbeResult> probe(
    String url, {
    required String platform,
    Duration timeout = const Duration(seconds: 6),
  });
}

/// 用 Range 请求读回文件头：既确认对方真的吐音频，又尽量拿到总长度。
///
/// 走 [SourceMediaTransport]，因此脚本返回私有网段地址时会被和播放链路同一套
/// 策略拦掉——检测不该成为 SSRF 的旁路。
class HttpMediaProbe implements MediaProbe {
  HttpMediaProbe({SourceMediaTransport? transport})
    : _transport = transport ?? SourceMediaTransport();

  /// 读 64 KiB：足够文件头嗅探，又不至于把整首歌拉下来。
  static const int sampleBytes = 64 * 1024;

  final SourceMediaTransport _transport;

  @override
  Future<MediaProbeResult> probe(
    String url, {
    required String platform,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final stopwatch = Stopwatch()..start();
    final responseHeaders = <String, String>{};
    try {
      final bytes = await _transport
          .read(
            url,
            headers: {
              ...mediaRequestHeaders(url, platform),
              'Range': 'bytes=0-${sampleBytes - 1}',
              'Accept-Encoding': 'identity',
            },
            maximumBytes: sampleBytes,
            responseHeaders: responseHeaders,
          )
          .timeout(timeout);
      stopwatch.stop();
      return classify(
        url: url,
        bytes: bytes,
        responseHeaders: responseHeaders,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return MediaProbeResult.failed(
        '探测超时',
        latencyMs: stopwatch.elapsedMilliseconds,
        timedOut: true,
      );
    } on MediaTransferLimitException {
      // 服务端无视 Range，一次性吐整个文件。能读到这么多字节说明地址确实是
      // 音频流，只是拿不到总长度——按可用处理，体积留空。
      stopwatch.stop();
      return MediaProbeResult(
        ok: true,
        message: '',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on MediaTransferHttpException catch (error) {
      stopwatch.stop();
      return MediaProbeResult.failed(
        'HTTP ${error.statusCode}',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      return MediaProbeResult.failed(
        error is TimeoutException ? '探测超时' : error.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
        timedOut: error is TimeoutException,
      );
    }
  }

  /// 判定「这段字节 + 这些响应头」算不算真的音频。抽成纯函数便于单测。
  @visibleForTesting
  static MediaProbeResult classify({
    required String url,
    required List<int> bytes,
    required Map<String, String> responseHeaders,
    int latencyMs = 0,
  }) {
    final total = totalBytesOf(responseHeaders['content-range']);
    // 不看 content-type：国内 CDN 常把音频标成 application/octet-stream 甚至
    // text/plain，文件头魔数比响应头可信。
    final sniffed = PlaybackCacheService.extensionFromBytes(bytes, fallback: '');
    final extension = sniffed.isNotEmpty ? sniffed : audioExtensionOf(url);
    if (extension == null) {
      return MediaProbeResult.failed(
        '返回内容不是音频',
        latencyMs: latencyMs,
      );
    }
    return MediaProbeResult(
      ok: true,
      message: '',
      sizeBytes: total,
      extension: extension,
      latencyMs: latencyMs,
    );
  }

  /// 只认 `bytes 0-N/TOTAL` 里的 TOTAL；`content-length` 是这一段的长度，不能当总长。
  @visibleForTesting
  static int? totalBytesOf(String? contentRange) {
    if (contentRange == null) return null;
    final match = RegExp(r'/(\d+)\s*$').firstMatch(contentRange.trim());
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    return value == null || value <= 0 ? null : value;
  }

  static final _audioPath = RegExp(
    r'\.(mp3|flac|wav|m4a|aac|ogg|ape)$',
    caseSensitive: false,
  );

  @visibleForTesting
  static String? audioExtensionOf(String url) {
    final parsed = Uri.tryParse(url);
    final path = (parsed?.path ?? url).toLowerCase();
    final match = _audioPath.firstMatch(path);
    return match == null ? null : '.${match.group(1)!.toLowerCase()}';
  }
}
