import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_handler.dart';

void main() {
  test('silence keepalive is Apple-only', () {
    // 鸿蒙的 just_audio 移植没有实现 silence 源类型（decodeAudioSource 直接
    // 抛 "Unknown AudioSource type: silence"），Windows 也不支持；把静音
    // 保活限制在 iOS/macOS，避免每次手动切歌先走一次必然失败的 setAudioSource。
    expect(
      AudioHandlerPlatformDefaults.host.useSilenceKeepalive,
      Platform.isIOS || Platform.isMacOS,
    );
  });

  test('windows streams local files through the proxy', () {
    expect(
      AudioHandlerPlatformDefaults.host.streamLocalFiles,
      Platform.isWindows,
    );
  });
}
