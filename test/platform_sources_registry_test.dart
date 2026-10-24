import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/music_source/platform/built_in_source_manager.dart';

void main() {
  test('BuiltInSourceManager registers only supported platforms', () {
    final manager = BuiltInSourceManager();
    addTearDown(manager.dispose);

    expect(manager.allIds, containsAll(['kw', 'tx', 'wy', 'kg']));
    expect(manager.allIds, isNot(contains('mg')));
    expect(manager.get('kg'), isNotNull);
    expect(manager.get('mg'), isNull);
  });
}
