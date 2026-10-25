import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';

/// 播放模式是纯状态机：点击循环、图标映射、以及从 handler 发布的
/// repeat/shuffle 反推当前位置。这里直接测行为，不再去源码里找字符串。
void main() {
  group('nextPlayMode', () {
    test('单曲循环 → 顺序 → 随机 → 单曲循环', () {
      expect(nextPlayMode(PlayMode.repeatOne), PlayMode.sequential);
      expect(nextPlayMode(PlayMode.sequential), PlayMode.shuffle);
      expect(nextPlayMode(PlayMode.shuffle), PlayMode.repeatOne);
    });

    test('转一圈回到起点，不丢模式也不多出一个模式', () {
      var mode = PlayMode.repeatOne;
      final visited = <PlayMode>{mode};
      for (var i = 0; i < PlayMode.values.length; i++) {
        mode = nextPlayMode(mode);
        visited.add(mode);
      }
      expect(visited.length, PlayMode.values.length);
      expect(mode, PlayMode.repeatOne);
    });

    test('每个模式都有下一站（无空返回、无自我循环）', () {
      for (final mode in PlayMode.values) {
        final next = nextPlayMode(mode);
        expect(next, isNot(mode), reason: '$mode 点击后必须切到别的模式');
      }
    });
  });

  group('playModeIcon', () {
    test('三种模式对应三个不同的图标', () {
      final icons = PlayMode.values.map(playModeIcon).toList();
      expect(icons.toSet().length, PlayMode.values.length);
    });

    test('图标语义与模式一致', () {
      expect(playModeIcon(PlayMode.repeatOne), Icons.repeat_one);
      expect(playModeIcon(PlayMode.sequential), Icons.repeat);
      expect(playModeIcon(PlayMode.shuffle), Icons.shuffle);
    });

    test('顺序播放不用 trending_flat 之类的方向箭头', () {
      // 曾经用过 trending_flat，语义不对：它是"趋势"不是"列表循环"。
      expect(playModeIcon(PlayMode.sequential), isNot(Icons.trending_flat));
    });
  });

  group('playModeFromPlaybackState', () {
    PlaybackState state({
      AudioServiceShuffleMode shuffle = AudioServiceShuffleMode.none,
      AudioServiceRepeatMode repeat = AudioServiceRepeatMode.none,
    }) {
      return PlaybackState(
        shuffleMode: shuffle,
        repeatMode: repeat,
      );
    }

    test('shuffle=all 优先判定为随机，即使同时开着单曲循环', () {
      expect(
        playModeFromPlaybackState(
          state(
            shuffle: AudioServiceShuffleMode.all,
            repeat: AudioServiceRepeatMode.one,
          ),
        ),
        PlayMode.shuffle,
      );
    });

    test('repeat=one 判定为单曲循环', () {
      expect(
        playModeFromPlaybackState(
          state(repeat: AudioServiceRepeatMode.one),
        ),
        PlayMode.repeatOne,
      );
    });

    test('都没有时是顺序播放', () {
      expect(
        playModeFromPlaybackState(state()),
        PlayMode.sequential,
      );
    });

    test('repeat=all 不算单曲循环', () {
      expect(
        playModeFromPlaybackState(
          state(repeat: AudioServiceRepeatMode.all),
        ),
        PlayMode.sequential,
      );
    });
  });
}
