import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../network/app_http_client.dart';
import '../../../features/player/domain/music_item.dart';

enum SourceFailureKind { offline, timeout, http, unexpected }

/// A failed source call that search can show instead of an empty song list.
class SourceFailure implements Exception {
  const SourceFailure({
    required this.platformId,
    required this.operation,
    required this.kind,
    required this.cause,
    this.statusCode,
  });

  final String platformId;
  final String operation;
  final SourceFailureKind kind;
  final Object cause;
  final int? statusCode;

  static SourceFailure classify(
    String platformId,
    String operation,
    Object error,
  ) {
    if (error is SourceFailure) return error;
    if (error is TimeoutException) {
      return SourceFailure(
        platformId: platformId,
        operation: operation,
        kind: SourceFailureKind.timeout,
        cause: error,
      );
    }
    if (error is SocketException) {
      return SourceFailure(
        platformId: platformId,
        operation: operation,
        kind: SourceFailureKind.offline,
        cause: error,
      );
    }
    if (error is DioException) {
      final status = error.response?.statusCode;
      final type = error.type;
      if (type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout) {
        return SourceFailure(
          platformId: platformId,
          operation: operation,
          kind: SourceFailureKind.timeout,
          cause: error,
        );
      }
      final offline = type == DioExceptionType.connectionError ||
          type == DioExceptionType.connectionTimeout ||
          (type == DioExceptionType.unknown && error.error is SocketException);
      if (offline) {
        return SourceFailure(
          platformId: platformId,
          operation: operation,
          kind: SourceFailureKind.offline,
          cause: error,
        );
      }
      if (status != null) {
        return SourceFailure(
          platformId: platformId,
          operation: operation,
          kind: SourceFailureKind.http,
          cause: error,
          statusCode: status,
        );
      }
    }
    return SourceFailure(
      platformId: platformId,
      operation: operation,
      kind: SourceFailureKind.unexpected,
      cause: error,
    );
  }

  String get message {
    switch (kind) {
      case SourceFailureKind.offline:
        return '网络不可用，请检查连接后再试';
      case SourceFailureKind.timeout:
        return '音源响应超时';
      case SourceFailureKind.http:
        return statusCode == null
            ? '音源接口返回错误'
            : '音源接口返回错误（$statusCode）';
      case SourceFailureKind.unexpected:
        return '音源暂时不可用';
    }
  }

  @override
  String toString() => message;
}

class LeaderboardCategory {
  final String id;
  final String name;
  final String? platform;
  final String? coverUrl;
  const LeaderboardCategory({
    required this.id,
    required this.name,
    this.platform,
    this.coverUrl,
  });

  LeaderboardCategory copyWith({
    String? id,
    String? name,
    String? platform,
    String? coverUrl,
  }) {
    return LeaderboardCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }
}

abstract class MusicPlatform {
  String get id;
  String get name;

  /// Last classified failure. Search throws it; other calls keep a degraded
  /// empty result but leave this set so the UI can tell "no such song" from
  /// "the source failed".
  SourceFailure? lastFailure;

  SourceFailure noteFailure(String operation, Object error) {
    final failure = SourceFailure.classify(id, operation, error);
    lastFailure = failure;
    debugPrint(
      '[source:$id] $operation ${failure.kind.name} ${failure.cause}',
    );
    return failure;
  }

  void clearFailure() => lastFailure = null;

  Future<List<MusicItem>> search(String keyword,
      {int page = 1, int limit = 20});
  Future<String?> getMusicUrl(MusicItem music, {String quality = '128k'});

  /// Coordinator-only exact request. Legacy callers continue using getMusicUrl.
  Future<String?> getMusicUrlExact(MusicItem music,
          {required String quality}) async =>
      null;
  Future<ExactPlayUrl?> getMusicUrlExactDetailed(MusicItem music,
      {required String quality}) async {
    final url = await getMusicUrlExact(music, quality: quality);
    return url == null ? null : ExactPlayUrl(url: url, actualQuality: quality);
  }

  String? exactAttemptKey(String quality) => null;
  Future<String?> getLyric(MusicItem music);
  Future<String?> getArtwork(MusicItem music) async => null;

  // 歌单搜索接口（可选实现）
  Future<List<MusicItem>> searchSongLists(String keyword,
          {int page = 1, int limit = 20}) async =>
      [];
  // 歌单详情接口（可选实现）
  Future<List<MusicItem>> getSongListDetail(String songListId,
          {int page = 1, int limit = 50}) async =>
      [];

  // 排行榜接口（可选实现）
  Future<List<LeaderboardCategory>> getLeaderboardCategories() async => [];
  Future<List<MusicItem>> getLeaderboardSongs(String leaderboardId,
          {int page = 1, int limit = 100}) async =>
      [];

  Dio createDio() {
    return AppHttpClient.create(
        options: BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
      },
    ));
  }

  final Map<String, Dio> _reusedServiceClients = {};

  Dio createDioForService(
      {Duration? connectTimeout,
      Duration? receiveTimeout,
      Map<String, dynamic>? headers}) {
    final connect = connectTimeout ?? const Duration(seconds: 8);
    final receive = receiveTimeout ?? const Duration(seconds: 10);
    final headerEntries = (headers ?? const <String, dynamic>{}).entries
        .toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    final key = '${connect.inMilliseconds}|${receive.inMilliseconds}|'
        '${headerEntries.map((entry) => '${entry.key}=${entry.value}').join('&')}';
    return _reusedServiceClients.putIfAbsent(key, () {
      return AppHttpClient.create(
          options: BaseOptions(
        connectTimeout: connect,
        receiveTimeout: receive,
        headers: headers,
      ));
    });
  }

  void closeReusedServiceClients() {
    for (final client in _reusedServiceClients.values) {
      client.close(force: true);
    }
    _reusedServiceClients.clear();
  }

  MusicItem parseItem(Map<String, dynamic> raw, String source);
}

class ExactPlayUrl {
  final String url;
  final String actualQuality;

  const ExactPlayUrl({required this.url, required this.actualQuality});
}
