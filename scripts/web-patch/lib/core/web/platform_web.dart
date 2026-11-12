// Web 下的 dart:io.Platform 替身。
// dart2js 的 Platform._operatingSystem 会抛 UnsupportedError，
// 而启动链里有大量 `Platform.isWindows / isAndroid` 之类的判断。
// 浏览器里这些平台标志一律为 false，路径分隔符用 '/'，目录相关操作
// 由调用方自己的 kIsWeb 分支或 shim 的 UnsupportedError 兜住。

abstract final class Platform {
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isFuchsia = false;

  static const String operatingSystem = 'web';
  static const String operatingSystemVersion = '';
  static const String pathSeparator = '/';
  static const String resolvedExecutable = '';
  static const String executable = '';
  static const List<String> executableArguments = <String>[];
  static const String localeName = 'zh_CN';
  static const String localHostname = 'localhost';
  static const int numberOfProcessors = 1;
  static const String packageConfig = '';
  static const String version = '3.12.2 (web)';

  static const Map<String, String> environment = <String, String>{};

  static Uri get script => Uri.base;
}
