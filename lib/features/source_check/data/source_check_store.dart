// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../core/storage/storage_service.dart';
import '../domain/source_check_report.dart';

/// 检测报告的落盘位置。
///
/// 只存结论（成功/超时/失败、延迟、体积），不存地址——脚本返回的链接带签名、
/// 几小时后就失效，留着既没用又容易泄漏。
class SourceCheckStore {
  SourceCheckStore({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance);

  static const String storageKey = 'source_check_report';

  final StorageLoader _storage;

  Future<SourceCheckBook> load() async {
    try {
      final json = (await _storage()).getJson(storageKey);
      if (json == null) return SourceCheckBook.empty;
      return SourceCheckBook.fromJson(json);
    } catch (_) {
      return SourceCheckBook.empty;
    }
  }

  Future<void> save(SourceCheckBook book) async {
    try {
      await (await _storage()).setJson(storageKey, book.toJson());
    } catch (_) {
      // 报告只是加速用的缓存，写失败不该打断检测结果展示。
    }
  }
}
