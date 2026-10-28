import 'dart:convert';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/home/presentation/home_quick_provider.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

void main() {
  test('每张快捷卡都有本地化标题，不会在首页直接显示 id', () {
    // quickTitle / quickSubtitle 是按 id 查表的，表里没有的 id 会原样返回 id。
    // 真实事故：新增 'ai' 卡时只加了 HomeQuickFeature，首页上显示成小写
    // 「ai」配「ai」副标题——构建、analyze、既有测试全都看不出来。
    for (final locale in const [Locale('zh'), Locale('en')]) {
      final s = S(lookupAppLocalizations(locale), locale);
      for (final feature in homeQuickFeatures) {
        expect(
          s.quickTitle(feature.id),
          isNot(feature.id),
          reason: '${locale.languageCode}: 快捷卡 ${feature.id} 没有标题映射',
        );
        expect(
          s.quickSubtitle(feature.id),
          isNot(feature.id),
          reason: '${locale.languageCode}: 快捷卡 ${feature.id} 没有副标题映射',
        );
        expect(s.quickTitle(feature.id).trim(), isNotEmpty);
        expect(s.quickSubtitle(feature.id).trim(), isNotEmpty);
      }
    }
  });

  test('reorder keeps every feature present exactly once', () {
    final notifier = HomeQuickSettingsNotifier();
    final initial = notifier.value.order;
    expect(initial.length, homeQuickFeatures.length);

    // 模拟 onReorderItem：把第一项移到末尾（newIndex 已按移除后修正）。
    notifier.reorder(0, initial.length - 1);

    final reordered = notifier.value.order;
    expect(reordered.length, homeQuickFeatures.length);
    expect(reordered.toSet().length, homeQuickFeatures.length);
    expect(reordered.first, initial[1]);
    expect(reordered.last, initial[0]);
  });

  test('reorder to adjacent index swaps without dropping items', () {
    final notifier = HomeQuickSettingsNotifier();
    final initial = [...notifier.value.order];

    notifier.reorder(1, 0);

    final reordered = notifier.value.order;
    expect(reordered.length, initial.length);
    expect(reordered.toSet().length, initial.length);
    expect(reordered[0], initial[1]);
    expect(reordered[1], initial[0]);
  });

  test('setEnabled never touches order', () {
    final notifier = HomeQuickSettingsNotifier();
    final orderBefore = [...notifier.value.order];

    notifier.setEnabled('stats', false);
    final disabledCount = notifier.value.enabled.length;
    notifier.setEnabled('stats', true);

    expect(notifier.value.order, orderBefore);
    expect(notifier.value.enabled.length, disabledCount + 1);
  });

  test('self-hosted library is on by default and can be turned off', () {
    final feature = homeQuickFeatures.singleWhere(
      (item) => item.id == 'subsonic',
    );
    expect(feature.title, 'NAS 乐库');
    expect(feature.route, '/subsonic');
    expect(feature.enabledByDefault, isTrue);

    final notifier = HomeQuickSettingsNotifier();
    expect(notifier.value.enabled, contains('subsonic'));
    notifier.setEnabled('subsonic', false);
    expect(notifier.value.enabled, isNot(contains('subsonic')));
  });

  test('AI assistant takes cloud sync slot and cloud sync stays available', () {
    final ai = homeQuickFeatures.singleWhere((item) => item.id == 'ai');
    expect(ai.title, 'AI 助手');
    expect(ai.route, '/ai-assistant');
    expect(ai.enabledByDefault, isTrue);

    // 云同步只是默认不显示，快捷功能面板里仍然能把它打开。
    final sync = homeQuickFeatures.singleWhere((item) => item.id == 'sync');
    expect(sync.title, '云同步');
    expect(sync.route, '/sync');
    expect(sync.enabledByDefault, isFalse);

    final notifier = HomeQuickSettingsNotifier();
    expect(notifier.value.enabled, contains('ai'));
    expect(notifier.value.enabled, isNot(contains('sync')));
    expect(notifier.value.order.first, 'ai');

    notifier.setEnabled('sync', true);
    expect(notifier.value.enabled, contains('sync'));
  });

  test('v1 config migrates once: sync out of the visible set, AI in', () async {
    SharedPreferences.setMockInitialValues({
      'home_quick_features_v1': jsonEncode({
        'order': ['recommend', 'local', 'sync'],
        'enabled': ['recommend', 'local', 'sync'],
      }),
    });
    final storage = StorageService.forTesting(
      await SharedPreferences.getInstance(),
    );
    final notifier = HomeQuickSettingsNotifier(storage: () async => storage);

    await pumpEventQueue();

    expect(notifier.value.enabled, contains('ai'));
    expect(notifier.value.enabled, isNot(contains('sync')));
    expect(notifier.value.order.first, 'ai');
    // 用户自己排过的顺序原样保留在后面。
    expect(notifier.value.order.take(4), ['ai', 'recommend', 'local', 'sync']);
  });
}
