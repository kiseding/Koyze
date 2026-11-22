/// 鸿蒙上的原生日志通道。
///
/// Dart 的 `print` / `debugPrint` 最终写进程 stdout，而 HAP 进程的 stdout
/// 没有接收方：鸿蒙只认 hilog。引擎自己的 `FML_LOG` 走
/// `XComFlutterOHOS_Native` 这个 tag，Dart 侧没有对应入口，所以平台相关的
/// 诊断信息在 `hilog` 里完全空白 —— 排查「引擎起不来」这类问题时等于闭眼。
///
/// 这里直接调 NDK 的 `OH_LOG_Print`，把 Dart 侧的诊断落到 hilog。非鸿蒙
/// 平台上它是空操作，调用方不需要判断平台。
///
/// 用 `hdc shell hilog | grep <tag>` 就能看到。
///
/// **为什么是条件导入而不是直接写实现**：本文件被 `audio_handler.dart`
/// 引用，而后者在 Web 编译图里可达。`dart:ffi` 一旦被 dart2js 看见就会
/// 整条构建失败（`test/build_configuration_test.dart` 钉着这条边界），
/// 所以 Web 侧走 [ohos_hilog_web.dart] 的空实现。
library;

import 'ohos_hilog_web.dart'
    if (dart.library.io) 'ohos_hilog_native.dart' as impl;

/// 写一条 hilog。Web 上是空操作，其他平台转给原生实现。
void ohosLog(String tag, String message, {bool error = false}) =>
    impl.ohosLog(tag, message, error: error);
