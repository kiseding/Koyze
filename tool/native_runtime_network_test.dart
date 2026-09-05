import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('source runtime does not register unrestricted network primitives', () {
    final runtime = getJavascriptRuntime(xhr: false);
    try {
      expect(
        runtime.evaluate('typeof XMLHttpRequest').stringResult,
        'undefined',
      );
      expect(runtime.evaluate('typeof fetch').stringResult, 'undefined');
      final channels = JavascriptRuntime
          .channelFunctionsRegistered[runtime.getEngineInstanceId()];
      expect(channels?.containsKey('SendNative'), isFalse);
    } finally {
      runtime.dispose();
    }
  });
}
