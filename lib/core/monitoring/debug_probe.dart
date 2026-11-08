// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:io';

import 'package:flutter/foundation.dart';

/// 性能探针（debug probe）总开关。
///
/// 探针本身很便宜，但它不是零成本：帧回调每秒被调用几十次，汇总定时器每 2 秒
/// 排序一次样本。把「要不要接探针」做成显式开关，可以保证正常用户完全不付这笔
/// 开销，同时给排查问题留出三条入口：
///
/// 1. 编译期：`flutter build windows --dart-define=KOYZE_PROBE=true`
/// 2. 运行期（桌面端）：环境变量 `KOYZE_PROBE=1`，免重新打包
/// 3. 界面：设置里的实时诊断日志，打开面板即开探针、关闭即停
///
/// 一、二两个入口都只决定「启动时默认值」，界面开关仍可在运行中覆盖它。
abstract final class DebugProbe {
  const DebugProbe._();

  /// 编译期与运行期共用的键名。
  static const String key = 'KOYZE_PROBE';

  /// 编译期开关。缺省为 false，因此正式构建默认不带探针。
  static const bool compiledIn = bool.fromEnvironment(key);

  static bool? _forced;
  static bool _environmentResolved = false;
  static bool _environment = false;

  /// 当前是否启用探针。
  static bool get enabled {
    final forced = _forced;
    if (forced != null) return forced;
    return staticallyEnabled;
  }

  /// 编译期 / 环境变量是否已经把探针钉死为开启。
  ///
  /// 诊断面板关闭时要据此判断「能不能停探针」：诊断包是带着探针编译的，
  /// 关面板不该把日志一并断掉。
  static bool get staticallyEnabled {
    if (!_environmentResolved) {
      _environmentResolved = true;
      _environment = _readEnvironment();
    }
    return _environment || compiledIn;
  }

  /// 运行期强制开关。传 null 表示恢复「编译期 + 环境变量」的默认判断。
  ///
  /// 诊断面板用它把探针打开，关闭面板时传 null 交还给默认值。
  static set forced(bool? value) => _forced = value;

  /// 探针来源，供日志一行说明「为什么现在是开着的」。
  static String describe() {
    if (_forced != null) return 'forced';
    if (_environment) return 'environment';
    if (compiledIn) return 'compile-time';
    return 'off';
  }

  /// 只在测试里重置缓存，避免环境变量读取结果跨用例串味。
  @visibleForTesting
  static void resetForTesting() {
    _forced = null;
    _environmentResolved = false;
    _environment = false;
  }

  static bool _readEnvironment() {
    if (kIsWeb) return false;
    try {
      final value = Platform.environment[key];
      if (value == null) return false;
      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes' ||
          normalized == 'on';
    } on Object {
      // 某些沙箱环境禁止读环境变量；探针缺失不影响任何功能。
      return false;
    }
  }
}
