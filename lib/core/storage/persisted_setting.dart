import 'dart:async';

import '../../../core/storage/storage_service.dart';

/// A single persisted setting: one value, a storage key, and a write queue.
///
/// Extracted from `_PersistedSettingNotifier` when the app moved from
/// `StateNotifierProvider` to `NotifierProvider`. `Notifier.build()` runs
/// inside the provider container, which makes it impossible to construct a
/// notifier directly in a unit test and read `state` synchronously — the very
/// thing twelve test files do to exercise load/mutation races.
///
/// Splitting the state machine out means:
///
/// * this class is a plain object: construct it, call [set], read [value];
/// * the Riverpod class is a five-line adapter that forwards to it.
///
/// The race rules live here and are the reason this is a class rather than
/// three fields in the notifier:
///
/// * **Loads are best-effort and never overwrite a user mutation.** A load
///   captures [generation] before awaiting storage; if the user changed the
///   value in the meantime the generation moved and the stale read is dropped.
/// * **Writes are serialised.** Two rapid setter calls must reach storage in
///   the same order the user made them, so writes are chained through
///   [_writeTail] rather than fired concurrently.
/// * **A failed write rolls the in-memory value back**, but only if nothing
///   newer has been applied since.
class PersistedSetting<T> {
  PersistedSetting({required T initialValue, StorageLoader? storage})
    : _value = initialValue,
      _storage = storage ?? (() => StorageService.instance);

  final StorageLoader _storage;

  T _value;
  int _generation = 0;
  Future<void> _writeTail = Future<void>.value();

  /// The current value. Always readable synchronously.
  T get value => _value;

  /// Current generation, exposed so adapters can detect stale loads.
  int get generation => _generation;

  /// Reads the persisted value through [read] and applies it unless a user
  /// mutation happened while the read was in flight.
  ///
  /// [read] returns null when nothing is stored, in which case the initial
  /// value is kept.
  Future<void> load(T? Function(StorageService storage) read) async {
    final generation = _generation;
    try {
      final value = read(await _storage());
      if (generation == _generation && value != null) {
        _value = value;
      }
    } catch (_) {
      // A failed load must not overwrite a newer mutation, and the initial
      // value is a safe fallback.
    }
  }

  /// Applies [value] and persists it.
  ///
  /// Returns whether this call's write is still authoritative when it
  /// completes; callers use `false` to skip follow-up work (e.g. telling the
  /// audio handler to reload at a new quality) that a newer mutation has
  /// already superseded.
  Future<bool> set(
    T value,
    Future<bool> Function(StorageService storage) write,
  ) async {
    final generation = ++_generation;
    final previous = _value;
    _value = value;
    try {
      final storage = await _storage();
      if (generation != _generation) return false;

      final pendingWrite = _writeTail.then<bool>((_) async {
        if (generation != _generation) return false;
        await write(storage);
        return generation == _generation;
      });
      _writeTail = pendingWrite.then<void>((_) {}, onError: (_, _) {});
      return await pendingWrite;
    } catch (_) {
      if (generation == _generation && _value == value) _value = previous;
      rethrow;
    }
  }

  /// Applies a value that was already persisted elsewhere (e.g. restored from
  /// a cloud backup) without writing it again.
  void applyCommitted(T value) {
    ++_generation;
    _value = value;
  }
}
