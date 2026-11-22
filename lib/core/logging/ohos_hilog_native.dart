import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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
typedef _OhLogPrintNative = Int32 Function(
  Int32 type,
  Int32 level,
  Uint32 domain,
  Pointer<Utf8> tag,
  Pointer<Utf8> format,
  Pointer<Utf8> message,
);
typedef _OhLogPrintDart = int Function(
  int type,
  int level,
  int domain,
  Pointer<Utf8> tag,
  Pointer<Utf8> format,
  Pointer<Utf8> message,
);

/// `LogType.LOG_APP`。
const int _logApp = 0;
const int _levelInfo = 4;
const int _levelError = 6;

/// `OH_LOG_Print` 是变参函数，`message` 通过 `%{public}s` 传入，这样内容里
/// 出现 `%` 也不会被当成格式符。
const String _format = '%{public}s';

_OhLogPrintDart? _logPrint;
bool _resolved = false;

bool get _isOhos => Platform.operatingSystem == 'ohos';

_OhLogPrintDart? _resolve() {
  if (_resolved) return _logPrint;
  _resolved = true;
  if (!_isOhos) return null;
  try {
    _logPrint = DynamicLibrary.open('libhilog_ndk.z.so')
        .lookupFunction<_OhLogPrintNative, _OhLogPrintDart>('OH_LOG_Print');
  } catch (_) {
    // 库被裁掉或 linker namespace 不允许时静默降级：日志不该让业务崩。
    _logPrint = null;
  }
  return _logPrint;
}

/// 写一条 hilog。非鸿蒙平台直接返回。
void ohosLog(String tag, String message, {bool error = false}) {
  final print = _resolve();
  if (print == null) return;
  try {
    final tagPtr = tag.toNativeUtf8();
    final formatPtr = _format.toNativeUtf8();
    final messagePtr = message.toNativeUtf8();
    try {
      print(
        _logApp,
        error ? _levelError : _levelInfo,
        0,
        tagPtr,
        formatPtr,
        messagePtr,
      );
    } finally {
      malloc.free(tagPtr);
      malloc.free(formatPtr);
      malloc.free(messagePtr);
    }
  } catch (_) {
    // 同上：日志失败不影响调用方。
  }
}
