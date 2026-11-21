import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

import '../logging/app_log.dart';
import '../logging/ohos_hilog.dart';
import 'mpv_engine.dart';
import 'playback_engine.dart';

/// 播放引擎的类型。
///
/// 同一进程内只应该有一种引擎：两套音频后端同时存在会各自抢音频焦点，
/// 表现为「播放时另一路在后台空转」。
enum PlaybackEngineKind {
  /// `just_audio`。所有平台的默认值，也是重构前的行为基线。
  justAudio,

  /// libmpv（`mpv_audio_kit`）。HarmonyOS 的目标引擎。
  mpv,
}

/// 本机默认引擎。
///
/// 默认走 [PlaybackEngineKind.mpv]。这个结论有实测支撑：在鸿蒙模拟器
/// （x86_64，`Mate 90 Pro`，API 26）上装 debug HAP，日志确认
/// `libmpv 就绪：mpv v0.41.0-dev`，随后《我不难过》从 00:52 播到 01:19、
/// 歌词同步滚动 —— `dlopen` 与 `ao_ohaudio` 都是真实可用的。
///
/// 仍然保留 just_audio 作为回退：[createMpvPlaybackEngine] 会自检 libmpv，
/// 返回 null 时 `main.dart` 继续走 just_audio 分支。桌面/移动端没有系统
/// libmpv 时也会自动落到这条路上，所以这个默认值不会让非鸿蒙平台没声音。
///
/// 临时只跑某一条路径时可以用编译期开关覆盖：
///
/// ```bash
/// flutter build hap --dart-define=KOYZE_PLAYBACK_ENGINE=just_audio
/// ```
PlaybackEngineKind hostPlaybackEngineKind() {
  const override = String.fromEnvironment('KOYZE_PLAYBACK_ENGINE');
  return parsePlaybackEngineOverride(override) ?? _defaultPlaybackEngineKind();
}

/// 把 `--dart-define=KOYZE_PLAYBACK_ENGINE=...` 的原始值解析成引擎类型。
///
/// 返回 null 表示「没指定 / 不认识」，由调用方退回默认值。无法识别的值
/// **不抛异常**：一个拼错的构建参数不该让应用起不来，退回默认引擎即可。
///
/// 单独抽成纯函数是为了能测——`String.fromEnvironment` 是编译期常量，
/// 测试里没法改它。
PlaybackEngineKind? parsePlaybackEngineOverride(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'mpv':
      return PlaybackEngineKind.mpv;
    case 'just_audio':
    case 'justaudio':
      return PlaybackEngineKind.justAudio;
  }
  return null;
}

PlaybackEngineKind _defaultPlaybackEngineKind() => PlaybackEngineKind.mpv;

/// HAP 里 libmpv 的 soname。
///
/// 打进 HAP 的 `libs/<abi>/*.so` 由系统 linker 按 soname 解析，拼绝对
/// 路径反而会在安装位置变化后失效。
const String kOhosLibmpvName = 'libmpv.so';

/// 当前进程是否跑在 OpenHarmony / HarmonyOS 上。
///
/// 不用 `Platform.isOhos`：普通 Flutter SDK 的 `dart:io` 没有这个字段，
/// 字符串比较让同一份代码在两套 SDK 下都能编译。
bool get isOhosPlatform => Platform.operatingSystem == 'ohos';

/// 创建 mpv 引擎，并在返回前确认 libmpv 真的能用。
///
/// 返回 `null` 表示 libmpv 不可用，调用方必须退回 just_audio。这不是
/// 防御性编程的洁癖，而是设备上真实会发生的三种失败：
///
/// * `.so` 没打进 HAP（ABI 目录名写错、打包时被 strip 掉）；
/// * `libc++_shared.so` 没跟 `libmpv.so` 放同一目录——它不在应用 linker
///   namespace 里，缺了它 `dlopen` 直接失败；
/// * `LC_NUMERIC` 没设成 `C`，`mpv_create()` 走 abort 分支。
///
/// 三种现象都是「点了播放没声音」，日志里却长得完全不一样，所以这里主动
/// 读一次 `mpv-version` 把结论钉进日志。
///
/// **为什么必须 await**：`Player` 的构造只负责起事件 isolate，真正的
/// `dlopen` 发生在那个 isolate 里，失败是**异步**抛出的。同步 try/catch
/// 抓不到，只能靠一次属性读来确认——`getRawProperty` 内部先
/// `await _gate()`，也就是等 bring-up 完成。
void _trace(String message) {
  // 鸿蒙上 print/debugPrint 写 stdout，没有接收方，平台侧诊断必须走 hilog
  // 才能被 `hdc shell hilog | grep KoyzeMpv` 看到。libmpv 加载失败时
  // 应用会静默退回 just_audio，这条链路没有日志就只能靠猜。
  ohosLog('KoyzeMpv', message);
}

Future<PlaybackEngine?> createMpvPlaybackEngine({String? libmpv}) async {
  final library = libmpv ?? _defaultLibmpv();
  _trace('enter library=$library');
  if (isOhosPlatform) {
    // libmpv 的 API 契约（mpv/client.h）要求调用方把 LC_NUMERIC 设为 C，
    // 否则 mpv_create() 直接 abort。mpv 自己起的线程继承进程级 locale，
    // 所以必须进程级设置。只在鸿蒙做：其它平台上 mpv_audio_kit 已经处理。
    applyCNumericLocale();
  }
  _trace('locale done, ensureInitialized');
  if (!_mpvInitialized) {
    mpv.MpvAudioKit.ensureInitialized(libmpv: library);
    _mpvInitialized = true;
  }
  _trace('constructing Player');
  final player = mpv.Player(
    configuration: const mpv.PlayerConfiguration(
      // 起播时机由 handler 的状态机决定，引擎不自己抢跑。
      autoPlay: false,
      // Koyze 自己持久化播放进度。让 mpv 也记 watch-later 会出现两套
      // 进度互相覆盖，恢复时跳到错误位置。
      resumePlayback: false,
      // HLS / 直链 HTTP 不一定声明可 seek，而 Koyze 的进度条与歌词
      // 依赖 seek。强制可 seek 让拖动在这些源上也能用。
      forceSeekable: true,
    ),
  );

  final version = await _probeLibmpv(player);
  _trace('probe returned version=$version');
  if (version == null) {
    // bring-up 失败时 core 可能只起了一半，销毁要吞异常——真正有价值的
    // 信息是上面那条日志，别让清理阶段的报错把它盖掉。
    try {
      await player.dispose().timeout(const Duration(seconds: 3));
      _trace('dispose done');
    } catch (error) {
      _trace('dispose failed/blocked: $error');
    }
    return null;
  }
  AppLog.instance.record('audio.mpv', 'libmpv 就绪：$version');
  _trace('engine ready');
  return MpvEngine(player);
}

/// 读一次 `mpv-version` 确认库真的起来了，返回版本串；失败返回 null。
Future<String?> _probeLibmpv(mpv.Player player) async {
  try {
    final version = await player
        .getRawProperty('mpv-version')
        .timeout(const Duration(seconds: 10));
    if (version == null || version.isEmpty) {
      throw StateError('mpv-version 返回空值');
    }
    return version;
  } catch (error, stackTrace) {
    AppLog.instance.record(
      'audio.mpv',
      'libmpv 自检失败，退回 just_audio：$error',
      level: AppLogLevel.error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

bool _mpvInitialized = false;

String? _defaultLibmpv() {
  if (isOhosPlatform) return kOhosLibmpvName;
  // 其它平台返回 null，交给 mpv_audio_kit 用它自己打包的那份。
  return null;
}

// ---------------------------------------------------------------------------
// 鸿蒙的 locale 引导
// ---------------------------------------------------------------------------

/// musl 与 glibc 的 `LC_NUMERIC` 都是 1。
const int _lcNumeric = 1;

typedef _SetLocaleNative = Pointer<Utf8> Function(Int32, Pointer<Utf8>);
typedef _SetLocaleDart = Pointer<Utf8> Function(int, Pointer<Utf8>);

/// 把进程的 `LC_NUMERIC` 修成 `C`，返回是否确认生效。
///
/// 失败只记录不抛：locale 本来就是 C 时（多数应用进程）mpv 仍能起来，
/// 为了一个 locale 让整个播放器初始化失败得不偿失。
bool applyCNumericLocale() {
  final setlocale = _lookupSetLocale();
  if (setlocale == null) return false;
  try {
    final result = using(
      (arena) => setlocale(_lcNumeric, 'C'.toNativeUtf8(allocator: arena)),
    );
    if (result == nullptr) {
      AppLog.instance.record(
        'audio.mpv',
        'setlocale(LC_NUMERIC, "C") 返回空指针',
        level: AppLogLevel.warning,
      );
      return false;
    }
    final current = result.toDartString();
    if (current != 'C') {
      AppLog.instance.record(
        'audio.mpv',
        'setlocale(LC_NUMERIC, "C") 实际得到 "$current"',
        level: AppLogLevel.warning,
      );
      return false;
    }
    return true;
  } catch (error) {
    AppLog.instance.record(
      'audio.mpv',
      'setlocale 调用失败：$error',
      level: AppLogLevel.warning,
    );
    return false;
  }
}

_SetLocaleDart? _lookupSetLocale() {
  final sources = <(String, DynamicLibrary Function())>[
    ('libc.so', () => DynamicLibrary.open('libc.so')),
    ('process', DynamicLibrary.process),
  ];
  for (final (label, open) in sources) {
    try {
      return open().lookupFunction<_SetLocaleNative, _SetLocaleDart>(
        'setlocale',
      );
    } catch (error) {
      AppLog.instance.record(
        'audio.mpv',
        'setlocale：$label 取不到符号（$error）',
        level: AppLogLevel.warning,
      );
    }
  }
  return null;
}
