import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/queue_occurrence_ledger.dart';

/// Two *distinct* objects that compare equal. The ledger must treat them as
/// two slots, which is exactly the case a value-equality implementation would
/// get wrong.
class _Item {
  _Item(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is _Item && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => '_Item($name)';
}

void main() {
  group('QueueOccurrenceLedger allocation', () {
    test('ids are allocated monotonically and never recycled', () {
      final ledger = QueueOccurrenceLedger();
      expect(ledger.allocate(), 1);
      expect(ledger.allocate(), 2);
      ledger.appendNew(); // consumes 3
      expect(ledger.ids, [3]);
      ledger.clear();
      // Cleared, but the counter must not restart: a stale resolver callback
      // holding id 1 must never match a slot created after the clear.
      expect(ledger.allocate(), 4);
    });

    test('allocateMany returns consecutive ids and leaves the list untouched', () {
      final ledger = QueueOccurrenceLedger();
      expect(ledger.allocateMany(3), [1, 2, 3]);
      expect(ledger.length, 0);
      ledger.appendAll(ledger.allocateMany(2));
      expect(ledger.ids, [4, 5]);
    });

    test('at and indexOf agree with the tracked order', () {
      final ledger = QueueOccurrenceLedger()..assignAll([10, 20, 30]);
      expect(ledger.at(0), 10);
      expect(ledger.at(2), 30);
      expect(ledger.indexOf(20), 1);
      expect(ledger.indexOf(99), -1);
    });
  });

  group('QueueOccurrenceLedger structural mutations', () {
    test('removeFirst drops the oldest slots and ignores non-positive counts', () {
      final ledger = QueueOccurrenceLedger()..assignAll([1, 2, 3, 4]);
      ledger.removeFirst(0);
      expect(ledger.ids, [1, 2, 3, 4]);
      ledger.removeFirst(-5);
      expect(ledger.ids, [1, 2, 3, 4]);
      ledger.removeFirst(2);
      expect(ledger.ids, [3, 4]);
    });

    test('removeAt drops exactly one slot', () {
      final ledger = QueueOccurrenceLedger()..assignAll([1, 2, 3]);
      ledger.removeAt(1);
      expect(ledger.ids, [1, 3]);
    });

    test('isEmpty tracks the slot count', () {
      final ledger = QueueOccurrenceLedger();
      expect(ledger.isEmpty, isTrue);
      ledger.appendNew();
      expect(ledger.isEmpty, isFalse);
      ledger.clear();
      expect(ledger.isEmpty, isTrue);
    });
  });

  group('QueueOccurrenceLedger.reconcile', () {
    test('surviving items keep their occurrence id', () {
      final a = _Item('a');
      final b = _Item('b');
      final ledger = QueueOccurrenceLedger()..assignAll([7, 8]);

      ledger.reconcile(previousItems: [a, b], nextItems: [b, a]);

      expect(ledger.ids, [8, 7]);
    });

    test('items absent from the old queue get fresh ids', () {
      final a = _Item('a');
      final c = _Item('c');
      final ledger = QueueOccurrenceLedger()..assignAll([7]);

      ledger.reconcile(previousItems: [a], nextItems: [a, c]);

      expect(ledger.ids.first, 7);
      expect(ledger.ids.last, 1, reason: 'fresh ids come from the counter');
    });

    test('duplicate items consume one old slot each, not one slot twice', () {
      final a = _Item('a');
      final ledger = QueueOccurrenceLedger()..assignAll([7, 8]);

      // `a` appears twice in both lists; both copies are distinct objects, so
      // identity matching must map them one-to-one.
      final first = _Item('a');
      final second = _Item('a');
      ledger.reconcile(
        previousItems: [first, second],
        nextItems: [second, first],
      );

      expect(ledger.ids, [8, 7]);
      expect(a, first, reason: 'value-equal objects are still distinct slots');
    });

    test('an item repeated only in the new list reuses the single old slot once', () {
      final a = _Item('a');
      final ledger = QueueOccurrenceLedger()..assignAll([7]);

      ledger.reconcile(previousItems: [a], nextItems: [a, a]);

      expect(ledger.ids.first, 7);
      expect(ledger.ids.length, 2);
      expect(ledger.ids.toSet().length, 2, reason: 'ids must stay unique');
    });

    test('equality is not identity: value-equal replacements get new ids', () {
      final old = _Item('a');
      final replacement = _Item('a');
      expect(old, replacement);
      final ledger = QueueOccurrenceLedger()..assignAll([7]);

      ledger.reconcile(previousItems: [old], nextItems: [replacement]);

      expect(ledger.ids.single, isNot(7));
    });

    test('reconciling an empty new list clears the ledger', () {
      final a = _Item('a');
      final ledger = QueueOccurrenceLedger()..assignAll([7, 8]);

      ledger.reconcile(previousItems: [a], nextItems: const []);

      expect(ledger.isEmpty, isTrue);
    });
  });
}
