import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/home_quick_provider.dart';

void main() {
  test('reorder keeps every feature present exactly once', () {
    final notifier = HomeQuickSettingsNotifier();
    final initial = notifier.state.order;
    expect(initial.length, homeQuickFeatures.length);

    // 模拟 onReorderItem：把第一项移到末尾（newIndex 已按移除后修正）。
    notifier.reorder(0, initial.length - 1);

    final reordered = notifier.state.order;
    expect(reordered.length, homeQuickFeatures.length);
    expect(reordered.toSet().length, homeQuickFeatures.length);
    expect(reordered.first, initial[1]);
    expect(reordered.last, initial[0]);
  });

  test('reorder to adjacent index swaps without dropping items', () {
    final notifier = HomeQuickSettingsNotifier();
    final initial = [...notifier.state.order];

    notifier.reorder(1, 0);

    final reordered = notifier.state.order;
    expect(reordered.length, initial.length);
    expect(reordered.toSet().length, initial.length);
    expect(reordered[0], initial[1]);
    expect(reordered[1], initial[0]);
  });

  test('setEnabled never touches order', () {
    final notifier = HomeQuickSettingsNotifier();
    final orderBefore = [...notifier.state.order];

    notifier.setEnabled('stats', false);
    final disabledCount = notifier.state.enabled.length;
    notifier.setEnabled('stats', true);

    expect(notifier.state.order, orderBefore);
    expect(notifier.state.enabled.length, disabledCount + 1);
  });

  test('self-hosted library is on by default and can be turned off', () {
    final feature = homeQuickFeatures.singleWhere(
      (item) => item.id == 'subsonic',
    );
    expect(feature.title, 'NAS 乐库');
    expect(feature.route, '/subsonic');
    expect(feature.enabledByDefault, isTrue);

    final notifier = HomeQuickSettingsNotifier();
    expect(notifier.state.enabled, contains('subsonic'));
    notifier.setEnabled('subsonic', false);
    expect(notifier.state.enabled, isNot(contains('subsonic')));
  });

  test('cloud sync is on by default and can be turned off', () {
    final feature = homeQuickFeatures.singleWhere((item) => item.id == 'sync');
    expect(feature.title, '云同步');
    expect(feature.route, '/sync');
    expect(feature.enabledByDefault, isTrue);

    final notifier = HomeQuickSettingsNotifier();
    expect(notifier.state.enabled, contains('sync'));
    notifier.setEnabled('sync', false);
    expect(notifier.state.enabled, isNot(contains('sync')));
  });
}
