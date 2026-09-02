import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card morph scales source UI with the expanding rect', () {
    final source = File('lib/core/card_expand.dart').readAsStringSync();

    // 窗口仍从源卡片矩形 lerp 到全屏：四边各自长到屏幕边。
    expect(source, contains('Rect.lerp(sourceRect, targetRect'));

    // 宽度跟着窗口走；高度用同一比例，不能按窗高单独缩放把卡片 UI 压扁。
    expect(source, contains('scale: currentRect.width / sourceRect.width'));
    expect(source, contains('scale: currentRect.width / targetRect.width'));
    expect(
      source,
      isNot(contains('scaleY: currentRect.height / sourceRect.height')),
    );
    expect(
      source,
      isNot(contains('scaleY: currentRect.height / targetRect.height')),
    );
    expect(source, isNot(contains('BoxFit.fill')));
    expect(source, isNot(contains('left: sourceRect.left - currentRect.left')));

    // 有卡片矩形时优先走 morph，不能被整页飞入/中心缩放盖掉。
    final expandingIdx = source.indexOf('if (expanding)');
    final swipeIdx = source.indexOf('if (fullWidthSwipe)');
    expect(expandingIdx, greaterThan(0));
    expect(swipeIdx, greaterThan(expandingIdx));
  });
}
