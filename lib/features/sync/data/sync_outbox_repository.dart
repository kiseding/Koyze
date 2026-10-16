import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sync_event.dart';

final class SyncOutboxRepository {
  SyncOutboxRepository({Future<SharedPreferences> Function()? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance;

  static const _key = 'sync_outbox_v1';
  final Future<SharedPreferences> Function() _preferences;
  Future<void> _writeTail = Future.value();

  Future<List<SyncEvent>> load() async {
    final prefs = await _preferences();
    final raw = prefs.getStringList(_key) ?? const [];
    final events = <SyncEvent>[];
    for (final value in raw) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          events.add(SyncEvent.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore one corrupted event without losing the remaining queue.
      }
    }
    return events;
  }

  Future<void> append(SyncEvent event) async {
    await _enqueue(() async {
      final events = await load();
      if (events.any((item) => item.eventId == event.eventId)) return;
      events.add(event);
      await _save(events);
    });
  }

  Future<void> removeProcessed(Iterable<String> eventIds) async {
    await _enqueue(() async {
      final ids = eventIds.toSet();
      if (ids.isEmpty) return;
      final events = await load();
      await _save(
        events.where((event) => !ids.contains(event.eventId)).toList(),
      );
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeTail.catchError((_) {}).then((_) => operation());
    _writeTail = next.catchError((_) {});
    return next;
  }

  Future<void> _save(List<SyncEvent> events) async {
    final prefs = await _preferences();
    final ok = await prefs.setStringList(
      _key,
      events.map((event) => event.encode()).toList(growable: false),
    );
    if (!ok) throw StateError('Unable to persist sync outbox');
  }
}
