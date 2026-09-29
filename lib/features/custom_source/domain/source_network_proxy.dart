// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// Network proxy for custom source scripts.
/// 
/// Provides:
/// - Domain whitelist enforcement
/// - Rate limiting (30 requests/minute per source)
/// - Response size limits
/// - Private IP blocking
/// - Audit logging

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SecurityException implements Exception {
  final String message;
  final String? code;

  SecurityException(this.message, {this.code});

  @override
  String toString() => 'SecurityException: $message';
}

class AuditEntry {
  final String sourceId;
  final String url;
  final DateTime timestamp;
  final int? statusCode;
  final int? responseSize;
  final Duration? duration;
  final String? error;

  AuditEntry({
    required this.sourceId,
    required this.url,
    required this.timestamp,
    this.statusCode,
    this.responseSize,
    this.duration,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'url': url,
        'timestamp': timestamp.toIso8601String(),
        if (statusCode != null) 'statusCode': statusCode,
        if (responseSize != null) 'responseSize': responseSize,
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        if (error != null) 'error': error,
      };
}

class SourceNetworkProxy {
  static const int MAX_REQUESTS_PER_MINUTE = 30;
  static const int MAX_RESPONSE_SIZE = 10 * 1024 * 1024; // 10MB
  static const Duration REQUEST_TIMEOUT = Duration(seconds: 10);
  static const int RATE_LIMIT_WINDOW_MS = 60000; // 1 minute

  // Whitelist: Known music platform domains
  static final Set<String> _allowedDomains = {
    // QQ Music
    'qq.com',
    'gtimg.cn',
    'music.tc.qq.com',
    'y.qq.com',
    'c.y.qq.com',
    'u.y.qq.com',
    'api.qq.com',
    
    // NetEase Cloud Music
    '163.com',
    'music.163.com',
    'api.music.163.com',
    'p1.music.126.net',
    'p2.music.126.net',
    'p3.music.126.net',
    'p4.music.126.net',
    
    // Kuwo Music
    'kuwo.cn',
    'api.kuwo.cn',
    'img.kuwo.cn',
    
    // Kugou Music
    'kugou.com',
    'kugoucdn.com',
    
    // Migu Music
    'migu.cn',
    'miguvideo.com',
    
    // Additional common music CDNs
    'music.126.net',
    'qqmusic.qq.com',
  };

  final Dio _dio;
  final Map<String, List<DateTime>> _requestTimestamps = {};
  final List<AuditEntry> _auditLog = [];
  final int _maxAuditEntries;

  SourceNetworkProxy({
    Dio? dio,
    int maxAuditEntries = 1000,
  })  : _dio = dio ?? Dio(),
        _maxAuditEntries = maxAuditEntries {
    _configureDio();
  }

  void _configureDio() {
    _dio.options.connectTimeout = REQUEST_TIMEOUT;
    _dio.options.receiveTimeout = REQUEST_TIMEOUT;
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 3;
    _dio.options.validateStatus = (status) =>
        status != null && status >= 200 && status < 500;
  }

  /// Fetch a URL with security checks.
  Future<Response> fetch(
    String url,
    String sourceId, {
    Map<String, dynamic>? headers,
    String method = 'GET',
    dynamic data,
  }) async {
    final stopwatch = Stopwatch()..start();
    final timestamp = DateTime.now();
    
    try {
      // 1. URL validation
      final uri = _validateUrl(url);

      // 2. Domain whitelist check
      if (!_isAllowedDomain(uri.host)) {
        _logRequest(
          sourceId: sourceId,
          url: url,
          timestamp: timestamp,
          error: 'Domain not in whitelist: ${uri.host}',
        );
        throw SecurityException(
          'Domain not in whitelist: ${uri.host}',
          code: 'DOMAIN_NOT_ALLOWED',
        );
      }

      // 3. Private IP check
      if (await _isPrivateIP(uri.host)) {
        _logRequest(
          sourceId: sourceId,
          url: url,
          timestamp: timestamp,
          error: 'Private network access forbidden',
        );
        throw SecurityException(
          'Private network access forbidden',
          code: 'PRIVATE_IP_FORBIDDEN',
        );
      }

      // 4. Rate limiting
      await _checkRateLimit(sourceId);

      // 5. Execute request with size limit
      int receivedBytes = 0;
      final response = await _dio.request(
        url,
        options: Options(
          method: method,
          headers: {
            'User-Agent': 'Koyze/3.0',
            'Referer': 'https://y.qq.com',
            ...?headers,
          },
        ),
        data: data,
        onReceiveProgress: (received, total) {
          receivedBytes = received;
          if (received > MAX_RESPONSE_SIZE) {
            throw SecurityException(
              'Response exceeds size limit of ${MAX_RESPONSE_SIZE ~/ (1024 * 1024)}MB',
              code: 'RESPONSE_TOO_LARGE',
            );
          }
        },
      );

      stopwatch.stop();

      // 6. Audit logging
      _logRequest(
        sourceId: sourceId,
        url: url,
        timestamp: timestamp,
        statusCode: response.statusCode,
        responseSize: receivedBytes,
        duration: stopwatch.elapsed,
      );

      return response;
    } on DioException catch (e) {
      stopwatch.stop();
      _logRequest(
        sourceId: sourceId,
        url: url,
        timestamp: timestamp,
        error: 'DioException: ${e.type} - ${e.message}',
        duration: stopwatch.elapsed,
      );
      rethrow;
    } on SecurityException {
      rethrow;
    } catch (e) {
      stopwatch.stop();
      _logRequest(
        sourceId: sourceId,
        url: url,
        timestamp: timestamp,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
      rethrow;
    }
  }

  Uri _validateUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw SecurityException(
          'Only HTTP/HTTPS protocols are allowed',
          code: 'INVALID_PROTOCOL',
        );
      }
      if (!uri.hasAuthority || uri.host.isEmpty) {
        throw SecurityException('Invalid URL format', code: 'INVALID_URL');
      }
      return uri;
    } catch (e) {
      if (e is SecurityException) rethrow;
      throw SecurityException('Invalid URL: $e', code: 'INVALID_URL');
    }
  }

  bool _isAllowedDomain(String host) {
    // Exact match
    if (_allowedDomains.contains(host)) return true;

    // Subdomain match (e.g., api.music.163.com matches 163.com)
    for (final allowed in _allowedDomains) {
      if (host == allowed || host.endsWith('.$allowed')) {
        return true;
      }
    }

    return false;
  }

  Future<bool> _isPrivateIP(String host) async {
    try {
      // Check if it's already an IP address
      final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
      if (ipPattern.hasMatch(host)) {
        return _isPrivateIPAddress(host);
      }

      // Resolve hostname to IP
      final addresses = await InternetAddress.lookup(host);
      for (final addr in addresses) {
        if (_isPrivateIPAddress(addr.address)) {
          return true;
        }
      }
      return false;
    } catch (e) {
      // If DNS resolution fails, allow (it will fail at connection time)
      debugPrint('DNS resolution failed for $host: $e');
      return false;
    }
  }

  bool _isPrivateIPAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList();
    if (octets.any((o) => o == null || o < 0 || o > 255)) return false;

    final first = octets[0]!;
    final second = octets[1]!;

    // 10.0.0.0/8
    if (first == 10) return true;

    // 172.16.0.0/12
    if (first == 172 && second >= 16 && second <= 31) return true;

    // 192.168.0.0/16
    if (first == 192 && second == 168) return true;

    // 127.0.0.0/8 (localhost)
    if (first == 127) return true;

    // 169.254.0.0/16 (link-local)
    if (first == 169 && second == 254) return true;

    // 0.0.0.0/8
    if (first == 0) return true;

    return false;
  }

  Future<void> _checkRateLimit(String sourceId) async {
    final now = DateTime.now();
    final timestamps = _requestTimestamps[sourceId] ?? [];

    // Remove timestamps older than the window
    timestamps.removeWhere(
      (ts) => now.difference(ts).inMilliseconds > RATE_LIMIT_WINDOW_MS,
    );

    if (timestamps.length >= MAX_REQUESTS_PER_MINUTE) {
      final oldestRequest = timestamps.first;
      final waitTime = RATE_LIMIT_WINDOW_MS -
          now.difference(oldestRequest).inMilliseconds;
      throw SecurityException(
        'Rate limit exceeded. Wait ${(waitTime / 1000).ceil()} seconds.',
        code: 'RATE_LIMIT_EXCEEDED',
      );
    }

    timestamps.add(now);
    _requestTimestamps[sourceId] = timestamps;
  }

  void _logRequest({
    required String sourceId,
    required String url,
    required DateTime timestamp,
    int? statusCode,
    int? responseSize,
    Duration? duration,
    String? error,
  }) {
    final entry = AuditEntry(
      sourceId: sourceId,
      url: url,
      timestamp: timestamp,
      statusCode: statusCode,
      responseSize: responseSize,
      duration: duration,
      error: error,
    );

    _auditLog.add(entry);

    // Limit audit log size
    if (_auditLog.length > _maxAuditEntries) {
      _auditLog.removeAt(0);
    }

    // Debug logging
    if (kDebugMode) {
      if (error != null) {
        debugPrint('🚫 Network request failed: $url - $error');
      } else {
        debugPrint(
          '✅ Network request: $url - ${statusCode ?? "?"} (${duration?.inMilliseconds ?? "?"}ms)',
        );
      }
    }
  }

  /// Get audit log entries for a specific source.
  List<AuditEntry> getAuditLog({String? sourceId, int? limit}) {
    var entries = sourceId == null
        ? _auditLog
        : _auditLog.where((e) => e.sourceId == sourceId).toList();

    if (limit != null && entries.length > limit) {
      entries = entries.sublist(entries.length - limit);
    }

    return entries;
  }

  /// Get network statistics for a source.
  Map<String, dynamic> getStats(String sourceId) {
    final entries = _auditLog.where((e) => e.sourceId == sourceId).toList();
    final now = DateTime.now();
    final recentEntries = entries
        .where((e) => now.difference(e.timestamp).inMinutes < 60)
        .toList();

    final successfulRequests =
        recentEntries.where((e) => e.statusCode != null && e.statusCode! < 400);
    final failedRequests =
        recentEntries.where((e) => e.error != null || (e.statusCode ?? 0) >= 400);

    final avgDuration = successfulRequests.isNotEmpty
        ? successfulRequests
                .map((e) => e.duration?.inMilliseconds ?? 0)
                .reduce((a, b) => a + b) /
            successfulRequests.length
        : 0.0;

    final domains = recentEntries
        .map((e) => Uri.tryParse(e.url)?.host ?? 'unknown')
        .toSet();

    return {
      'totalRequests': entries.length,
      'recentRequests': recentEntries.length,
      'successfulRequests': successfulRequests.length,
      'failedRequests': failedRequests.length,
      'avgDurationMs': avgDuration.round(),
      'accessedDomains': domains.toList(),
      'rateLimitRemaining': MAX_REQUESTS_PER_MINUTE -
          (_requestTimestamps[sourceId]?.length ?? 0),
    };
  }

  /// Clear rate limit for a source (admin function).
  void clearRateLimit(String sourceId) {
    _requestTimestamps.remove(sourceId);
  }

  /// Export audit log as JSON.
  List<Map<String, dynamic>> exportAuditLog({String? sourceId}) {
    final entries = sourceId == null
        ? _auditLog
        : _auditLog.where((e) => e.sourceId == sourceId).toList();
    return entries.map((e) => e.toJson()).toList();
  }
}
