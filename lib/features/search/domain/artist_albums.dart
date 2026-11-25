import '../../player/domain/music_item.dart';

/// 歌手详情页里的一个专辑分组。
///
/// [time] 取组内最新的发行/入库时间，用于专辑倒序；没有时间信息时为 null，
/// 这类专辑排在有时间的专辑之后，并保持搜索结果里的先后次序。
class ArtistAlbumGroup {
  const ArtistAlbumGroup({
    required this.name,
    required this.songs,
    required this.time,
  });

  final String name;
  final List<MusicItem> songs;
  final DateTime? time;
}

class _MutableGroup {
  _MutableGroup(this.name, this.order);

  final String name;
  final int order;
  final List<MusicItem> songs = <MusicItem>[];
  DateTime? time;
}

/// 常见的发行时间字段名。各平台原始 meta 保留在 MusicItem.meta 里，
/// 字段名并不统一；本地曲库则提供 modifiedAt。
const List<String> _timeKeys = <String>[
  'publishTime',
  'publish_time',
  'pubtime',
  'pubTime',
  'releaseDate',
  'release_time',
  'releaseTime',
  'PublishDate',
  'PublishTime',
  'issueDate',
  'year',
  'modifiedAt',
  'mtime',
  // 不纳入 'time'：平台里通常是歌曲时长而非发行时间。
];

DateTime? groupSongsByAlbumTime(MusicItem song) {
  final meta = song.meta;
  if (meta == null || meta.isEmpty) return null;
  for (final key in _timeKeys) {
    final value = meta[key] ?? meta[key.toLowerCase()];
    final parsed = parseAlbumTime(value);
    if (parsed != null) return parsed;
  }
  // 网易云的 al / alias 结构里偶尔带 publishTime。
  for (final key in const <String>['al', 'album', 'bizInfo']) {
    final nested = meta[key];
    if (nested is! Map) continue;
    for (final timeKey in _timeKeys) {
      final parsed = parseAlbumTime(nested[timeKey]);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// 把时间戳、年份、ISO 日期字符串统一解析成 DateTime。
DateTime? parseAlbumTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) return _albumTimeFromNumber(value.toInt());

  final text = value.toString().trim();
  if (text.isEmpty) return null;
  if (RegExp(r'^\d{4}$').hasMatch(text)) {
    final year = int.parse(text);
    return (year >= 1900 && year <= 2100) ? DateTime(year) : null;
  }
  final number = num.tryParse(text);
  if (number != null) return _albumTimeFromNumber(number.toInt());
  return DateTime.tryParse(text);
}

DateTime? _albumTimeFromNumber(int value) {
  if (value >= 1900 && value <= 2100) return DateTime(value);
  // 13 位毫秒时间戳 / 10 位秒级时间戳。
  if (value > 100000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value > 1000000000) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000);
  }
  return null;
}

/// 按专辑名分组，专辑按最新发行时间倒序；无时间信息的专辑保持原顺序。
/// 组内歌曲保持传入顺序。
List<ArtistAlbumGroup> groupSongsByAlbum(List<MusicItem> songs) {
  final groups = <String, _MutableGroup>{};
  var order = 0;
  for (final song in songs) {
    final key = song.album.trim();
    final group = groups.putIfAbsent(key, () => _MutableGroup(key, order++));
    group.songs.add(song);
    final time = groupSongsByAlbumTime(song);
    if (time != null && (group.time == null || time.isAfter(group.time!))) {
      group.time = time;
    }
  }

  final result = groups.values
      .map(
        (group) => ArtistAlbumGroup(
          name: group.name,
          songs: List<MusicItem>.unmodifiable(group.songs),
          time: group.time,
        ),
      )
      .toList();
  result.sort((a, b) {
    if (a.time != null && b.time != null) {
      final byTime = b.time!.compareTo(a.time!);
      if (byTime != 0) return byTime;
    } else if (a.time != null) {
      return -1;
    } else if (b.time != null) {
      return 1;
    }
    return groups[a.name]!.order.compareTo(groups[b.name]!.order);
  });
  return List<ArtistAlbumGroup>.unmodifiable(result);
}
