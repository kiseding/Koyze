/// Web 侧的原生日志通道：空实现。
///
/// `ohos_hilog.dart` 原本直接 `import 'dart:ffi'`，而它被 `audio_handler.dart`
/// 引用——后者在 Web 编译图里可达（`lib/main_web.dart` 一路经播放器可达），
/// 于是 `package:ffi` 的 `external` 声明进了 dart2js，整条 Web 构建直接报
/// "Only JS interop members may be 'external'"。报错落在 pub-cache 里的第三方
/// 文件上，看不出是哪个本地改动引入的。
///
/// 这里只保留签名、不做任何事：浏览器里没有 hilog，`debugPrint` 走 console
/// 已经够用。签名必须与 native 分支完全一致，否则调用点会编译不过。
void ohosLog(String tag, String message, {bool error = false}) {}
