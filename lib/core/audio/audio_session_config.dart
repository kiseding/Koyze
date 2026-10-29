// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:audio_session/audio_session.dart';

/// 全应用共用的「播放音乐」会话配置。
///
/// 抽成函数是为了有一个可断言的单一来源：会话类别一旦被写成别的值，
/// Android 上表现为抢焦点、iOS 上表现为输出被语音通道接管，都是很难从
/// 现象反推的故障，所以不放在启动流程的匿名参数里。
AudioSessionConfiguration musicAudioSessionConfiguration() =>
    const AudioSessionConfiguration.music().copyWith(
      // 导航播报之类的短暂闪避：压低音量而不是直接暂停。
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    );
