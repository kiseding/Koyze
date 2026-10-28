// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../core/storage/storage_service.dart';
import '../domain/recommendation_tuning.dart';

/// 「猜你喜欢」调校的落盘位置。
///
/// 和推荐结果本身分开存：结果 12 小时过期，调校是用户（或 AI）明确表达过的
/// 偏好，不会自己消失。
class RecommendationTuningStore {
  RecommendationTuningStore({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance);

  static const String storageKey = 'recommendation_tuning_v1';

  final StorageLoader _storage;

  Future<RecommendationTuning> load() async {
    try {
      final json = (await _storage()).getJson(storageKey);
      if (json == null) return RecommendationTuning.empty;
      return RecommendationTuning.fromJson(json);
    } catch (_) {
      return RecommendationTuning.empty;
    }
  }

  Future<void> save(RecommendationTuning tuning) async {
    final storage = await _storage();
    if (tuning.isEmpty) {
      await storage.remove(storageKey);
      return;
    }
    await storage.setJson(storageKey, tuning.toJson());
  }
}
