// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_session_config.dart';

void main() {
  test('共用会话配置始终是 music/playback', () {
    final configuration = musicAudioSessionConfiguration();

    // 会话被写成 playAndRecord 时，Apple 平台会把播放送进语音通道
    // （AEC + 自动增益），听感变空、音量忽大忽小。这里钉住类别。
    expect(configuration.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(configuration.avAudioSessionMode, AVAudioSessionMode.defaultMode);
    // 导航播报压低音量而不是直接暂停。
    expect(
      configuration.androidAudioFocusGainType,
      AndroidAudioFocusGainType.gainTransientMayDuck,
    );
    expect(configuration.androidWillPauseWhenDucked, isFalse);
  });
}
