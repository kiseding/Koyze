import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_handler.dart';
import '../../../core/performance/low_memory.dart';
import '../../../core/storage/persisted_setting.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/theme/app_themes.dart';
import '../../nas/domain/nas_url.dart';
import '../../player/domain/player_backdrop.dart';
import 'settings_provider.dart' show AudioQualityOption, audioQualityToken;

// ---- Notifiers ----
//
// Migrated from `StateNotifier` to `Notifier` (review item #11).
//
// The migration is not a rename: `Notifier.state` only exists after `build()`
// has run inside a provider container, while twelve test files construct these
// notifiers directly and read `state` synchronously to exercise load/mutation
// races. Deleting that ability would have meant rewriting those tests against a
// `ProviderContainer`, which couples them to Riverpod instead of to the
// behaviour under test.
//
// The split used here solves both: `PersistedSetting<T>` (core/storage) is a
// plain object holding the value and the race rules, and the notifier is an
// adapter. Direct construction in a test still yields a working object with a
// synchronously readable `value`; under Riverpod the adapter mirrors it into
// `state`.

/// Shared adapter for one persisted scalar setting.
///
/// Subclasses supply the initial value, the storage key reader, and any
/// side effects that must run when the value changes.
abstract class _PersistedSettingNotifier<T> extends Notifier<T> {
  _PersistedSettingNotifier(this.initialValue, {StorageLoader? storage})
    : _setting = PersistedSetting<T>(
        initialValue: initialValue,
        storage: storage,
      );

  final T initialValue;
  final PersistedSetting<T> _setting;

  /// The durable state machine. Tests may drive it directly.
  @protected
  PersistedSetting<T> get setting => _setting;

  /// Current value, readable before [build] has run.
  ///
  /// Under Riverpod this is the same value as [state]; outside a container
  /// [state] is unavailable, so tests use this.
  T get value => _setting.value;

  /// Reads the persisted value. Returning null keeps [initialValue].
  T? readFrom(StorageService storage);

  /// Kicks off the async load. Production calls it from [build]; tests get it
  /// from the constructor so a direct instantiation behaves like the old
  /// `StateNotifier` did.
  void startLoad() {
    // ignore: discarded_futures
    _setting.load(readFrom).then((_) => _mirrorState());
  }

  void _mirrorState() {
    // `state` throws until `build()` has run inside a container. Direct
    // instantiation in a test never builds, and the value the test reads comes
    // from [value] instead.
    try {
      state = _setting.value;
    } catch (_) {
      // Not attached to a ProviderContainer.
    }
  }

  @override
  T build() {
    ref.onDispose(onTeardown);
    startLoad();
    return _setting.value;
  }

  /// Called when the provider is disposed. Subclasses that hold timers or
  /// subscriptions override this instead of `dispose()`, which `Notifier` does
  /// not expose in Riverpod 2.x.
  @protected
  void onTeardown() {}

  /// Applies [value], persists it, and reports whether the write is still the
  /// newest one when it completes.
  @protected
  Future<bool> persist(
    T next,
    Future<bool> Function(StorageService storage) write,
  ) async {
    final owns = await _setting.set(next, write);
    _mirrorState();
    return owns;
  }

  /// Applies an already-persisted value (cloud restore / external commit).
  @protected
  void applyCommittedValue(T next) {
    _setting.applyCommitted(next);
    _mirrorState();
  }
}

class AccentColorNotifier extends _PersistedSettingNotifier<Color> {
  AccentColorNotifier({StorageLoader? storage})
    : super(AppThemes.defaultAccentColor, storage: storage) {
    startLoad();
  }

  static const String _storageKey = 'app_accent_color';

  @override
  Color? readFrom(StorageService storage) {
    final value = storage.getInt(_storageKey);
    return value == null ? null : Color(value);
  }

  Future<void> setAccentColor(Color color) async {
    if (value.toARGB32() == color.toARGB32()) return;
    await persist(
      color,
      (storage) => storage.setInt(_storageKey, color.toARGB32()),
    );
  }
}

class ThemeModeNotifier extends _PersistedSettingNotifier<ThemeMode> {
  ThemeModeNotifier({StorageLoader? storage})
    : super(ThemeMode.system, storage: storage) {
    startLoad();
  }

  @override
  ThemeMode? readFrom(StorageService storage) {
    final index = storage.getInt('theme_mode');
    return index == null
        ? null
        : ThemeMode.values[index.clamp(0, ThemeMode.values.length - 1)];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await persist(mode, (storage) => storage.setInt('theme_mode', mode.index));
  }

  void applyCommitted(ThemeMode mode) {
    applyCommittedValue(mode);
  }
}

class AudioQualityNotifier
    extends _PersistedSettingNotifier<AudioQualityOption> {
  AudioQualityNotifier({
    StorageLoader? storage,
    Future<void> Function(String quality)? applyPreferredQuality,
  }) : _applyPreferredQuality =
           applyPreferredQuality ?? _applyPreferredQualityToHandler,
       super(AudioQualityOption.high, storage: storage) {
    startLoad();
  }

  final Future<void> Function(String quality) _applyPreferredQuality;

  static Future<void> _applyPreferredQualityToHandler(String quality) async {
    if (audioHandler is LxAudioHandler) {
      await (audioHandler as LxAudioHandler).applyPreferredQuality(quality);
    }
  }

  @override
  AudioQualityOption? readFrom(StorageService storage) {
    final index = storage.getInt('audio_quality');
    return index == null
        ? null
        : AudioQualityOption.values[index.clamp(
            0,
            AudioQualityOption.values.length - 1,
          )];
  }

  Future<void> setQuality(AudioQualityOption quality) async {
    final ownsPersistedValue = await persist(
      quality,
      (storage) => storage.setInt('audio_quality', quality.index),
    );
    if (!ownsPersistedValue) return;
    // 立即让正在播放的队列按新音质重解析，避免继续用旧 extras.url
    final token = audioQualityToken(quality);
    try {
      await _applyPreferredQuality(token);
    } catch (_) {
      // audioHandler 可能尚未 init（单测）；忽略
    }
  }

  void applyCommitted(AudioQualityOption quality) {
    applyCommittedValue(quality);
  }
}

class DownloadQualityNotifier
    extends _PersistedSettingNotifier<AudioQualityOption> {
  DownloadQualityNotifier({StorageLoader? storage})
    : super(AudioQualityOption.high, storage: storage) {
    startLoad();
  }

  @override
  AudioQualityOption? readFrom(StorageService storage) {
    final index = storage.getInt('download_quality');
    return index == null
        ? null
        : AudioQualityOption.values[index.clamp(
            0,
            AudioQualityOption.values.length - 1,
          )];
  }

  Future<void> setQuality(AudioQualityOption quality) async {
    await persist(
      quality,
      (storage) => storage.setInt('download_quality', quality.index),
    );
  }

  void applyCommitted(AudioQualityOption quality) {
    applyCommittedValue(quality);
  }
}

class WifiOnlyDownloadNotifier extends _PersistedSettingNotifier<bool> {
  WifiOnlyDownloadNotifier({StorageLoader? storage})
    : super(true, storage: storage) {
    startLoad();
  }

  @override
  bool? readFrom(StorageService storage) =>
      storage.getBool('wifi_only_download');

  Future<void> setWifiOnly(bool value) async {
    await persist(
      value,
      (storage) => storage.setBool('wifi_only_download', value),
    );
  }

  void applyCommitted(bool value) {
    applyCommittedValue(value);
  }
}

class AutoResumePlaybackNotifier extends _PersistedSettingNotifier<bool> {
  AutoResumePlaybackNotifier({StorageLoader? storage})
    : super(false, storage: storage) {
    startLoad();
  }

  @override
  bool? readFrom(StorageService storage) =>
      storage.getBool('auto_resume_playback');

  Future<void> setAutoResume(bool value) async {
    await persist(
      value,
      (storage) => storage.setBool('auto_resume_playback', value),
    );
  }

  void applyCommitted(bool value) {
    applyCommittedValue(value);
  }
}

class AndroidFloatingPlayerNotifier extends _PersistedSettingNotifier<bool> {
  AndroidFloatingPlayerNotifier({StorageLoader? storage})
    : super(false, storage: storage) {
    startLoad();
  }

  @override
  bool? readFrom(StorageService storage) =>
      storage.getBool('android_floating_player');

  Future<void> setEnabled(bool value) async {
    await persist(
      value,
      (storage) => storage.setBool('android_floating_player', value),
    );
  }
}

class ForceLandscapeNotifier extends _PersistedSettingNotifier<bool> {
  ForceLandscapeNotifier({StorageLoader? storage})
    : super(false, storage: storage) {
    startLoad();
  }

  @override
  bool? readFrom(StorageService storage) => storage.getBool('force_landscape');

  Future<void> setEnabled(bool value) async {
    await persist(
      value,
      (storage) => storage.setBool('force_landscape', value),
    );
  }
}

class SimplifyEffectsNotifier extends _PersistedSettingNotifier<bool> {
  SimplifyEffectsNotifier({StorageLoader? storage})
    : super(LowMemory.active, storage: storage) {
    startLoad();
  }

  @override
  bool? readFrom(StorageService storage) {
    final stored = storage.getBool('simplify_effects');
    if (stored == null) return null;
    LowMemory.active = stored;
    return stored;
  }

  Future<void> setEnabled(bool value) async {
    final previous = LowMemory.active;
    LowMemory.active = value;
    try {
      await persist(
        value,
        (storage) => storage.setBool('simplify_effects', value),
      );
    } catch (_) {
      LowMemory.active = previous;
      rethrow;
    }
  }
}

/// 滑杆类设置的公共骨架：值立刻生效，写盘合并到停下之后。
///
/// 拖动一次滑块会回调几十上百次 `onChanged`，每次都写一遍 SharedPreferences
/// 既浪费又会让磁盘队列堆积。这里沿用音量的做法——内存值同步更新（界面跟手），
/// 落盘延后 [_writeDelay]，期间只保留最后一次；页面销毁时把还没落盘的那次补上。
abstract class _SliderSettingNotifier
    extends _PersistedSettingNotifier<double> {
  _SliderSettingNotifier(super.initialValue, {super.storage}) {
    startLoad();
  }

  static const Duration _writeDelay = Duration(milliseconds: 120);

  Timer? _persistTimer;
  double? _pending;

  /// 把越界值拉回合法区间。子类决定区间。
  double normalize(double value);

  /// 真正写盘。子类提供存储键。
  Future<bool> writeValue(StorageService storage, double value);

  @override
  void onTeardown() => flush();

  /// 立即生效、延迟落盘。
  void applyLive(double value) {
    final next = normalize(value);
    setting.applyCommitted(next);
    _mirrorState();
    _pending = next;
    _persistTimer?.cancel();
    _persistTimer = Timer(_writeDelay, flush);
  }

  /// 把还在等待的那次写入立刻发出去。
  ///
  /// 面板关掉、页面销毁、测试想跳过 120ms 的等待时都走这里。
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    unawaited(
      persist(
        pending,
        (storage) => writeValue(storage, pending),
      ).catchError((_) => false),
    );
  }

  /// 恢复出厂档位，并立刻落盘（不跟手的东西不需要延迟）。
  Future<void> resetTo(double value) async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _pending = null;
    final next = normalize(value);
    await persist(next, (storage) => writeValue(storage, next));
  }
}

class PlayerBackdropBlurNotifier extends _SliderSettingNotifier {
  PlayerBackdropBlurNotifier({StorageLoader? storage})
    : super(PlayerBackdrop.defaultBlur, storage: storage);

  static const String _storageKey = 'player_backdrop_blur';

  @override
  double normalize(double value) => PlayerBackdrop.clampBlur(value);

  @override
  double? readFrom(StorageService storage) {
    final value = storage.getDouble(_storageKey);
    return value == null ? null : PlayerBackdrop.clampBlur(value);
  }

  @override
  Future<bool> writeValue(StorageService storage, double value) =>
      storage.setDouble(_storageKey, value);

  /// 拖动中调用：立刻生效，120ms 后落盘。
  void setBlur(double value) => applyLive(value);

  /// 直接写定（无拖动），例如「恢复默认」。
  Future<void> commitBlur(double value) => resetTo(value);
}

class PlayerBackdropScrimNotifier extends _SliderSettingNotifier {
  PlayerBackdropScrimNotifier({StorageLoader? storage})
    : super(PlayerBackdrop.defaultScrim, storage: storage);

  static const String _storageKey = 'player_backdrop_scrim';

  @override
  double normalize(double value) => PlayerBackdrop.clampScrim(value);

  @override
  double? readFrom(StorageService storage) {
    final value = storage.getDouble(_storageKey);
    return value == null ? null : PlayerBackdrop.clampScrim(value);
  }

  @override
  Future<bool> writeValue(StorageService storage, double value) =>
      storage.setDouble(_storageKey, value);

  void setScrim(double value) => applyLive(value);

  Future<void> commitScrim(double value) => resetTo(value);
}

class DefaultSearchPlatformNotifier extends _PersistedSettingNotifier<String> {
  DefaultSearchPlatformNotifier({StorageLoader? storage})
    : super('tx', storage: storage) {
    startLoad();
  }

  @override
  String? readFrom(StorageService storage) {
    final value = storage.getString('default_search_platform');
    if (value == null || !allowedSearchPlatforms.contains(value)) {
      return null;
    }
    return canonicalSearchPlatform(value);
  }

  Future<void> setPlatform(String platform) async {
    if (!allowedSearchPlatforms.contains(platform)) {
      return;
    }
    final normalized = canonicalSearchPlatform(platform);
    await persist(
      normalized,
      (storage) => storage.setString('default_search_platform', normalized),
    );
  }

  void applyCommitted(String platform) {
    applyCommittedValue(canonicalSearchPlatform(platform));
  }
}

enum AppLanguage {
  system,
  zh,
  en;

  static const supportedLocales = <Locale>[Locale('zh'), Locale('en')];

  Locale? get materialLocale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.zh => const Locale('zh'),
    AppLanguage.en => const Locale('en'),
  };

  static AppLanguage parse(String? raw) => switch (raw) {
    'zh' => AppLanguage.zh,
    'en' => AppLanguage.en,
    _ => AppLanguage.system,
  };
}

class AppLanguageNotifier extends _PersistedSettingNotifier<AppLanguage> {
  AppLanguageNotifier({StorageLoader? storage})
    : super(AppLanguage.system, storage: storage) {
    startLoad();
  }

  static const String _storageKey = 'app_language';

  @override
  AppLanguage? readFrom(StorageService storage) =>
      AppLanguage.parse(storage.getString(_storageKey));

  Future<void> setLanguage(AppLanguage language) {
    return persist(
      language,
      (storage) => storage.setString(_storageKey, language.name),
    );
  }

  void applyCommitted(AppLanguage language) {
    applyCommittedValue(language);
  }
}

class PlaybackVolumeNotifier extends _PersistedSettingNotifier<double> {
  PlaybackVolumeNotifier({StorageLoader? storage})
    : super(1, storage: storage) {
    startLoad();
  }

  @override
  void onTeardown() => _flushPendingVolume();

  static const String _storageKey = 'playback_volume';

  Timer? _persistTimer;
  double? _pending;

  @override
  double? readFrom(StorageService storage) {
    final value = storage.getDouble(_storageKey);
    if (value == null) return null;
    return value.clamp(0.0, 1.0).toDouble();
  }

  void setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    setting.applyCommitted(clamped);
    _mirrorVolume();
    _pending = clamped;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 80), () {
      final pending = _pending;
      _pending = null;
      if (pending == null) return;
      unawaited(
        persist(pending, (storage) => storage.setDouble(_storageKey, pending)),
      );
    });
  }

  void _mirrorVolume() {
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {
      // Direct instantiation outside a container.
    }
  }

  void _flushPendingVolume() {
    _persistTimer?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending == null) return;
    unawaited(
      persist(pending, (storage) => storage.setDouble(_storageKey, pending)),
    );
  }
}

/// 锁屏 / 通知栏显示当前歌词行。默认关闭：它会让 mediaItem 频繁更新。
class LockScreenLyricNotifier extends _PersistedSettingNotifier<bool> {
  LockScreenLyricNotifier({StorageLoader? storage})
    : super(false, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'lock_screen_lyric_enabled';

  @override
  bool? readFrom(StorageService storage) => storage.getBool(storageKey);

  void setEnabled(bool enabled) {
    setting.applyCommitted(enabled);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(enabled, (storage) => storage.setBool(storageKey, enabled)),
    );
  }
}

/// 响度均衡（ReplayGain）。默认开启：它只在本曲有标签时生效，
/// 没有标签的歌完全不受影响。
class ReplayGainNotifier extends _PersistedSettingNotifier<bool> {
  ReplayGainNotifier({StorageLoader? storage}) : super(true, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'replay_gain_enabled';

  @override
  bool? readFrom(StorageService storage) => storage.getBool(storageKey);

  void setEnabled(bool enabled) {
    setting.applyCommitted(enabled);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(enabled, (storage) => storage.setBool(storageKey, enabled)),
    );
  }
}

/// 播放音调（半音）。
///
/// 与倍速分开存：倍速改时间轴，音调改频率。范围 ±12 半音（一个八度），
/// 再宽会明显失真；0.5 步长足够覆盖「降半音跟唱」这类需求。
class PitchSemitonesNotifier extends _PersistedSettingNotifier<double> {
  PitchSemitonesNotifier({StorageLoader? storage})
    : super(0, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'pitch_semitones';

  @override
  double? readFrom(StorageService storage) {
    final value = storage.getDouble(storageKey);
    if (value == null) return null;
    return normalizePitchSemitones(value);
  }

  void setSemitones(double semitones) {
    final next = normalizePitchSemitones(semitones);
    if (next == setting.value) return;
    setting.applyCommitted(next);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(next, (storage) => storage.setDouble(storageKey, next)),
    );
  }
}

/// 跳过静音（仅 Android 的原生 skipSilence）。
class SkipSilenceNotifier extends _PersistedSettingNotifier<bool> {
  SkipSilenceNotifier({StorageLoader? storage}) : super(false, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'skip_silence_enabled';

  @override
  bool? readFrom(StorageService storage) => storage.getBool(storageKey);

  void setEnabled(bool enabled) {
    setting.applyCommitted(enabled);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(enabled, (storage) => storage.setBool(storageKey, enabled)),
    );
  }
}

/// 播放/暂停时的音量淡入淡出。
class PlaybackFadeNotifier extends _PersistedSettingNotifier<bool> {
  PlaybackFadeNotifier({StorageLoader? storage})
    : super(true, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'playback_fade_enabled';

  @override
  bool? readFrom(StorageService storage) => storage.getBool(storageKey);

  void setEnabled(bool enabled) {
    setting.applyCommitted(enabled);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(enabled, (storage) => storage.setBool(storageKey, enabled)),
    );
  }
}

/// 把任意输入夹到 ±12 半音，并保留两位小数。
///
/// 不吸附到 0.5 刻度：滑块本身是 0.5 步长，但 432Hz 预设需要 -0.3177 这种
/// 精细值，吸附会让它偏成 -0.5（约 427.5Hz），听起来就不是 432Hz 了。
double normalizePitchSemitones(double semitones) {
  if (!semitones.isFinite) return 0;
  final clamped = semitones.clamp(-12.0, 12.0);
  return (clamped * 100).roundToDouble() / 100;
}

/// 半音 → 频率倍数（12 平均律）。
double pitchFactorForSemitones(double semitones) =>
    math.pow(2, normalizePitchSemitones(semitones) / 12).toDouble();

/// 432Hz 调音相对 440Hz 的频率倍数。
final double kPitchFactor432Hz = 432 / 440;

/// 界面展示：0 显示「0」，其余带正负号并去掉尾随 0。
String pitchSemitonesLabel(double semitones) {
  final normalized = normalizePitchSemitones(semitones);
  if (normalized == 0) return '0';
  var text = normalized.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return normalized > 0 ? '+$text' : text;
}

/// 播放倍速。
///
/// 只允许 0.5~2.0 的离散档位：低到 0 会让部分平台把播放器当暂停处理，
/// 高到 3 以上人声已经不可辨认，没有实际用途。档位固定也让界面不必
/// 展示「1.0499999×」这种数字。
class PlaybackSpeedNotifier extends _PersistedSettingNotifier<double> {
  PlaybackSpeedNotifier({StorageLoader? storage})
    : super(kDefaultPlaybackSpeed, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'playback_speed';

  @override
  double? readFrom(StorageService storage) {
    final value = storage.getDouble(storageKey);
    if (value == null) return null;
    return normalizePlaybackSpeed(value);
  }

  void setSpeed(double speed) {
    final next = normalizePlaybackSpeed(speed);
    if (next == setting.value) return;
    setting.applyCommitted(next);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {
      // Direct instantiation outside a container.
    }
    unawaited(persist(next, (storage) => storage.setDouble(storageKey, next)));
  }
}

/// 可选倍速档位。
const List<double> kPlaybackSpeedSteps = <double>[
  0.5,
  0.75,
  1.0,
  1.25,
  1.5,
  1.75,
  2.0,
];

const double kDefaultPlaybackSpeed = 1.0;

/// 把任意输入吸附到最近的合法档位。NaN / 非正值回落到 1.0；
/// 超出范围的吸附到最近的那个端点档位。
double normalizePlaybackSpeed(double speed) {
  if (speed.isNaN || speed <= 0) return kDefaultPlaybackSpeed;
  var best = kPlaybackSpeedSteps.first;
  for (final step in kPlaybackSpeedSteps) {
    if ((step - speed).abs() < (best - speed).abs()) best = step;
  }
  return best;
}

/// 界面展示用：1.0 显示「正常」，其余保留两位以内的小数。
String playbackSpeedLabel(double speed) {
  final normalized = normalizePlaybackSpeed(speed);
  if (normalized == 1.0) return '1.0×';
  final text = normalized.toStringAsFixed(2);
  return '${text.endsWith('0') ? text.substring(0, text.length - 1) : text}×';
}

/// 常听预缓存开关。
///
/// 默认关闭：它会主动下载整首歌，属于「用流量换启动速度」的取舍，
/// 应该在用户明确同意之后才发生，而不是默认替他决定。
class PrecacheEnabledNotifier extends _PersistedSettingNotifier<bool> {
  PrecacheEnabledNotifier({StorageLoader? storage})
    : super(false, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'precache_recent_enabled';

  @override
  bool? readFrom(StorageService storage) => storage.getBool(storageKey);

  void setEnabled(bool enabled) {
    setting.applyCommitted(enabled);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(
      persist(enabled, (storage) => storage.setBool(storageKey, enabled)),
    );
  }
}

/// 预缓存的曲目数量。
class PrecacheCountNotifier extends _PersistedSettingNotifier<int> {
  PrecacheCountNotifier({StorageLoader? storage})
    : super(kDefaultPrecacheCount, storage: storage) {
    startLoad();
  }

  static const String storageKey = 'precache_recent_count';

  @override
  int? readFrom(StorageService storage) {
    final value = storage.getInt(storageKey);
    if (value == null) return null;
    return normalizePrecacheCount(value);
  }

  void setCount(int count) {
    final next = normalizePrecacheCount(count);
    if (next == setting.value) return;
    setting.applyCommitted(next);
    try {
      if (state != setting.value) state = setting.value;
    } catch (_) {}
    unawaited(persist(next, (storage) => storage.setInt(storageKey, next)));
  }
}

const List<int> kPrecacheCountSteps = <int>[5, 10, 20];
const int kDefaultPrecacheCount = 10;

/// 吸附到最近的合法档位。
int normalizePrecacheCount(int count) {
  var best = kPrecacheCountSteps.first;
  for (final step in kPrecacheCountSteps) {
    if ((step - count).abs() < (best - count).abs()) best = step;
  }
  return best;
}
