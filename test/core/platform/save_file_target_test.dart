// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/platform/save_file_target.dart';

/// 这两个判据是「同一个平台的同一件事」的两个侧面，必须始终相反。
///
/// 曾经的真实 bug：三处导出写的是 `Platform.isIOS || Platform.isAndroid`，
/// 鸿蒙不匹配任何一支，于是既不传字节（file_picker 的鸿蒙通道直接抛
/// `ArgumentError`），又拿返回的 `file://docs/...` 去 `dart:io` 写
/// （报 13900002）。导出在鸿蒙上 100% 失败，而且报错点在 `File(...)`，
/// 看起来像路径问题。
void main() {
  test('两个判据必须互补，不能同时为真或同时为假', () {
    // 同时为真：既让原生写、又自己写一遍，内容会被覆盖或写失败。
    // 同时为假：既不传字节、也不自己写，结果是一个空文件。
    expect(saveFileNeedsBytes, isNot(callerWritesSavedFile));
  });

  test('测试宿主是桌面，走「只给路径、调用方自己写」这一支', () {
    // 测试跑在 Windows / Linux / macOS 上，三者都由调用方自己写文件。
    // 这条同时保证新加的平台判断不会把桌面误判成移动端。
    expect(saveFileNeedsBytes, isFalse);
    expect(callerWritesSavedFile, isTrue);
  });
}
