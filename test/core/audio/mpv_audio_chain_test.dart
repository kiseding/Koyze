import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/mpv_audio_chain.dart';

/// 记录每次成功写入的假写入器。
///
/// [failuresLeft] 让前 N 次写入抛错，用来验证「silenceremove 不被支持时
/// 降级」这条路径——真实场景里是 filter 名字不被这份 libmpv 认识，每次
/// 都会失败，但降级后**不再**把跳过静音放进链路，所以重试会成功。
class _RecordingWriter implements MpvAfWriter {
  _RecordingWriter({this.failuresLeft = 0});

  final List<List<String>> writes = <List<String>>[];
  int failuresLeft;

  @override
  Future<void> writeAf(List<String> filters) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('filter not found');
    }
    writes.add(List<String>.of(filters));
  }
}

void main() {
  group('buildMpvSkipSilenceFilters', () {
    test('关闭时不挂滤镜', () {
      expect(buildMpvSkipSilenceFilters(enabled: false), isEmpty);
    });

    test('开启时只裁开头，不裁中间', () {
      final filters = buildMpvSkipSilenceFilters();
      expect(filters, hasLength(1));
      final filter = filters.single;
      // 只裁开头是硬约束：中途裁剪会让输出时间轴短于解复用器，
      // 进度条从那一刻起持续落后，seek 也会落错位置。
      expect(filter, contains('start_periods=1'));
      expect(filter, isNot(contains('stop_periods')));
    });

    test('保留 100ms 静音，避免削掉起振', () {
      // 直接贴到波形前沿会听成「啪」的一下，留一点余量。
      expect(
        buildMpvSkipSilenceFilters().single,
        contains('start_silence=0.1'),
      );
    });

    test('阈值约 -50 dBFS，不会被底噪误触发', () {
      // CD 转录的底噪通常在 -60..-70 dB，必须低于阈值；而 -50 dB 也远高于
      // 24bit 母带的极低电平段落，不会把正常弱音当静音切掉。
      final filter = buildMpvSkipSilenceFilters().single;
      expect(filter, contains('start_threshold=0.00316'));
      expect(filter, contains('detection=rms'));
    });
  });

  group('composeMpvFilterChain', () {
    test('跳过静音排在均衡器之前', () {
      // 顺序有语义：跳过静音必须在均衡器抬过噪声基底之前看到原始信号，
      // 否则 -50 dB 的静音会被 +12 dB 低频增益抬到 -38 dB，判不出来。
      final chain = composeMpvFilterChain(
        skipSilence: const ['silenceremove=x'],
        equalizer: const ['equalizer=f=60:g=6'],
      );
      expect(chain, <String>['silenceremove=x', 'equalizer=f=60:g=6']);
    });

    test('降级时不包含跳过静音，但保留均衡器', () {
      final chain = composeMpvFilterChain(
        skipSilence: const ['silenceremove=x'],
        equalizer: const ['equalizer=f=60:g=6'],
        skipSilenceDegraded: true,
      );
      expect(chain, <String>['equalizer=f=60:g=6']);
    });

    test('全空时返回空列表，避免挂一条无意义的链路', () {
      expect(
        composeMpvFilterChain(skipSilence: const [], equalizer: const []),
        isEmpty,
      );
    });

    test('只有均衡器时结果与旧行为一致', () {
      final chain = composeMpvFilterChain(
        skipSilence: const [],
        equalizer: const ['eq1', 'eq2'],
      );
      expect(chain, <String>['eq1', 'eq2']);
    });
  });

  group('MpvAudioChain', () {
    test('两个写者共用一条链路，谁也不抹掉谁', () async {
      // 回归守卫：曾经均衡器和跳过静音各写各的 `af`，后写的把前一个抹掉，
      // 表现为「开了跳过静音均衡器就失效」。
      final writer = _RecordingWriter();
      final chain = MpvAudioChain(writer);

      chain.setEqualizer(const ['eq=6']);
      chain.setSkipSilence(const ['silence']);
      await chain.settled;

      expect(writer.writes, isNotEmpty);
      // 最后一次写入必须同时含两者，且跳过静音在前。
      expect(writer.writes.last, <String>['silence', 'eq=6']);
    });

    test('只调整均衡器时跳过静音仍在链路里', () async {
      final writer = _RecordingWriter();
      final chain = MpvAudioChain(writer);

      chain.setSkipSilence(const ['silence']);
      await chain.settled;
      chain.setEqualizer(const ['eq=3']);
      await chain.settled;
      chain.setEqualizer(const ['eq=9']);
      await chain.settled;

      expect(writer.writes.last, <String>['silence', 'eq=9']);
    });

    test('相同链路不重复写入', () async {
      final writer = _RecordingWriter();
      final chain = MpvAudioChain(writer, debounce: Duration.zero);

      chain.setEqualizer(const ['eq=6']);
      await chain.settled;
      chain.setEqualizer(const ['eq=6']);
      await chain.settled;

      expect(writer.writes, hasLength(1));
    });

    test('silenceremove 失败时降级关闭它，保住均衡器', () async {
      // 跳过静音是次要特性，不该因为它把用户调过的曲线一起拖死。
      // 第一次写入（含 silenceremove）失败，降级重试只含均衡器。
      final writer = _RecordingWriter(failuresLeft: 1);
      final chain = MpvAudioChain(writer);

      chain.setEqualizer(const ['eq=6']);
      chain.setSkipSilence(const ['silence']);
      await chain.settled;

      expect(chain.skipSilenceDegraded, isTrue);
      expect(chain.filters, <String>['eq=6']);
      expect(writer.writes.last, <String>['eq=6']);
    });

    test('降级后不再把跳过静音放回链路', () async {
      final writer = _RecordingWriter(failuresLeft: 1);
      final chain = MpvAudioChain(writer);
      chain.setSkipSilence(const ['silence']);
      await chain.settled;
      expect(chain.skipSilenceDegraded, isTrue);

      // 用户再拨一次开关，不该重新引入会失败的滤镜。
      chain.setSkipSilence(const ['silence']);
      await chain.settled;
      expect(chain.filters, isEmpty);
    });

    test('dispose 后不再写入', () async {
      final writer = _RecordingWriter();
      final chain = MpvAudioChain(writer);
      chain.setEqualizer(const ['eq=6']);
      await chain.settled;
      final before = writer.writes.length;

      await chain.dispose();
      chain.setEqualizer(const ['eq=9']);
      await Future<void>.delayed(Duration.zero);
      expect(writer.writes, hasLength(before));
    });
  });
}