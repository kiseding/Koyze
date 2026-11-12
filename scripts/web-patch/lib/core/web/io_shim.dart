// Web 构建专用：由 build-web.sh 在临时副本里把 `import 'dart:io'` 全部替换成本文件。
//
// 技巧：dart2js 自带 dart:io 的类型 stub（编译期所有类型都在，运行时才抛错），
// 我们保留它的全部类型，只把 Platform 换成不抛异常的实现。
// 这样 48 个引用 dart:io 的文件一行逻辑都不用改，原生平台也不受影响
// （本文件只在 Web 构建副本里出现）。

export 'dart:io' hide Platform;
export 'platform_web.dart' show Platform;
