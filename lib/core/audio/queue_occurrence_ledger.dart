/// Owns the identity of every slot in the playback queue.
///
/// Extracted from `LxAudioHandler`. A `MediaItem` is not a queue slot: the same
/// song can appear twice in a playlist, and both copies must be individually
/// addressable so that a late URL resolution for copy #1 cannot land on copy #2.
/// The handler therefore keeps a parallel list of occurrence ids, one per slot,
/// and this class owns that list plus the id counter.
///
/// The invariant that matters — and the reason this is a class rather than a
/// bare `List<int>` — is that **ids are never reused**. A resolver callback can
/// outlive the queue mutation that removed its slot; if ids were recycled the
/// stale callback could match a freshly inserted item. Monotonic allocation
/// makes a stale id simply not found.
///
/// [reconcile] is the one operation that looks at items rather than ids: it
/// rebuilds the list after a `setQueue`-style wholesale replacement, keeping
/// the occurrence of every item that survived by identity and allocating fresh
/// ids for the rest. Identity (`identical`) rather than equality is deliberate —
/// two equal items in the old queue are two different slots.
class QueueOccurrenceLedger {
  final List<int> _ids = [];
  int _nextId = 0;

  /// Number of slots currently tracked.
  int get length => _ids.length;

  bool get isEmpty => _ids.isEmpty;

  /// Read-only view, for assertions and diagnostics.
  List<int> get ids => List.unmodifiable(_ids);

  /// Allocates a fresh id. The counter only ever moves forward.
  int allocate() => ++_nextId;

  /// Allocates [count] fresh consecutive ids.
  List<int> allocateMany(int count) =>
      List<int>.generate(count, (_) => allocate(), growable: false);

  /// Occurrence id of the slot at [index].
  int at(int index) => _ids[index];

  /// Index of [occurrenceId], or -1 when that slot is gone.
  int indexOf(int occurrenceId) => _ids.indexOf(occurrenceId);

  /// Replaces the whole ledger with [next], e.g. after a lazy-queue rebuild
  /// that already decided the new ids.
  void assignAll(Iterable<int> next) {
    _ids
      ..clear()
      ..addAll(next);
  }

  /// Appends already-allocated ids.
  void appendAll(Iterable<int> next) => _ids.addAll(next);

  /// Appends one slot with a fresh id.
  void appendNew() => _ids.add(allocate());

  void removeAt(int index) => _ids.removeAt(index);

  /// Drops the first [count] slots, matching a history trim of the item list.
  void removeFirst(int count) {
    if (count <= 0) return;
    _ids.removeRange(0, count);
  }

  void clear() => _ids.clear();

  /// Rebuilds the ledger for a wholesale queue replacement.
  ///
  /// Slots whose item survived by identity keep their occurrence (so an
  /// in-flight resolution still targets the right slot); everything else gets
  /// a fresh id. A repeated item that appears twice in [nextItems] consumes two
  /// distinct old slots, not one twice.
  void reconcile({
    required List<Object?> previousItems,
    required List<Object?> nextItems,
  }) {
    final previousIds = List<int>.of(_ids);
    final claimed = <int>{};
    final next = <int>[];
    for (final item in nextItems) {
      var oldIndex = -1;
      for (var i = 0; i < previousItems.length; i++) {
        if (!claimed.contains(i) && identical(previousItems[i], item)) {
          oldIndex = i;
          break;
        }
      }
      if (oldIndex >= 0) {
        claimed.add(oldIndex);
        next.add(previousIds[oldIndex]);
      } else {
        next.add(allocate());
      }
    }
    assignAll(next);
  }
}
