// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/persisted_setting.dart';
import '../../../core/storage/storage_service.dart';
import '../../settings/presentation/settings_provider.dart';
import '../domain/car_connection.dart';

/// 车机模式的三种状态。
enum CarModePreference {
  /// 跟随 HiCar 连接状态自动切换（默认）。
  auto,

  /// 一直使用宽屏车机布局，方便在手机 / 平板上预览。
  always,

  /// 从来不进车机模式。
  off;

  static const String storageKey = 'car_mode_preference';

  static CarModePreference parse(String? raw) {
    for (final value in CarModePreference.values) {
      if (value.name == raw) return value;
    }
    return CarModePreference.auto;
  }
}

/// 连接状态从哪来。测试里覆盖成假实现即可脱离平台通道。
final carLinkProvider = Provider<CarLink>((ref) {
  if (kIsWeb) return const DetachedCarLink();
  return PlatformCarLink();
});

/// 当前连接状态。初值取 [CarConnection.unsupported]：在拿到第一条真实事件之前
/// 不主动切换布局，避免冷启动时先闪一下车机界面。
final carConnectionProvider =
    NotifierProvider<CarConnectionNotifier, CarConnection>(
      CarConnectionNotifier.new,
    );

class CarConnectionNotifier extends Notifier<CarConnection> {
  StreamSubscription<CarConnection>? _subscription;

  @override
  CarConnection build() {
    final link = ref.watch(carLinkProvider);
    ref.onDispose(() => _subscription?.cancel());
    _subscription = link.status.listen(
      (connection) => state = connection,
      // 通道本身出错时按「不支持」处理，不能让它把界面顶成错误态。
      onError: (Object _) => state = CarConnection.unsupported,
    );
    return CarConnection.unsupported;
  }
}

final carModePreferenceProvider =
    NotifierProvider<CarModePreferenceNotifier, CarModePreference>(
      CarModePreferenceNotifier.new,
    );

class CarModePreferenceNotifier extends Notifier<CarModePreference> {
  CarModePreferenceNotifier({StorageLoader? storage})
    : _setting = PersistedSetting<CarModePreference>(
        initialValue: CarModePreference.auto,
        storage: storage,
      ) {
    // 与设置页的 notifier 一致：直连构造也能读到已存的值，不必先挂到 container。
    _startLoad();
  }

  final PersistedSetting<CarModePreference> _setting;

  /// 直连构造（测试）时读这里，不依赖 container。
  CarModePreference get value => _setting.value;

  static CarModePreference? _read(StorageService storage) =>
      CarModePreference.parse(storage.getString(CarModePreference.storageKey));

  void _startLoad() {
    unawaited(_setting.load(_read).then((_) => _mirror()));
  }

  /// `state` 在 `build()` 之前、以及被销毁之后都会抛，直接构造的测试和晚到的
  /// 异步读都会撞上，所以这里吞掉。
  void _mirror() {
    try {
      state = _setting.value;
    } catch (_) {
      // 未挂到 ProviderContainer 上。
    }
  }

  @override
  CarModePreference build() {
    _startLoad();
    return _setting.value;
  }

  Future<void> set(CarModePreference preference) async {
    final owns = await _setting.set(
      preference,
      (storage) => storage.setString(
        CarModePreference.storageKey,
        preference.name,
      ),
    );
    if (!owns) return;
    _mirror();
  }
}

/// 是否处于车机模式。
final carModeActiveProvider = Provider<bool>((ref) {
  return switch (ref.watch(carModePreferenceProvider)) {
    CarModePreference.off => false,
    CarModePreference.always => true,
    CarModePreference.auto => ref.watch(carConnectionProvider).isConnected,
  };
});

/// 是否使用横屏 / 侧栏那套宽屏外壳。
///
/// 用户手动打开的「强制横屏」和车机模式走同一条路径：车机上的虚拟屏本来就是
/// 横的，界面能直接复用，不需要另做一套。
final landscapeShellProvider = Provider<bool>((ref) {
  return ref.watch(forceLandscapeProvider) || ref.watch(carModeActiveProvider);
});
