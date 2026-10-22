# Vendored: flutter_js (OpenHarmony port)

本目录是 [flutter_js](https://pub.dev/packages/flutter_js) 的 OpenHarmony 移植版，
来源 **`flutter_js_ohos` 0.6.8**（上游仓库 <https://github.com/yeliulee/flutter_js>，
`oh` 分支），包名改回 `flutter_js`，让业务代码继续使用
`package:flutter_js/flutter_js.dart`。

## 相对上游移植包的改动

- `pubspec.yaml`：`name: flutter_js`；只声明 ohos 平台；去掉 `http` / `sync_http` /
  `flutter_platform_utils` 依赖（本仓库用 http 1.x，和移植包的 http 0.13 冲突）。
- `getJavascriptRuntime()`：用 `Platform.operatingSystem == 'ohos'` 判断平台，
  不再走 `flutter_platform_utils`；不启用 fetch/XHR 扩展（Koyze 的
  `SourceRuntimePolyfill` 会在 JS 侧用 `lx.request` 兜底实现 fetch/XMLHttpRequest）。
- Dart 3 FFI 适配（0.6.8 是为 Dart 2 写的，直接编译会失败）：
  - 结构体 `external int? char;` → `external int char;`
  - `channelDispacher` 返回值去掉可空（与上游 flutter_js 0.8.7 的修法一致）
  - 删除未使用且不兼容的旧运行时 `quickjs_runtime.dart` / `qjs_typedefs.dart` /
    `utf8_null_terminated.dart`（`QuickJsRuntime2` 不依赖它们）
  - 删除 `quickjs-sync-server/`（依赖 sync_http，未使用）
- `ohos/` 模块名统一为 `flutter_js`（`oh-package.json5` / `module.json5`）。

## 原生库

- `ohos/libs/arm64-v8a/libquickjs_c_bridge.so`：移植包自带的 QuickJS C bridge
  （built with OpenHarmony API 12）。
- `ohos/libs/arm64-v8a/libc++_shared.so`：`libquickjs_c_bridge.so` 的 NEEDED 依赖。
  hvigor 只会把插件自己的 `.so` 打进 HAP，不会带 C++ 运行时，缺失时真机 dlopen
  报 `Error loading shared library libc++_shared.so (needed by libquickjs_c_bridge.so)`，
  表现为自定义音源初始化失败。该文件取自 DevEco Studio SDK
  `sdk/default/openharmony/native/llvm/lib/aarch64-linux-ohos/libc++_shared.so`。
