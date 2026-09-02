import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('card morph scales source UI with the expanding rect', () {
    final source = File('lib/core/card_expand.dart').readAsStringSync();

    // 窗口仍从源卡片矩形 lerp 到全屏：四边各自长到屏幕边。
    expect(source, contains('Rect.lerp(sourceRect, targetRect'));

    // 卡片界面元素必须跟着窗口一起放大缩小，不能钉死原尺寸只做裁剪。
    expect(source, contains('scaleX: currentRect.width / sourceRect.width'));
    expect(source, contains('scaleY: currentRect.height / sourceRect.height'));
    expect(source, contains('scaleX: currentRect.width / targetRect.width'));
    expect(source, contains('scaleY: currentRect.height / targetRect.height'));
    expect(source, isNot(contains('left: sourceRect.left - currentRect.left')));

    // 有卡片矩形时优先走 morph，不能被整页飞入/中心缩放盖掉。
    final expandingIdx = source.indexOf('if (expanding)');
    final swipeIdx = source.indexOf('if (fullWidthSwipe)');
    expect(expandingIdx, greaterThan(0));
    expect(swipeIdx, greaterThan(expandingIdx));
  });
}
