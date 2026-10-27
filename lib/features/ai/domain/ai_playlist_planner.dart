// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/network/music_source_service.dart';
import '../../player/domain/music_item.dart';
import 'ai_client.dart';
import 'ai_config.dart';

/// AI 给出的一首歌（还没在曲库里匹配）。
@immutable
class AiSongRequest {
  const AiSongRequest({
    required this.title,
    this.artist = '',
    this.reason = '',
  });

  final String title;
  final String artist;
  final String reason;

  /// 搜索时用「歌名 + 歌手」，比只搜歌名稳。
  String get query => artist.isEmpty ? title : '$title $artist';
}

@immutable
class AiPlaylistDraft {
  const AiPlaylistDraft({
    required this.name,
    required this.description,
    required this.songs,
  });

  final String name;
  final String description;
  final List<AiSongRequest> songs;

  bool get isEmpty => songs.isEmpty;
}

/// 把自然语言需求变成结构化歌单。
class AiPlaylistPlanner {
  AiPlaylistPlanner({AiClient? client}) : _client = client ?? AiClient();

  final AiClient _client;

  static const int maxSongs = 25;

  static const String systemPrompt =
      '你是音乐歌单助手。根据用户描述挑选真实存在、发行过的歌曲。'
      '只输出 JSON，不要解释，不要 Markdown 代码块。格式：'
      '{"name":"歌单名","description":"一句话介绍",'
      '"songs":[{"title":"歌名","artist":"歌手","reason":"为什么选它（不超过20字）"}]}'
      '歌名与歌手必须使用发行时的正式写法。不要编造不存在的歌。';

  Future<AiPlaylistDraft> plan({
    required AiConfig config,
    required String apiKey,
    required String request,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final text = await _client.complete(
      config: config,
      apiKey: apiKey,
      messages: [
        const AiMessage(AiRole.system, systemPrompt),
        AiMessage(AiRole.user, request.trim()),
      ],
      timeout: timeout,
    );
    return parse(text, fallbackName: request.trim());
  }

  /// 从模型输出里抠出 JSON。
  ///
  /// 即便提示词说了「只输出 JSON」，模型偶尔仍会包一层代码块或前后加一句话，
  /// 所以这里不做严格校验，只找第一个 `{` 到最后一个 `}`。
  @visibleForTesting
  static AiPlaylistDraft parse(String raw, {String fallbackName = ''}) {
    final text = _stripFences(raw);
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AiException(AiFailureKind.badResponse, '返回内容里没有 JSON');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } on FormatException catch (error) {
      throw AiException(AiFailureKind.badResponse, error.message);
    }
    if (decoded is! Map) {
      throw const AiException(AiFailureKind.badResponse, 'JSON 顶层不是对象');
    }

    final songs = <AiSongRequest>[];
    final rawSongs = decoded['songs'] ?? decoded['tracks'] ?? decoded['list'];
    if (rawSongs is List) {
      for (final item in rawSongs) {
        final song = _songOf(item);
        if (song != null) songs.add(song);
        if (songs.length >= maxSongs) break;
      }
    }

    final name = (decoded['name'] ?? decoded['title'] ?? '').toString().trim();
    final description = (decoded['description'] ?? decoded['desc'] ?? '')
        .toString()
        .trim();
    return AiPlaylistDraft(
      name: name.isEmpty ? _defaultName(fallbackName) : name,
      description: description,
      songs: songs,
    );
  }

  static AiSongRequest? _songOf(Object? item) {
    if (item is String) {
      final value = item.trim();
      return value.isEmpty ? null : AiSongRequest(title: value);
    }
    if (item is! Map) return null;
    final title = (item['title'] ?? item['name'] ?? item['song'] ?? '')
        .toString()
        .trim();
    if (title.isEmpty) return null;
    final artist = (item['artist'] ?? item['singer'] ?? item['artists'] ?? '')
        .toString()
        .trim();
    final reason = (item['reason'] ?? item['why'] ?? item['note'] ?? '')
        .toString()
        .trim();
    return AiSongRequest(
      title: title,
      artist: artist,
      reason: reason.length > 60 ? '${reason.substring(0, 60)}…' : reason,
    );
  }

  static String _stripFences(String raw) {
    var text = raw.trim();
    if (!text.contains('```')) return text;
    final fenceStart = text.indexOf('```');
    final firstNewline = text.indexOf('\n', fenceStart);
    if (firstNewline < 0) return text;
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd <= firstNewline) {
      return text.substring(firstNewline + 1);
    }
    return text.substring(firstNewline + 1, fenceEnd);
  }

  static String _defaultName(String request) {
    final value = request.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return 'AI 歌单';
    return value.length > 20 ? '${value.substring(0, 20)}…' : value;
  }
}

/// 一首 AI 请求在曲库里匹配到的结果。
@immutable
class AiSongMatch {
  const AiSongMatch({required this.request, required this.song, this.score = 0});

  final AiSongRequest request;

  /// null 表示曲库里没找到足够像的版本。
  final MusicItem? song;
  final double score;

  bool get matched => song != null;
}

/// 逐首去曲库搜，挑最像的一版。
///
/// 匹配故意保守：宁可留空让用户自己补，也不要塞一首同名不同曲的歌进歌单。
class AiPlaylistMatcher {
  AiPlaylistMatcher({required this.service});

  final MusicSourceService service;

  static const double minimumScore = 0.55;

  Future<List<AiSongMatch>> match(
    List<AiSongRequest> requests, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cancelled = isCancelled ?? () => false;
    final matches = <AiSongMatch>[];
    for (var index = 0; index < requests.length; index++) {
      if (cancelled()) break;
      final request = requests[index];
      onProgress?.call(index, requests.length);
      MusicItem? best;
      var bestScore = 0.0;
      try {
        final results = await service
            .search(request.query, limit: 10)
            .timeout(const Duration(seconds: 20));
        for (final item in results) {
          final score = scoreOf(request, item);
          if (score > bestScore) {
            bestScore = score;
            best = item;
          }
        }
      } catch (_) {
        // 搜不到就留空，不影响其它歌。
      }
      matches.add(
        AiSongMatch(
          request: request,
          song: bestScore >= minimumScore ? best : null,
          score: bestScore,
        ),
      );
    }
    onProgress?.call(requests.length, requests.length);
    return matches;
  }

  /// 0~1 的相似度。歌名越接近分越高，歌手对得上再加一档。
  @visibleForTesting
  static double scoreOf(AiSongRequest request, MusicItem item) {
    final wantTitle = _normalize(request.title);
    final wantArtist = _normalize(request.artist);
    final title = _normalize(item.name);
    final artist = _normalize(item.singer);
    if (wantTitle.isEmpty || title.isEmpty) return 0;

    final artistHit =
        wantArtist.isEmpty ||
        artist.contains(wantArtist) ||
        wantArtist.contains(artist);
    if (title == wantTitle) {
      if (wantArtist.isEmpty) return 0.9;
      return artistHit ? 1 : 0.8;
    }
    if (title.contains(wantTitle) || wantTitle.contains(title)) {
      return artistHit ? 0.7 : 0.55;
    }
    return 0;
  }

  static final _noise = RegExp(
    r'''[\s\-_·•,，.。!！?？:：;；()（）\[\]【】「」《》"'’“”]''',
  );

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(_noise, '');
}
