// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';

import '../../player/domain/music_item.dart';

/// 「猜你喜欢」的人工调校。
///
/// 推荐本身是算法算出来的，用户（或代用户动手的 AI）能改的是三件事：
/// 把某些歌顶到最前面、把某些歌或歌手彻底挡掉、用一句话说明口味。
/// 这三件事都落盘，算法每次重算时先套用它们，再谈排序。
@immutable
class RecommendationTuning {
  const RecommendationTuning({
    this.pinned = const <SongRef>[],
    this.excludedSongs = const <SongRef>[],
    this.excludedArtists = const <String>[],
    this.focus = '',
  });

  static const RecommendationTuning empty = RecommendationTuning();

  /// 置顶歌曲，按用户给的顺序排在推荐最前面。
  final List<SongRef> pinned;

  /// 不希望出现的歌。
  final List<SongRef> excludedSongs;

  /// 不希望出现的歌手（小写原名，比较时再做归一化）。
  final List<String> excludedArtists;

  /// 口味提示，例如「多来点粤语老歌」。会作为额外的检索词去补充候选。
  final String focus;

  static const int maxPinned = 20;
  static const int maxExcludedSongs = 50;
  static const int maxExcludedArtists = 30;
  static const int maxFocusLength = 200;

  bool get isEmpty =>
      pinned.isEmpty &&
      excludedSongs.isEmpty &&
      excludedArtists.isEmpty &&
      focus.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// 这首歌能不能出现在推荐里。
  bool allows(MusicItem song) {
    final singer = normalizeText(song.singer);
    for (final artist in excludedArtists) {
      final blocked = normalizeText(artist);
      if (blocked.isEmpty) continue;
      if (singer == blocked || singer.contains(blocked)) return false;
    }
    for (final ref in excludedSongs) {
      if (ref.matches(song)) return false;
    }
    return true;
  }

  /// 这首歌是不是被置顶的。
  bool isPinned(MusicItem song) => pinned.any((ref) => ref.matches(song));

  RecommendationTuning withPinned(Iterable<SongRef> refs) {
    final next = <SongRef>[...pinned];
    for (final ref in refs) {
      if (ref.title.trim().isEmpty) continue;
      if (next.any((item) => item.sameAs(ref))) continue;
      next.add(ref);
    }
    return copyWith(pinned: next.take(maxPinned).toList(growable: false));
  }

  RecommendationTuning withExcludedSongs(Iterable<SongRef> refs) {
    final next = <SongRef>[...excludedSongs];
    for (final ref in refs) {
      if (ref.title.trim().isEmpty) continue;
      if (next.any((item) => item.sameAs(ref))) continue;
      next.add(ref);
    }
    return copyWith(
      excludedSongs: next.take(maxExcludedSongs).toList(growable: false),
    );
  }

  RecommendationTuning withExcludedArtists(Iterable<String> artists) {
    final next = <String>[...excludedArtists];
    for (final artist in artists) {
      final value = artist.trim();
      if (value.isEmpty) continue;
      if (next.any((item) => normalizeText(item) == normalizeText(value))) {
        continue;
      }
      next.add(value);
    }
    return copyWith(
      excludedArtists: next.take(maxExcludedArtists).toList(growable: false),
    );
  }

  RecommendationTuning withFocus(String value) {
    final text = value.trim();
    return copyWith(
      focus: text.length > maxFocusLength
          ? text.substring(0, maxFocusLength)
          : text,
    );
  }

  /// 清掉某几类调整；[all] 连口味提示一起清。
  RecommendationTuning cleared(Set<TuningSection> sections) {
    final all = sections.contains(TuningSection.all);
    return RecommendationTuning(
      pinned: all || sections.contains(TuningSection.pinned) ? const [] : pinned,
      excludedSongs: all || sections.contains(TuningSection.excluded)
          ? const []
          : excludedSongs,
      excludedArtists: all || sections.contains(TuningSection.artists)
          ? const []
          : excludedArtists,
      focus: all || sections.contains(TuningSection.focus) ? '' : focus,
    );
  }

  RecommendationTuning copyWith({
    List<SongRef>? pinned,
    List<SongRef>? excludedSongs,
    List<String>? excludedArtists,
    String? focus,
  }) => RecommendationTuning(
    pinned: pinned ?? this.pinned,
    excludedSongs: excludedSongs ?? this.excludedSongs,
    excludedArtists: excludedArtists ?? this.excludedArtists,
    focus: focus ?? this.focus,
  );

  Map<String, dynamic> toJson() => {
    if (pinned.isNotEmpty)
      'pinned': [for (final ref in pinned) ref.toJson()],
    if (excludedSongs.isNotEmpty)
      'excludedSongs': [for (final ref in excludedSongs) ref.toJson()],
    if (excludedArtists.isNotEmpty) 'excludedArtists': excludedArtists,
    if (focus.trim().isNotEmpty) 'focus': focus,
  };

  static RecommendationTuning fromJson(Map<String, dynamic> json) {
    List<SongRef> refs(Object? raw) => [
      if (raw is List)
        for (final item in raw)
          if (SongRef.fromJson(item) case final ref?) ref,
    ];
    final focus = (json['focus'] ?? '').toString().trim();
    return RecommendationTuning(
      pinned: refs(json['pinned']).take(maxPinned).toList(growable: false),
      excludedSongs: refs(
        json['excludedSongs'],
      ).take(maxExcludedSongs).toList(growable: false),
      excludedArtists: [
        if (json['excludedArtists'] case final List raw)
          for (final item in raw.take(maxExcludedArtists))
            if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ],
      focus: focus.length > maxFocusLength
          ? focus.substring(0, maxFocusLength)
          : focus,
    );
  }

  /// 给界面和模型看的一句话摘要。
  String describe() => [
    if (pinned.isNotEmpty) '置顶 ${pinned.length} 首',
    if (excludedSongs.isNotEmpty) '屏蔽 ${excludedSongs.length} 首',
    if (excludedArtists.isNotEmpty) '屏蔽 ${excludedArtists.length} 位歌手',
    if (focus.trim().isNotEmpty) '口味「${focus.trim()}」',
  ].join(' · ');
}

enum TuningSection { pinned, excluded, artists, focus, all }

/// 一首歌的最小标识：歌名 + 歌手。
///
/// 不放 id：id 跟着音源变，用户说的「屏蔽这首」指的是这首歌本身。
@immutable
class SongRef {
  const SongRef({required this.title, this.artist = ''});

  final String title;
  final String artist;

  static SongRef? fromJson(Object? raw) {
    if (raw is String) {
      final value = raw.trim();
      return value.isEmpty ? null : SongRef(title: value);
    }
    if (raw is! Map) return null;
    final title = (raw['title'] ?? raw['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final artist = (raw['artist'] ?? raw['singer'] ?? '').toString().trim();
    return SongRef(title: title, artist: artist);
  }

  bool matches(MusicItem song) {
    final wantTitle = normalizeText(title);
    if (wantTitle.isEmpty) return false;
    final songTitle = normalizeText(song.name);
    final titleHit =
        songTitle == wantTitle ||
        songTitle.contains(wantTitle) ||
        wantTitle.contains(songTitle);
    if (!titleHit) return false;
    final wantArtist = normalizeText(artist);
    if (wantArtist.isEmpty) return true;
    final singer = normalizeText(song.singer);
    return singer == wantArtist ||
        singer.contains(wantArtist) ||
        wantArtist.contains(singer);
  }

  bool sameAs(SongRef other) =>
      normalizeText(title) == normalizeText(other.title) &&
      normalizeText(artist) == normalizeText(other.artist);

  Map<String, dynamic> toJson() => {
    'title': title,
    if (artist.isNotEmpty) 'artist': artist,
  };

  @override
  String toString() => artist.isEmpty ? title : '$title · $artist';
}

/// 比较用的归一化：去空白、标点、大小写，只留下字母数字和汉字。
String normalizeText(String value) =>
    value.toLowerCase().replaceAll(_noise, '');

final RegExp _noise = RegExp(
  r'''[\s\-_·•,，.。!！?？:：;；()（）\[\]【】「」《》"'’“”/\\|]''',
);
