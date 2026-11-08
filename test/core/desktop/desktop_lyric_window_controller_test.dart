// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/desktop/desktop_lyric_window_channel.dart';
import 'package:koyze/core/desktop/desktop_lyric_window_controller.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/lyric/domain/lyric.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeChannel implements DesktopLyricWindowChannel {
  final List<({String method, Object? arguments})> calls = [];
  DesktopLyricWindowEventHandler? handler;

  @override
  Future<void> invoke(String method, [Object? arguments]) async {
    calls.add((method: method, arguments: arguments));
  }

  @override
  void setEventHandler(DesktopLyricWindowEventHandler? handler) {
    this.handler = handler;
  }

  List<Object?> argumentsOf(String method) => calls
      .where((call) => call.method == method)
      .map((call) => call.arguments)
      .toList();

  int countOf(String method) =>
      calls.where((call) => call.method == method).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late StorageService storage;
  late _FakeChannel channel;
  late Lyrics lyrics;
  late Duration position;
  late List<bool> enabledChanges;
  late List<int> fontSizeChanges;
  late DesktopLyricWindowController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    storage = StorageService.forTesting(preferences);
    channel = _FakeChannel();
    lyrics = const Lyrics(
      raw: '',
      lines: [
        LyricLine(time: Duration.zero, text: '第一句'),
        LyricLine(time: Duration(seconds: 5), text: '第二句'),
        LyricLine(time: Duration(seconds: 10), text: '第三句'),
      ],
    );
    position = Duration.zero;
    enabledChanges = [];
    fontSizeChanges = [];
    controller = DesktopLyricWindowController(
      channel: channel,
      storage: () async => storage,
      lyrics: () => lyrics,
      position: () => position,
      onEnabledChanged: (enabled) async {
        enabledChanges.add(enabled);
      },
      onFontSizeChanged: (fontSize) async {
        fontSizeChanges.add(fontSize);
      },
      refreshInterval: const Duration(days: 1),
    );
  });

  tearDown(() async {
    await controller.dispose();
  });

  test('启动恢复窗口位置并推送初始样式和歌词', () async {
    await preferences.setInt('desktop_lyric_x', 240);
    await preferences.setInt('desktop_lyric_y', 680);

    await controller.init(enabled: true, locked: true, fontSize: 34);

    expect(channel.argumentsOf('show').single, {'x': 240, 'y': 680});
    expect(channel.argumentsOf('setStyle').single, {
      'fontSize': 34,
      'opacity': 0.9,
      'locked': true,
    });
    expect(channel.argumentsOf('update').single, {
      'current': '第一句',
      'next': '第二句',
    });
  });

  test('异步恢复位置期间的启用变更按队列顺序处理', () async {
    final storageReady = Completer<StorageService>();
    controller = DesktopLyricWindowController(
      channel: channel,
      storage: () => storageReady.future,
      lyrics: () => lyrics,
      position: () => position,
      onEnabledChanged: (enabled) async {
        enabledChanges.add(enabled);
      },
      onFontSizeChanged: (fontSize) async {
        fontSizeChanges.add(fontSize);
      },
      refreshInterval: const Duration(days: 1),
    );
    final initialized = controller.init(
      enabled: true,
      locked: false,
      fontSize: 28,
    );
    final disabled = controller.setEnabled(false);

    await preferences.setInt('desktop_lyric_x', 150);
    await preferences.setInt('desktop_lyric_y', 620);
    storageReady.complete(storage);
    await initialized;
    await disabled;

    expect(channel.argumentsOf('show').single, {'x': 150, 'y': 620});
    expect(channel.countOf('hide'), 1);
  });

  test('样式设置会钳制字号并抑制重复原生调用', () async {
    await controller.init(enabled: true, locked: false, fontSize: 28);

    await controller.updateStyle(locked: true, fontSize: 90);
    await controller.updateStyle(locked: true, fontSize: 90);

    expect(channel.argumentsOf('setStyle').length, 2);
    expect(channel.argumentsOf('setStyle').last, {
      'fontSize': 72,
      'opacity': 0.9,
      'locked': true,
    });
  });

  test('只在当前句或下一句变化时推送歌词', () async {
    await controller.init(enabled: true, locked: false, fontSize: 28);
    await controller.refresh();
    expect(channel.countOf('update'), 1);

    position = const Duration(seconds: 5);
    await controller.refresh();
    expect(channel.argumentsOf('update').last, {
      'current': '第二句',
      'next': '第三句',
    });
    expect(channel.countOf('update'), 2);
  });

  test('禁用时隐藏并停止推送，重开时重新应用样式', () async {
    await controller.init(enabled: true, locked: true, fontSize: 36);
    await controller.setEnabled(false);
    final updates = channel.countOf('update');

    position = const Duration(seconds: 5);
    await controller.refresh();
    await controller.setEnabled(true);

    expect(channel.countOf('hide'), 1);
    expect(channel.countOf('update'), updates + 1);
    expect(channel.argumentsOf('setStyle').length, 2);
    expect((channel.argumentsOf('setStyle').last as Map)['fontSize'], 36);
    expect((channel.argumentsOf('setStyle').last as Map)['locked'], isTrue);
  });

  test('位置事件持久化，字号事件限制范围并回写设置', () async {
    await controller.init(enabled: true, locked: false, fontSize: 28);

    channel.handler!('position', {'x': 512, 'y': 384});
    channel.handler!('style', {'fontSize': 200});
    await pumpEventQueue();

    expect(preferences.getInt('desktop_lyric_x'), 512);
    expect(preferences.getInt('desktop_lyric_y'), 384);
    expect(fontSizeChanges, [72]);
  });

  test('原生关闭事件通知设置层关闭歌词窗', () async {
    await controller.init(enabled: true, locked: false, fontSize: 28);

    channel.handler!('closed', const {});
    await pumpEventQueue();

    expect(enabledChanges, [false]);
  });

  test('dispose 注销事件处理器、隐藏窗口并忽略迟到事件', () async {
    await controller.init(enabled: true, locked: false, fontSize: 28);
    final lateHandler = channel.handler!;
    await controller.dispose();
    lateHandler('closed', const {});

    expect(channel.handler, isNull);
    expect(channel.countOf('hide'), 1);
    expect(enabledChanges, isEmpty);
  });
}
