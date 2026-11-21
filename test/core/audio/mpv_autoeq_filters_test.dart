import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/audio/mpv_audio_chain.dart';
import 'package:koyze/core/audio/mpv_equalizer_bridge.dart';
import 'package:koyze/features/equalizer/domain/autoeq.dart';

AutoEqBiquad _biquad({
  String type = 'PK',
  double frequencyHz = 1000,
  double gainDb = 6,
  double q = 1.41,
  bool enabled = true,
}) => AutoEqBiquad(
  type: type,
  frequencyHz: frequencyHz,
  gainDb: gainDb,
  q: q,
  enabled: enabled,
);

void main() {
  group('biquadWidthOctaves', () {
    test('Q=1.41 恰好是一个倍频程', () {
      // 这是 Q 与倍频程带宽的换算基准点：q = 1/(2·sinh(ln2/2 · BW))，
      // BW=1 时解出来的 q 就是 1.4142。写错一个常数会整体偏移。
      expect(biquadWidthOctaves(1.414213562), closeTo(1.0, 0.01));
    });

    test('Q 越低，覆盖的倍频程越宽', () {
      // 听感对应关系：Q 低 = 影响范围宽（像调总音量），Q 高 = 窄（像削尖峰）。
      final wide = biquadWidthOctaves(0.5);
      final narrow = biquadWidthOctaves(6.0);
      expect(wide, greaterThan(narrow));
    });

    test('Q=0.707 接近两个倍频程', () {
      expect(biquadWidthOctaves(0.70710678), closeTo(1.93, 0.05));
    });

    test('非法 Q 值退回 1 倍频程而不是写出 NaN', () {
      expect(biquadWidthOctaves(0), 1);
      expect(biquadWidthOctaves(-2), 1);
      expect(biquadWidthOctaves(double.nan), 1);
      expect(biquadWidthOctaves(double.infinity), 1);
    });

    test('结果被夹在 0.1~4 倍频程，不会宽到等于整体音量变化', () {
      expect(biquadWidthOctaves(1000), greaterThanOrEqualTo(0.1));
      expect(biquadWidthOctaves(0.001), lessThanOrEqualTo(4));
    });
  });

  group('buildMpvAutoEqFilters', () {
    test('关闭时不挂任何滤镜', () {
      expect(
        buildMpvAutoEqFilters(enabled: false, biquads: [_biquad()]),
        isEmpty,
      );
    });

    test('Preamp 排在所有滤波器之前', () {
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(frequencyHz: 105, gainDb: 5.5)],
        preampDb: -6.2,
      );
      // 顺序有语义：Preamp 是给后面叠加出的峰值留的余量，放后面就变成
      // 「先削波再衰减」，削掉的信息回不来。
      expect(filters.first, startsWith('volume='));
      expect(filters.first, contains('-6.2dB'));
      expect(filters[1], contains('equalizer='));
    });

    test('Preamp 接近 0 时省掉这个滤镜', () {
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad()],
        preampDb: 0.01,
      );
      expect(filters.any((f) => f.startsWith('volume=')), isFalse);
    });

    test('每个滤波器独立下发，中心频率保持原值', () {
      // 这里就是「不降采样」的核心：AutoEQ 文件里 3200 Hz 的窄带修正
      // 必须还是 3200 Hz，而不是被抹进 910/3600 这两个固定频段。
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [
          _biquad(frequencyHz: 3200, gainDb: -4, q: 4),
          _biquad(frequencyHz: 105, gainDb: 5.5, q: 0.7),
        ],
      );
      expect(filters, hasLength(2));
      expect(filters[0], contains('f=3200'));
      expect(filters[1], contains('f=105'));
    });

    test('Q 值被换算成倍频程带宽，而不是丢掉', () {
      final sharp = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(q: 4)],
      ).single;
      final broad = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(q: 0.7)],
      ).single;
      final sharpWidth = double.parse(
        RegExp(r'width=([0-9.]+)').firstMatch(sharp)!.group(1)!,
      );
      final broadWidth = double.parse(
        RegExp(r'width=([0-9.]+)').firstMatch(broad)!.group(1)!,
      );
      expect(sharpWidth, lessThan(broadWidth));
    });

    test('架式滤波器用 lowshelf / highshelf，峰值用 equalizer', () {
      String nameOf(String type) => buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(type: type)],
      ).single.split('=').first;

      expect(nameOf('LS'), 'lowshelf');
      expect(nameOf('LSC'), 'lowshelf');
      expect(nameOf('HS'), 'highshelf');
      expect(nameOf('HSC'), 'highshelf');
      expect(nameOf('PK'), 'equalizer');
    });

    test('被标记 OFF 的滤波器不下发', () {
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [
          _biquad(frequencyHz: 100, enabled: false),
          _biquad(frequencyHz: 200),
        ],
      );
      expect(filters, hasLength(1));
      expect(filters.single, contains('f=200'));
    });

    test('贴着 0 dB 的滤波器被跳过，省掉无意义的双二阶运算', () {
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(gainDb: 0.01)],
      );
      expect(filters, isEmpty);
    });

    test('频率被夹在可听范围内，不会写出 0 或超出 Nyquist', () {
      final low = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(frequencyHz: 1)],
      ).single;
      final high = buildMpvAutoEqFilters(
        enabled: true,
        biquads: [_biquad(frequencyHz: 96000)],
      ).single;
      expect(low, contains('f=10'));
      expect(high, contains('f=20000'));
    });
  });

  group('AutoEQ 从文件到滤镜的完整链路', () {
    const parametric = '''
Preamp: -6.2 dB
Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 3: ON PK Fc 3200 Hz Gain -4.0 dB Q 4.00
''';

    test('ParametricEQ 保留原始滤波器与 Preamp', () {
      final profile = parseAutoEq(parametric, name: 'Test HP');
      expect(profile, isNotNull);
      expect(profile!.preampDb, closeTo(-6.2, 0.01));
      expect(profile.filters, hasLength(3));

      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: profile.biquads,
        preampDb: profile.preampDb,
      );
      // 1 条 Preamp + 3 条滤波器。
      expect(filters, hasLength(4));
      expect(filters.first, contains('-6.2dB'));
      expect(filters[1], contains('f=105'));
      expect(filters[2], contains('lowshelf'));
      expect(filters[3], contains('f=3200'));
    });

    test('解析出的 Q 值在滤镜里真的生效，而不是全按同一个宽度', () {
      final profile = parseAutoEq(parametric, name: 'Test HP')!;
      final filters = buildMpvAutoEqFilters(
        enabled: true,
        biquads: profile.biquads,
      );
      // Q 0.70 与 Q 4.00 的宽度必须不同，否则等于把 Q 丢了。
      final widths = filters
          .map((f) => RegExp(r'width=([0-9.]+)').firstMatch(f)?.group(1))
          .whereType<String>()
          .map(double.parse)
          .toList();
      expect(widths.toSet(), hasLength(greaterThan(1)));
    });

    test('GraphicEQ 没有滤波器，只能退回固定频段', () {
      final profile = parseAutoEq(
        'GraphicEQ: 20 -3.1; 100 -1.0; 1000 0.0; 10000 2.0',
        name: 'Graphic',
      );
      expect(profile, isNotNull);
      expect(profile!.biquads, isEmpty);
      // 曲线仍然可用，所以画图与降级路径都不受影响。
      expect(profile.curve, hasLength(4));
    });

    test('曲线与滤波器描述的是同一条响应', () {
      // 曲线是把滤波器响应采样到 48 个点，二者在滤波器中心频率处必须
      // 大致吻合（含 Preamp）。差太多说明 biquad 系数或采样逻辑写错了。
      final profile = parseAutoEq(parametric, name: 'Test HP')!;
      final point = profile.curve.firstWhere(
        (p) => p.frequencyHz > 80 && p.frequencyHz < 140,
      );
      final direct = profile.filters
              .map((f) => f.gainAt(point.frequencyHz))
              .fold(0.0, (a, b) => a + b) +
          profile.preampDb;
      expect(point.gainDb, closeTo(direct, 0.01));
    });
  });

  group('增强项滤镜', () {
    test('交叉馈送关闭时不挂滤镜', () {
      expect(buildMpvCrossfeedFilters(enabled: false), isEmpty);
    });

    test('交叉馈送强度被夹到 0~1，非法值退回默认', () {
      expect(
        buildMpvCrossfeedFilters(enabled: true, strength: 5).single,
        contains('strength=1'),
      );
      expect(
        buildMpvCrossfeedFilters(enabled: true, strength: -3).single,
        contains('strength=0'),
      );
      expect(
        buildMpvCrossfeedFilters(
          enabled: true,
          strength: double.nan,
        ).single,
        contains('strength=0.35'),
      );
    });

    test('响度均衡用流式的 dynaudnorm，而不是双 pass 的 loudnorm', () {
      // loudnorm 在 seek 之后要重新测量，表现为「跳一下音量」；这里刻意
      // 选了纯流式的 dynaudnorm。
      final filter = buildMpvLoudnessFilters(enabled: true).single;
      expect(filter, contains('dynaudnorm'));
      expect(filter, isNot(contains('loudnorm')));
    });

    test('限幅器默认关闭自动电平补偿', () {
      // level=1 会在限幅后把整体音量补回来，让安静段落被抬起来，
      // 在音乐播放里听感更差。
      final filter = buildMpvLimiterFilters(enabled: true).single;
      expect(filter, contains('level=0'));
      expect(filter, contains('alimiter'));
    });

    test('限幅天花板被夹在 0.5~1.0', () {
      expect(
        buildMpvLimiterFilters(enabled: true, ceiling: 2).single,
        contains('limit=1'),
      );
      expect(
        buildMpvLimiterFilters(enabled: true, ceiling: 0.1).single,
        contains('limit=0.5'),
      );
    });
  });

  group('增强项在链路里的位置', () {
    test('完整链路顺序：跳过静音 → 均衡器 → 交叉馈送 → 响度 → 限幅', () {
      final chain = composeMpvFilterChain(
        skipSilence: const ['silence'],
        equalizer: const ['eq'],
        crossfeed: const ['xf'],
        loudness: const ['loud'],
        limiter: const ['limit'],
      );
      expect(chain, const ['silence', 'eq', 'xf', 'loud', 'limit']);
    });

    test('限幅器永远排在最后', () {
      // 放中间就管不到后面的增益，等于白挂。
      final chain = composeMpvFilterChain(
        skipSilence: const [],
        equalizer: const ['eq'],
        crossfeed: const ['xf'],
        loudness: const ['loud'],
        limiter: const ['limit'],
      );
      expect(chain.last, 'limit');
    });
  });

  group('MpvAudioChain 的可选环节降级', () {
    test('交叉馈送不被支持时只放弃它，均衡器与限幅留着', () async {
      final writer = _FailOnceWriter(failuresLeft: 1);
      final chain = MpvAudioChain(writer, debounce: Duration.zero);
      chain.setEqualizer(const ['eq']);
      chain.setCrossfeed(const ['xf']);
      chain.setLimiter(const ['limit']);
      await chain.settled;

      expect(chain.filters, const ['eq', 'limit']);
      expect(writer.writes.last, const ['eq', 'limit']);
    });

    test('按可牺牲程度依次降级，均衡器永不放弃', () async {
      // 四个可选环节全挂上、每次写入都失败：只应该降级三次（xf/loud/limit
      // 与 silence），均衡器始终在链里。
      final writer = _FailOnceWriter(failuresLeft: 4);
      final chain = MpvAudioChain(writer, debounce: Duration.zero);
      chain.setEqualizer(const ['eq']);
      chain.setCrossfeed(const ['xf']);
      chain.setLoudness(const ['loud']);
      chain.setLimiter(const ['limit']);
      chain.setSkipSilence(const ['silence']);
      await chain.settled;

      expect(chain.filters, const ['eq']);
      expect(writer.writes.last, const ['eq']);
    });
  });
}

/// 前 N 次写入失败的假写入器。
class _FailOnceWriter implements MpvAfWriter {
  _FailOnceWriter({required this.failuresLeft});

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