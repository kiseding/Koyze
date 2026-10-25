import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koyze/core/widgets/auto_text_input.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows URL fields use a text keyboard so colon is not semicolon', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.text);
    expect(
      desktopSafeKeyboardType(TextInputType.emailAddress),
      TextInputType.text,
    );
    expect(desktopSafeKeyboardType(TextInputType.text), TextInputType.text);
  });

  test('mobile URL fields keep the URL keyboard', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.url);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(desktopSafeKeyboardType(TextInputType.url), TextInputType.url);
  });

  test('macOS 与 Linux 也走桌面安全键盘', () {
    // 桌面端统一处理：这两个平台同样存在 URL 键盘把 : 打成 ; 的问题。
    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(
        desktopSafeKeyboardType(TextInputType.url),
        TextInputType.text,
        reason: '$platform 的 URL 输入框应回退为普通文本键盘',
      );
    }
  });
}
