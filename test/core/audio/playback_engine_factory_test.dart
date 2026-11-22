import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/playback_engine_factory.dart';

/// 读一份源码并去掉整行注释，用来做「代码里不能出现 X」这类断言。
///
/// 不能直接 `contains` 整份源码：注释里经常正好写着那个词（比如
/// 「不用 Platform.isOhos，因为…」），会把守卫测成假阴性。
String _codeOnly(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('parsePlaybackEngineOverride', () {
    test('recognises mpv', () {
      expect(parsePlaybackEngineOverride('mpv'), PlaybackEngineKind.mpv);
      // 构建脚本里多打一个空格很常见，不该因此退回默认引擎。
      expect(parsePlaybackEngineOverride(' MPV '), PlaybackEngineKind.mpv);
    });

    test('recognises just_audio in both spellings', () {
      for (final raw in ['just_audio', 'JustAudio', 'justaudio', 'JUST_AUDIO']) {
        expect(
          parsePlaybackEngineOverride(raw),
          PlaybackEngineKind.justAudio,
          reason: '"$raw"',
        );
      }
    });

    test('returns null for empty or unknown values', () {
      // 拼错的 --dart-define 既不该让应用起不来，也不该悄悄切到另一个引擎。
      for (final raw in ['', '   ', 'vlc', 'mpv2', 'libmpv']) {
        expect(parsePlaybackEngineOverride(raw), isNull, reason: '"$raw"');
      }
    });
  });

  test('mpv 是默认引擎', () {
    // 默认值已从 just_audio 切到 mpv。切之前做过的验证：鸿蒙模拟器
    // （x86_64 / API 26）上装 debug HAP，日志确认 libmpv 自检返回
    // `mpv v0.41.0-dev`，随后歌曲进度从 00:52 走到 01:19、歌词同步滚动，
    // 说明 dlopen 与 ao_ohaudio 都真的在工作。
    expect(hostPlaybackEngineKind(), PlaybackEngineKind.mpv);
  });

  test('鸿蒙按 soname 找库，不写绝对路径', () {
    // HAP 里的 libs/<abi>/*.so 由系统 linker 按 soname 解析，拼绝对路径
    // 会在安装位置变化后失效。
    expect(kOhosLibmpvName, 'libmpv.so');
    expect(kOhosLibmpvName.contains('/'), isFalse);
  });

  test('鸿蒙要先预加载 NDK 依赖，否则 libmpv 的依赖解析会失败', () {
    // 实测：这份 libmpv.so 的 NEEDED 里有 libohaudio.so（ao_ohaudio，
    // 17 个 OH_AudioRenderer_* / OH_AudioStreamBuilder_* 符号），而模拟器
    // 把它装在 /system/lib64/ndk/，不在应用 linker namespace 的搜索路径里。
    // 不预加载就 dlopen 失败，mpv-version 读出 null。
    final code = _codeOnly('lib/core/audio/playback_engine_factory.dart');
    expect(code, contains('preloadOhosNdkLibraries()'));
    // 必须在 ensureInitialized / Player 构造之前调用。
    final preload = code.indexOf('preloadOhosNdkLibraries()');
    final ensure = code.indexOf('MpvAudioKit.ensureInitialized');
    expect(preload, greaterThan(0));
    expect(preload, lessThan(ensure));
  });

  test('平台判定不依赖 dart:io 的 isOhos', () {
    // 普通 Flutter SDK 的 Platform 没有 isOhos 字段，用了就编译不过；
    // 字符串比较让同一份代码在两套 SDK 下都能编译。
    final code = _codeOnly('lib/core/audio/playback_engine_factory.dart');
    expect(code, contains("Platform.operatingSystem == 'ohos'"));
    expect(code, isNot(contains('Platform.isOhos')));
  });

  test('创建引擎前必须自检，失败抛异常而不是返回 null', () {
    // 同步 try/catch 抓不到 dlopen 失败 —— 它发生在事件 isolate 里，
    // 是异步抛出的。只能靠读一次 mpv-version（内部 await _gate()）确认。
    final code = _codeOnly('lib/core/audio/playback_engine_factory.dart');
    // 返回类型必须是非空：已经没有「返回 null 让调用方回退」这条路径。
    expect(code, contains('Future<PlaybackEngine> createMpvPlaybackEngine'));
    expect(code, isNot(contains('Future<PlaybackEngine?>')));
    expect(code, contains("getRawProperty('mpv-version')"));
    expect(code, contains('await player.dispose()'));
    // 均衡器 / 限幅 / 频谱全挂在 mpv 上，静默退回 just_audio 会让它们集体失效。
    expect(code, contains('throw PlaybackEngineUnavailable'));
  });

  test('main 直接 await 引擎，不再按 kind 分支', () {
    final code = _codeOnly('lib/main.dart');
    expect(code, contains('await createMpvPlaybackEngine()'));
    expect(code, contains('engine: engine'));
    // 旧实现是「工厂返回 null 就继续走 just_audio」；那条路已经去掉了。
    expect(code, isNot(contains('失败返回 null')));
    // 也别留下 `hostPlaybackEngineKind() == ... ? ... : null` 这种
    // 「引擎可能不存在」的三元分支——引擎只有一个来源。
    expect(code, isNot(contains('hostPlaybackEngineKind() ==')));
  });

  test('生产代码只通过 engine 访问播放器', () {
    // `handler.player` 拿的是 just_audio 的 AudioPlayer，mpv 引擎下会抛
    // StateError。锁屏同步与桌面媒体会话都踩过这个坑（它们读 position /
    // duration），改成 engine 之后用这条守着别再长回来。
    final pattern = RegExp(r'handler\.player(?!Stream)');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // getter 本体在这里定义，跳过。
      if (entity.path.endsWith('audio_handler.dart')) continue;
      if (pattern.hasMatch(_codeOnly(entity.path))) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: '改用 handler.engine');
  });
}
