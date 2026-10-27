// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'source_check_report.dart';

/// 把音源检测的结论喂给选源：明确失败的脚本不再尝试，只有超时的排到最后。
///
/// 只在报告足够新的时候生效——脚本会失效、平台会改接口，一周前的结论不该继续
/// 左右播放。报告过期就当作没测过。
class SourceCheckPolicy {
  SourceCheckPolicy({
    this.book = SourceCheckBook.empty,
    this.maxAge = const Duration(days: 7),
  });

  /// 当前生效的报告。检测跑完由界面层调用 [update] 换掉。
  SourceCheckBook book;
  final Duration maxAge;

  void update(SourceCheckBook next) {
    book = next;
  }

  bool isFresh(SourceCheckPlatformReport report, {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(report.testedAt);
    return age <= maxAge;
  }

  /// 脚本在某个平台上「明确坏了」：全部音质都硬失败。
  bool isHardFail(String sourceId, String platform, {DateTime? now}) {
    final report = book.forSource(sourceId)?.forPlatform(platform);
    if (report == null || !report.tested) return false;
    if (!isFresh(report, now: now)) return false;
    return report.allHardFail;
  }

  /// 脚本在某个平台上「只是超时」：排到最后但仍会尝试。
  bool isSoftFail(String sourceId, String platform, {DateTime? now}) {
    final report = book.forSource(sourceId)?.forPlatform(platform);
    if (report == null || !report.tested) return false;
    if (!isFresh(report, now: now)) return false;
    return report.hasSoftFail;
  }

  /// 重排尝试顺序：可用的在前，只有超时的在后，明确失败的直接剔除。
  ///
  /// 如果剔除后一个不剩，就退回原始顺序——检测结果不该把播放彻底卡死。
  List<String> order(List<String> sourceIds, String platform, {DateTime? now}) {
    if (book.isEmpty) return sourceIds;
    final usable = <String>[];
    final soft = <String>[];
    for (final id in sourceIds) {
      if (isHardFail(id, platform, now: now)) continue;
      if (isSoftFail(id, platform, now: now)) {
        soft.add(id);
      } else {
        usable.add(id);
      }
    }
    if (usable.isEmpty && soft.isEmpty) return sourceIds;
    return [...usable, ...soft];
  }
}
