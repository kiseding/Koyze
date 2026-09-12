import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:koyze/features/home/presentation/home_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';

/// 首页内容（搜索条 + 收藏卡片 + 快捷功能网格，含上下内边距）在竖屏单列宽度下的
/// 自然高度。桌面端默认窗口高度必须容得下「该高度 + 底部 chrome」，否则首页一打开
/// 就要滚动，观感上就是个放不下的窗口。
///
/// 这个值是在测试字体下量出来的；真机字体行高略有差异（通常多几 px），
/// 由各平台的 breathingRoom 吸收。改动首页布局后重新跑本测试即可拿到新值。
const int homeContentMinHeight = 549;

/// 底部 chrome 在桌面端占用的高度。来自
/// `lib/features/home/presentation/main_scaffold.dart`：
/// navHeight 38（36 基准 + bottomSpacing 2）+ 容器内边距 16 + bottomClearance 11
/// + miniGap 11 + miniHeight 78 = 154。桌面端没有系统底栏 inset，取的是这条分支。
const int desktopChromeHeight = 154;

/// 各平台 runner 里的默认窗口高度常数 -> 定义它的源文件与变量名。
const nativeHeights = <String, (String, String)>{
  'Windows': ('windows/runner/main.cpp', 'kHomeContentHeight'),
  'Linux': ('linux/runner/my_application.cc', 'kHomeContentHeight'),
  'macOS': ('macos/Runner/MainFlutterWindow.swift', 'homeContentHeight'),
};

int _intConst(String source, String name) {
  final match = RegExp('$name\\s*(?::\\s*CGFloat)?\\s*=\\s*(\\d+)')
      .firstMatch(source);
  expect(match, isNotNull, reason: '找不到 $name 的定义');
  return int.parse(match!.group(1)!);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('首页在竖屏单列宽度下的内容高度', (tester) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playlistsProvider.overrideWithValue(const [])],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final scrollView = find.byType(SingleChildScrollView);
    final size = tester.getSize(
      find
          .descendant(of: scrollView, matching: find.byType(Column))
          .first,
    );
    final scroll = tester.widget<SingleChildScrollView>(scrollView);
    final padding = scroll.padding! as EdgeInsets;
    final contentHeight = size.height + padding.top + padding.bottom;

    expect(
      contentHeight,
      homeContentMinHeight,
      reason: '首页内容高度变了，同步更新 homeContentMinHeight 并核对各平台窗口高度',
    );
  });

  test('桌面端默认窗口高度容得下首页全部内容', () {
    final required = homeContentMinHeight + desktopChromeHeight;

    for (final entry in nativeHeights.entries) {
      final (path, name) = entry.value;
      final height = _intConst(File(path).readAsStringSync(), name);
      expect(
        height,
        greaterThanOrEqualTo(required),
        reason: '${entry.key} 的 $name=$height 放不下首页（需要 $required）',
      );
    }
  });

  test('三端默认窗口高度保持一致', () {
    final heights = <String, int>{
      for (final entry in nativeHeights.entries)
        entry.key: _intConst(
          File(entry.value.$1).readAsStringSync(),
          entry.value.$2,
        ),
    };
    expect(heights.values.toSet(), hasLength(1), reason: '$heights');
  });

  test('默认窗口高度留有呼吸余量', () {
    for (final entry in nativeHeights.entries) {
      final source = File(entry.value.$1).readAsStringSync();
      final breathing = _intConst(
        source,
        entry.key == 'macOS' ? 'breathingRoom' : 'kBreathingRoom',
      );
      expect(breathing, greaterThan(0), reason: entry.key);
    }
  });
}
