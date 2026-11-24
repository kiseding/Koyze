import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/platform/app_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('读取剪贴板文本', () async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'https://example.com/source.js'};
      }
      return null;
    });

    final result = await readClipboard();
    expect(result.status, ClipboardReadStatus.text);
    expect(result.text, 'https://example.com/source.js');
  });

  test('剪贴板没有文本时返回 empty', () async {
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': ''};
      }
      return null;
    });

    final result = await readClipboard();
    expect(result.status, ClipboardReadStatus.empty);
    expect(result.text, isNull);
  });

  test('平台没有实现时按空处理，不抛异常', () async {
    // 鸿蒙引擎就是这种情况：OptionalMethodChannel 对未知方法回 null。
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });

    final result = await readClipboard();
    expect(result.status, ClipboardReadStatus.empty);
  });

  test('写入把文本交给系统通道', () async {
    String? written;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        written = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });

    await setClipboardText('复制的内容');
    expect(written, '复制的内容');
  });
}
