import '../../player/domain/music_item.dart';

/// Radio Browser 的一个电台。
///
/// 只保留列表与播放入口真正要用的字段：名字、流地址、封面、标签、码率。
/// 站点总数上万，多解析一个字段就是一次多余的分配。
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.favicon,
    this.tags = '',
    this.country = '',
    this.codec = '',
    this.bitrate = 0,
    this.votes = 0,
  });

  /// `stationuuid`，Radio Browser 的稳定主键。
  final String id;
  final String name;

  /// 解析后的直链。多数是 mp3/aac 的 ICY 流，just_audio 直接吃。
  final String streamUrl;
  final String? favicon;
  final String tags;
  final String country;
  final String codec;
  final int bitrate;
  final int votes;

  /// 列表右侧的一行说明：国家 · 码率 · 编码，缺哪项跳哪项。
  String get subtitleParts {
    final parts = <String>[
      if (country.trim().isNotEmpty) country.trim(),
      if (bitrate > 0) '${bitrate}k',
      if (codec.trim().isNotEmpty) codec.trim().toUpperCase(),
    ];
    return parts.join(' · ');
  }

  /// 转成播放队列用的曲目。
  ///
  /// 电台没有时长、没有专辑，因此 [MusicItem.duration] 为 0，播放器进度条
  /// 一直停在 0——这是直播流的正确表现，不需要特殊分支。
  /// 直链同时写进 `url` 与 `meta.streamUrl`：前者会随队列序列化，后者在
  /// 播放器剥离 `extras['url']` 之后仍然存在，解析时兜底用。
  MusicItem toMusicItem() {
    return MusicItem(
      id: id,
      name: name,
      singer: tags.trim().isEmpty ? country.trim() : tags.trim(),
      album: '',
      source: radioSourceId,
      platform: radioSourceId,
      artwork: favicon,
      url: streamUrl,
      meta: {
        'radio': true,
        'streamUrl': streamUrl,
        if (codec.trim().isNotEmpty) 'codec': codec.trim(),
        if (bitrate > 0) 'bitrate': bitrate,
        if (country.trim().isNotEmpty) 'country': country.trim(),
        if (tags.trim().isNotEmpty) 'tags': tags.trim(),
      },
    );
  }

  static const String radioSourceId = 'radio';

  static RadioStation? fromJson(Map<String, dynamic> json) {
    final id = (json['stationuuid'] ?? json['id'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final resolved = (json['url_resolved'] ?? '').toString().trim();
    final raw = (json['url'] ?? '').toString().trim();
    final stream = resolved.isNotEmpty ? resolved : raw;
    // 没有直链的条目直接丢掉：无法播放的电台出现在列表里只会制造一次点击失败。
    if (id.isEmpty || name.isEmpty || stream.isEmpty) return null;
    final favicon = (json['favicon'] ?? '').toString().trim();
    return RadioStation(
      id: id,
      name: name,
      streamUrl: stream,
      favicon: favicon.isEmpty ? null : favicon,
      tags: (json['tags'] ?? '').toString(),
      country: (json['country'] ?? json['countrycode'] ?? '').toString(),
      codec: (json['codec'] ?? '').toString(),
      bitrate: _asInt(json['bitrate']),
      votes: _asInt(json['votes']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
