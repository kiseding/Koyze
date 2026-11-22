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
/// **鸿蒙上没有回退**：均衡器、交叉馈送、限幅、实时频谱全部挂在 mpv 的
/// 滤镜链 / FFT 管线上，退回 `just_audio` 等于让这一整套功能集体失效，
/// 用户看到的就是「均衡器不可用」。宁可显式报错，也不静默降级到半个
/// 播放器。桌面/移动端同理——它们本来就该带 libmpv。
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

/// 两种 ABI 都构建为纯音频：libc++_shared 随 HAP 分发，libc 由系统提供。
/// 唯一需要兜底预加载的是可能不在应用 linker 搜索路径里的 libohaudio。
/// 不探测视频 / OHCodec 库，避免把可选组件缺失误报为启动失败原因。
const List<String> kOhosNdkDependencies = ['libohaudio.so'];

/// 鸿蒙系统库的可能目录，按命中概率排列。
const List<String> kOhosSystemLibDirs = [
  '/system/lib64/ndk',
  '/system/lib64',
  '/system/lib/ndk',
];

/// 依次尝试的完整路径：库 × 目录。
List<String> get kOhosPreloadCandidates => [
  for (final dir in kOhosSystemLibDirs)
    for (final lib in kOhosNdkDependencies) '$dir/$lib',
];

/// 把 [kOhosNdkDependencies] 里的库预加载进当前进程。
///
/// 返回 (成功数, 失败清单)。只在鸿蒙上调用，且必须在创建 mpv 之前。
/// 已经加载过的库再 `open` 一次会拿到同一个 handle，代价可以忽略。
({int loaded, List<String> failed}) preloadOhosNdkLibraries() {
  var loaded = 0;
  final failed = <String>[];
  final loadedNames = <String>{};
  for (final dir in kOhosSystemLibDirs) {
    for (final lib in kOhosNdkDependencies) {
      if (loadedNames.contains(lib)) continue;
      try {
        DynamicLibrary.open('$dir/$lib');
        loadedNames.add(lib);
        loaded++;
        _trace('preloaded $lib <- $dir');
      } catch (error) {
        // 只在这本库的最后一个候选目录失败时记一笔，中间目录失败是正常的。
        if (dir == kOhosSystemLibDirs.last) {
          failed.add('$lib ($error)');
        }
      }
    }
  }
  _trace('preload ndk: loaded=$loaded failed=${failed.join(' | ')}');
  return (loaded: loaded, failed: failed);
}

/// 当前进程是否跑在 OpenHarmony / HarmonyOS 上。
///
/// 不用 `Platform.isOhos`：普通 Flutter SDK 的 `dart:io` 没有这个字段，
/// 字符串比较让同一份代码在两套 SDK 下都能编译。
bool get isOhosPlatform => Platform.operatingSystem == 'ohos';

/// libmpv 在这个进程里起不来的原因。
///
/// 抛它而不是返回 null：均衡器 / 交叉馈送 / 限幅 / 实时频谱全部挂在 mpv
/// 的滤镜链与 FFT 管线上。静默退回 `just_audio` 会让这些功能集体失效，
/// 用户看到的是「均衡器不可用」这种无从下手的提示；启动直接失败至少
/// 能看到一句具体原因加一个重试按钮。
class PlaybackEngineUnavailable implements Exception {
  const PlaybackEngineUnavailable({
    required this.reason,
    this.diagnostic,
    this.cause,
  });

  /// 面向用户的短句。
  final String reason;

  /// 面向排查的细节：候选路径、`mpv-version` 读失败的原因等。
  final String? diagnostic;

  /// 原始异常（如果有）。
  final Object? cause;

  @override
  String toString() =>
      'PlaybackEngineUnavailable($reason${diagnostic == null ? '' : '；$diagnostic'})';
}

/// 创建 mpv 引擎并确认 libmpv 真的能用。
///
/// 只有一条路径：拿不到可用的 libmpv 就抛 [PlaybackEngineUnavailable]，
/// 由 `main.dart` 落到启动失败页。没有「返回 null 让调用方回退」这回事
/// ——均衡器 / 交叉馈送 / 限幅 / 实时频谱全挂在 mpv 上，退回 `just_audio`
/// 等于让它们集体失效，用户只会看到「均衡器不可用」这种无从下手的提示。
///
/// 设备上真实会发生的三种失败：
///
/// * `.so` 没打进 HAP：读不到库文件；
/// * `libc++_shared.so` 没跟 `libmpv.so` 放同一目录——它不在应用 linker
///   namespace 里，缺了它 `dlopen` 直接失败；
/// * 依赖的 `libohaudio.so` 不在 linker 搜索路径里
///   （鸿蒙把系统库装在 `/system/lib64/ndk/`）。这条最隐蔽，见
///   [kOhosNdkDependencies]。
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
  // 这条链路没有日志就只能靠猜。
  ohosLog('KoyzeMpv', message);
}

Future<PlaybackEngine> createMpvPlaybackEngine({String? libmpv}) async {
  final library = libmpv ?? _defaultLibmpv();
  _trace('enter library=$library');
  if (isOhosPlatform) {
    // libmpv 的 API 契约（mpv/client.h）要求调用方把 LC_NUMERIC 设为 C，
    // 否则 mpv_create() 直接 abort。mpv 自己起的线程继承进程级 locale，
    // 所以必须进程级设置。只在鸿蒙做：其它平台上 mpv_audio_kit 已经处理。
    applyCNumericLocale();
  }
  _trace('locale done, ensureInitialized');
  var preload = (loaded: 0, failed: <String>[]);
  if (isOhosPlatform) {
    // 先预加载 libohaudio，处理系统库目录不在应用 linker 搜索路径里的设备。
    preload = preloadOhosNdkLibraries();
  }
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

  final probe = await _probeLibmpv(player);
  _trace('probe returned version=${probe.version} error=${probe.error}');
  if (probe.version == null) {
    // bring-up 失败时 core 可能只起了一半，销毁要吞异常——真正有价值的
    // 信息是上面那条日志，别让清理阶段的报错把它盖掉。
    try {
      await player.dispose().timeout(const Duration(seconds: 3));
      _trace('dispose done');
    } catch (error) {
      _trace('dispose failed/blocked: $error');
    }
    throw PlaybackEngineUnavailable(
      reason: '音频引擎（libmpv）加载失败',
      diagnostic: [
        'library=$library',
        if (isOhosPlatform) 'ndk 预加载 ${preload.loaded} 个',
        if (preload.failed.isNotEmpty) '未加载：${preload.failed.join(', ')}',
        if (probe.error != null) 'probe: ${probe.error}',
      ].join('；'),
      cause: probe.error,
    );
  }
  AppLog.instance.record('audio.mpv', 'libmpv 就绪：${probe.version}');
  // Determine support from the loaded library on every native platform.
  var supportsPcmTap = false;
  try {
    final properties = await player
        .getRawPropertyNode('property-list')
        .timeout(const Duration(seconds: 2));
    supportsPcmTap = properties is List && properties.contains('pcm-tap-frame');
  } catch (error) {
    AppLog.instance.record(
      'audio.mpv',
      'PCM tap capability probe failed: $error',
    );
  }
  AppLog.instance.record(
    'audio.mpv',
    'pcm-tap-frame supported=$supportsPcmTap',
  );
  _trace('pcm-tap-frame supported=$supportsPcmTap');
  _trace('engine ready');
  return MpvEngine(player, supportsPcmTap: supportsPcmTap);
}

/// `mpv-version` 的读取结果。失败时 [version] 为 null 并带上 [error]。
typedef _LibmpvProbe = ({String? version, Object? error});

/// 读一次 `mpv-version` 确认库真的起来了。
Future<_LibmpvProbe> _probeLibmpv(mpv.Player player) async {
  try {
    final version = await player
        .getRawProperty('mpv-version')
        .timeout(const Duration(seconds: 10));
    if (version == null || version.isEmpty) {
      throw StateError('mpv-version 返回空值');
    }
    return (version: version, error: null);
  } catch (error, stackTrace) {
    AppLog.instance.record(
      'audio.mpv',
      'libmpv 自检失败：$error',
      level: AppLogLevel.error,
      stackTrace: stackTrace,
    );
    return (version: null, error: error);
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
