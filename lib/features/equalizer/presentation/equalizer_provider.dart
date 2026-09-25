import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/audio/audio_handler.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/domain/equalizer_settings.dart';

/// 均衡器设置的持久化键。
const String equalizerSettingsStorageKey = 'equalizer_settings_v1';

/// 均衡器桥。
///
/// iOS / macOS / Windows 上没有任何可用的实现，此时返回不支持的空实现，
/// 界面据此展示说明而不是一堆拖不动的滑块。
final equalizerBridgeProvider = Provider<EqualizerBridge>((ref) {
  final handler = _currentHandler();
  if (handler is LxAudioHandler) return handler.equalizer;
  return const UnsupportedEqualizerBridge();
});

/// 读取全局音频处理器；启动引导尚未完成时 `audioHandler` 还是未初始化的
/// late 变量，读取会抛错，这里按「没有处理器」处理。
AudioHandler? _currentHandler() {
  try {
    return audioHandler;
  } catch (_) {
    return null;
  }
}

@immutable
class EqualizerState {
  const EqualizerState({
    this.settings = const EqualizerSettings(),
    this.supported = false,
    this.layout,
    this.loading = true,
  });

  final EqualizerSettings settings;

  /// 当前平台是否有可用的均衡器实现。
  final bool supported;

  /// 设备真实频段布局；播放器还没激活过时为 null。
  final EqualizerBandLayout? layout;

  /// 是否还在读取持久化设置。
  final bool loading;

  /// 界面实际使用的布局：真实布局没拿到时先按兜底布局展示，
  /// 这样用户不必先播放一首歌才能看到均衡器。
  EqualizerBandLayout get effectiveLayout => layout ?? kFallbackEqualizerLayout;

  /// 设备真实布局是否已就绪。
  bool get layoutReady => layout != null;

  /// 滑块是否可拖动。
  bool get interactive => supported && settings.enabled;

  /// 当前要展示 / 施加的频段增益。
  List<double> get gains => settings.gainsFor(effectiveLayout);

  EqualizerState copyWith({
    EqualizerSettings? settings,
    bool? supported,
    EqualizerBandLayout? layout,
    bool? loading,
  }) => EqualizerState(
    settings: settings ?? this.settings,
    supported: supported ?? this.supported,
    layout: layout ?? this.layout,
    loading: loading ?? this.loading,
  );
}

/// 设置页副标题。
String equalizerSubtitle(EqualizerState state, {Locale? locale}) {
  final en = locale?.languageCode == 'en';
  if (!state.supported) {
    return en ? 'Not supported on this platform' : '当前平台不支持';
  }
  if (!state.settings.enabled) return en ? 'Off' : '未开启';
  final preset = _presetSubtitle(state.settings.presetId, en: en);
  return en ? 'On · $preset' : '已开启 · $preset';
}

String _presetSubtitle(String id, {required bool en}) {
  if (!en) return equalizerPresetLabel(id);
  return switch (id) {
    'flat' => 'Flat',
    'pop' => 'Pop',
    'rock' => 'Rock',
    'jazz' => 'Jazz',
    'classical' => 'Classical',
    'electronic' => 'Electronic',
    'folk' => 'Folk',
    'vocal' => 'Vocal',
    'bass' => 'Bass boost',
    'treble' => 'Treble boost',
    _ => 'Custom',
  };
}

/// 均衡器设置的读取入口，测试可替换。
final equalizerStorageProvider = Provider<StorageLoader>(
  (ref) =>
      () => StorageService.instance,
);

final equalizerProvider =
    StateNotifierProvider<EqualizerNotifier, EqualizerState>((ref) {
      return EqualizerNotifier(
        bridge: ref.watch(equalizerBridgeProvider),
        storage: ref.watch(equalizerStorageProvider),
      );
    });

class EqualizerNotifier extends StateNotifier<EqualizerState> {
  EqualizerNotifier({required EqualizerBridge bridge, StorageLoader? storage})
    : _bridge = bridge,
      _storage = storage ?? (() => StorageService.instance),
      super(EqualizerState(supported: bridge.isSupported)) {
    _restored = _restore();
  }

  final EqualizerBridge _bridge;
  final StorageLoader _storage;
  late final Future<void> _restored;

  /// 首次读取持久化设置完成的信号（测试用）。
  @visibleForTesting
  Future<void> get restored => _restored;

  Future<void> _restore() async {
    var settings = const EqualizerSettings();
    try {
      final raw = (await _storage()).getJson(equalizerSettingsStorageKey);
      if (raw != null) settings = EqualizerSettings.fromJson(raw);
    } catch (_) {
      // 读取失败按默认值处理，不影响进入页面。
    }
    if (!mounted) return;
    state = state.copyWith(settings: settings, loading: false);
    if (!_bridge.isSupported) return;
    // 先登记并施加期望状态：播放器还没激活时桥会记下来，激活后自己补上，
    // 用户不必重进页面。
    await _bridge.apply(
      enabled: settings.enabled,
      gains: settings.gainsFor(state.effectiveLayout),
    );
    await _refreshLayout();
  }

  Future<void> setEnabled(bool enabled) =>
      _commit(state.settings.copyWith(enabled: enabled));

  /// 选择预设：按当前布局把曲线采样成频段增益。
  Future<void> selectPreset(String presetId) => _commit(
    state.settings.copyWith(
      presetId: presetId,
      gains: gainsForPreset(presetId, state.effectiveLayout.centerFrequencies),
    ),
  );

  /// 拖动单个频段：切到「自定义」。
  Future<void> setBandGain(int index, double gain) async {
    final layout = state.effectiveLayout;
    if (index < 0 || index >= layout.bandCount) return;
    final gains = List<double>.of(state.settings.gainsFor(layout));
    gains[index] = layout.clampGain(gain);
    await _commit(
      state.settings.copyWith(presetId: kCustomPresetId, gains: gains),
    );
  }

  /// 复位成原声（保留总开关）。
  Future<void> resetToFlat() => selectPreset(kDefaultPresetId);

  /// 重新读取设备频段布局。播放器刚激活时用得上。
  Future<void> refreshLayout() => _refreshLayout();

  Future<void> _commit(EqualizerSettings settings) async {
    state = state.copyWith(settings: settings);
    await _persist(settings);
    if (!_bridge.isSupported) return;
    await _bridge.apply(
      enabled: settings.enabled,
      gains: settings.gainsFor(state.effectiveLayout),
    );
    await _refreshLayout();
  }

  Future<void> _refreshLayout() async {
    final layout = await _bridge.loadLayout();
    if (!mounted || layout == null || layout == state.layout) return;
    state = state.copyWith(layout: layout);
  }

  Future<void> _persist(EqualizerSettings settings) async {
    try {
      final storage = await _storage();
      await storage.setJson(equalizerSettingsStorageKey, settings.toJson());
    } catch (_) {
      // 持久化失败不影响本次生效。
    }
  }
}
