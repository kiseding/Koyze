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
    // 内容相对窗口居中：收起时上下一起裁，而不是顶对齐从下往上收。
    expect(source, isNot(contains('alignment: Alignment.topLeft')));
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

    // 每条路由自己的关闭会话：NAS 设置叠在乐库上时，不能共用全局
    // cardDismissProgress，否则返回设置会把底下的乐库收成空层。
    expect(source, contains('class _CardDismissSession'));
    expect(source, contains('_CardDismissScope.maybeOf'));
    expect(
      source,
      contains('getInheritedWidgetOfExactType<_CardDismissScope>()'),
    );

    // go_router 重跑 pageBuilder 时必须按 Page.key 记住第一次的源矩形，
    // 否则从设置页返回后乐库变成不透明页，右滑和卡片 morph 一起丢。
    expect(source, contains('_expandRectByPage'));
    expect(source, contains('_rememberExpandRect'));
    expect(source, contains('_forgetExpandOrigin'));
  });
}
