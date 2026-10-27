// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/foundation.dart';

import '../../player/domain/music_item.dart';

/// 检测用的样本曲。
///
/// 检测要回答的是「这个脚本此刻还能不能拿到链接」，所以样本必须稳定、长期存在、
/// 且各平台都能搜到同一首。这里挑了四首发行多年、版权覆盖面广的歌；`songmid`
/// 是各平台自己的曲目 id，脚本拿它去换地址，和用户在应用里点播走的是同一条链路。
@immutable
class SourceCheckSample {
  const SourceCheckSample({
    required this.platform,
    required this.name,
    required this.singer,
    required this.songmid,
    this.hash,
    this.album = '',
    this.duration = Duration.zero,
    this.meta,
  });

  final String platform;
  final String name;
  final String singer;
  final String songmid;

  /// 酷狗按 hash 取地址，其余平台为空。
  final String? hash;
  final String album;
  final Duration duration;

  /// 平台特有的字段，例如咪咕的 `copyrightId`。
  final Map<String, dynamic>? meta;

  MusicItem toMusicItem(String sourceId) => MusicItem(
    id: songmid,
    name: name,
    singer: singer,
    album: album,
    duration: duration,
    source: sourceId,
    platform: platform,
    songmid: songmid,
    hash: hash,
    meta: meta,
  );
}

/// 平台 → 样本曲。只覆盖脚本生态里通用的五个平台，其余平台不参与检测。
const Map<String, SourceCheckSample> sourceCheckSamples = {
  'tx': SourceCheckSample(
    platform: 'tx',
    name: '晴天',
    singer: '周杰伦',
    album: '叶惠美',
    songmid: '0039MnYb0qxYhV',
    duration: Duration(minutes: 4, seconds: 29),
  ),
  'kw': SourceCheckSample(
    platform: 'kw',
    name: '晴天',
    singer: '周杰伦',
    album: '叶惠美',
    songmid: '228908',
    duration: Duration(minutes: 4, seconds: 29),
  ),
  'wy': SourceCheckSample(
    platform: 'wy',
    name: '鲜花',
    singer: '回春丹',
    album: '鲜花',
    songmid: '2738715965',
    duration: Duration(minutes: 4, seconds: 48),
  ),
  'kg': SourceCheckSample(
    platform: 'kg',
    name: '演员',
    singer: '薛之谦',
    album: '绅士',
    songmid: '097e777171f692855eae98b6965f9477',
    hash: '097e777171f692855eae98b6965f9477',
    duration: Duration(minutes: 4, seconds: 21),
  ),
  'mg': SourceCheckSample(
    platform: 'mg',
    name: '晴天',
    singer: '周杰伦',
    album: '叶惠美',
    songmid: '600902000006889366',
    duration: Duration(minutes: 4, seconds: 29),
    meta: {'copyrightId': '60054701923'},
  ),
};

/// 音质从高到低的实测顺序，和脚本 `qualitys` 声明取交集后再截断。
const List<String> sourceCheckQualityOrder = [
  'hires',
  'flac24bit',
  'flac',
  '320k',
  '192k',
  '128k',
];
