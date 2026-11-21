// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// `FilePicker.saveFile` 在各平台上的两种行为。
///
/// ## 为什么需要这个文件
///
/// `file_picker` 的保存通道分两类：
///
/// * **交给原生写**（Android / iOS / 鸿蒙）：调用方必须把字节一起传过去，
///   由原生侧落盘。漏传 `bytes` 会直接抛 `ArgumentError`。
/// * **只给路径**（Windows / macOS / Linux）：原生只弹选择框、返回路径，
///   文件内容要调用方自己写。
///
/// 代码里原本写的是 `Platform.isIOS || Platform.isAndroid`，鸿蒙不匹配其中
/// 任何一支，于是既不传字节、又拿返回的 URI 去 `dart:io` 写——鸿蒙上
/// 备份导出、歌词卡片导出、歌单导出全都失败，而且报错点在 `File(...)`，
/// 看起来像是路径问题。
///
/// 这里把判断收敛成一处，新增平台只改这里。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// 当前平台保存文件时，是否需要调用方提供字节。
///
/// 为 true 时**必须**把 `bytes` 传给 `FilePicker.saveFile`，否则抛异常。
bool get saveFileNeedsBytes {
  if (kIsWeb) return false;
  return Platform.isAndroid ||
      Platform.isIOS ||
      Platform.operatingSystem == 'ohos';
}

/// 拿到 `saveFile` 的返回值后，是否需要调用方自己把内容写进去。
///
/// 与 [saveFileNeedsBytes] **严格互补**：内容要么由原生侧写入，要么由调用
/// 方写入，不可能两边都写、也不可能两边都不写。
///
/// 为 true 时用 `File(savedPath).writeAsBytes(...)`；为 false 时内容已经
/// 由原生侧落盘，返回值只是个位置或 URI，**不能**再拿去用 `dart:io`
/// 打开——鸿蒙返回的是 `file://docs/...`，`File` 会把它当相对路径，写入
/// 时报 13900002。
bool get callerWritesSavedFile => !saveFileNeedsBytes;
