// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/services.dart';

/// 手机与车机之间的连接状态。
///
/// 只有鸿蒙侧有 Car Kit，其余平台（以及鸿蒙的模拟器 / 平板 / 低版本系统）永远
/// 停在 [unsupported]：车机模式届时只能靠用户手动打开，不会自动切换。
enum CarConnection {
  /// 这台设备不具备 Car Kit 能力。
  unsupported,

  /// 具备能力，但当前没有连上车机。
  disconnected,

  /// 已连上 HiCar 认证车机或超级桌面。
  connected;

  bool get isConnected => this == CarConnection.connected;

  /// 解析鸿蒙侧发来的字符串。未知值一律当作不支持——宁可不动，也不要在
  /// 不认识的设备上自作聪明地切布局。
  static CarConnection parse(Object? raw) {
    return switch (raw) {
      'connected' => CarConnection.connected,
      'disconnected' => CarConnection.disconnected,
      _ => CarConnection.unsupported,
    };
  }
}

/// 连接状态的来源。
///
/// 抽成接口是为了让测试塞假实现：真实实现要碰 `EventChannel`，而单元测试里没有
/// 平台侧处理器，订阅永远不会收到值，测出来只会是「一直没连上」。
abstract class CarLink {
  /// 订阅即开始监听，取消订阅即注销。冷启动时先补一次当前状态再等变化。
  Stream<CarConnection> get status;
}

/// 走鸿蒙侧 `CarStatusBridge`（`EventChannel('koyze/car/status')`）。
class PlatformCarLink implements CarLink {
  PlatformCarLink({
    this.channel = const EventChannel(carStatusChannel),
  });

  /// 与 `ohos/entry/src/main/ets/entryability/CarStatusBridge.ets` 里的常量一致。
  static const String carStatusChannel = 'koyze/car/status';

  final EventChannel channel;

  @override
  Stream<CarConnection> get status async* {
    try {
      await for (final raw in channel.receiveBroadcastStream()) {
        yield CarConnection.parse(raw);
      }
    } on MissingPluginException {
      // 非鸿蒙平台根本没有这个通道。安静降级，不要把它当成错误抛给 UI。
      yield CarConnection.unsupported;
    } on PlatformException {
      yield CarConnection.unsupported;
    }
  }
}

/// 永远不连接的实现，给非鸿蒙平台和测试当默认值。
class DetachedCarLink implements CarLink {
  const DetachedCarLink([this._value = CarConnection.unsupported]);

  final CarConnection _value;

  @override
  Stream<CarConnection> get status => Stream<CarConnection>.value(_value);
}
