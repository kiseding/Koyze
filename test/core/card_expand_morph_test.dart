import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card morph expands the clip rect instead of uniformly scaling the page', () {
    final source = File('lib/core/card_expand.dart').readAsStringSync();

    // 窗口必须从源卡片矩形 lerp 到全屏：四边各自长到屏幕边，
    // 而不是把整页按一个比例均匀放大。
    expect(source, contains('Rect.lerp(sourceRect, targetRect'));
    expect(source, isNot(contains('scale: sizeW / targetRect.width')));
    expect(source, isNot(contains('scale: currentRect.width / sourceRect.width')));

    // 有卡片矩形时优先走 morph，不能被整页飞入/中心缩放盖掉。
    final expandingIdx = source.indexOf('if (expanding)');
    final swipeIdx = source.indexOf('if (fullWidthSwipe)');
    expect(expandingIdx, greaterThan(0));
    expect(swipeIdx, greaterThan(expandingIdx));
  });
}
