import 'dart:ffi';
import 'dart:io';
import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe packaged QuickJS timeout using a bounded computation', () {
    if (Platform.isWindows) {
      final library = DynamicLibrary.open('quickjs_c_bridge.dll');
      for (final name in [
        'JS_SetInterruptHandler',
        'JS_SetMemoryLimit',
        'jsSetInterruptHandler',
        'jsSetMemoryLimit',
      ]) {
        // ignore: avoid_print
        print('$name exported=${library.providesSymbol(name)}');
      }
    }
    final runtime = QuickJsRuntime2(timeout: 1);
    try {
      final watch = Stopwatch()..start();
      final result = runtime.evaluate(
        'var end = Date.now() + 250; while (Date.now() < end) {} "completed";',
      );
      // A finite probe prevents an unsupported timeout from hanging the host.
      // This diagnostic intentionally reports evidence without treating the
      // presence of the constructor argument as a verified deadline.
      // ignore: avoid_print
      print(
        'deadlineProbe: elapsed=${watch.elapsedMilliseconds}ms '
        'error=${result.isError} result=${result.stringResult}',
      );
    } finally {
      runtime.dispose();
    }
  });
}
