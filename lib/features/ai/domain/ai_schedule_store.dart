// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import '../../../core/storage/storage_service.dart';
import 'ai_schedule.dart';

/// AI 定时任务的落盘位置。
class AiScheduleStore {
  AiScheduleStore({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance);

  static const String storageKey = 'ai_schedules_v1';

  final StorageLoader _storage;

  Future<List<AiScheduledTask>> load() async {
    try {
      final rows = (await _storage()).getJsonList(storageKey);
      return [
        for (final row in rows)
          if (AiScheduledTask.fromJson(row) case final task?) task,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<AiScheduledTask> tasks) async {
    final storage = await _storage();
    if (tasks.isEmpty) {
      await storage.remove(storageKey);
      return;
    }
    await storage.setJsonList(storageKey, [
      for (final task in tasks) task.toJson(),
    ]);
  }
}
