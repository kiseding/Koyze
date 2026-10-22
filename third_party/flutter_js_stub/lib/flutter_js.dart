library flutter_js;

/// HarmonyOS 桩实现：flutter_js 没有鸿蒙原生移植（QuickJS/JSC 均为 C++ 实现），
/// 这里提供与上游一致的最小 API 面，使工程能编译、启动；
/// 调用 getJavascriptRuntime 时抛出 UnsupportedError，由调用方 try/catch 优雅降级。
class JsEvalResult {
  JsEvalResult({
    required this.isError,
    this.stringResult = '',
    this.jsonResult,
  });

  final bool isError;
  final String stringResult;
  final dynamic jsonResult;
}

class JavascriptRuntime {
  void onMessage(String channelName, dynamic Function(dynamic args) function) {
    // 无原生通道，注册的 handler 永远不会被触发。
  }

  JsEvalResult evaluate(String code) {
    return JsEvalResult(
      isError: true,
      stringResult: 'HarmonyOS 版本暂不支持自定义音源（flutter_js 无鸿蒙移植）',
    );
  }

  void dispose() {}

  void executePendingJob() {}
}

JavascriptRuntime getJavascriptRuntime() {
  throw UnsupportedError('HarmonyOS 版本暂不支持自定义音源（flutter_js 无鸿蒙移植）');
}
