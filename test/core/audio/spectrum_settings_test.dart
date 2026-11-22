import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:koyze/core/audio/audio_spectrum_factory_native.dart';

// Exercise the upstream PCM-to-FFT algorithm as well as our display mapping.
List<double> _analyze(double hz, double amplitude) {
  const rate = 48000;
  final samples = Float32List.fromList(
    List.generate(
      kSpectrumSettings.fftSize,
      (i) => amplitude * math.sin(2 * math.pi * hz * i / rate),
    ),
  );
  return mapPlayerSpectrumBands(
    BandProcessor(kSpectrumSettings).process(
      PcmFrame(
        samples: samples,
        timestamp: Duration.zero,
        sampleRate: rate,
        channels: 1,
      ),
    )!,
  );
}

void main() {
  group('播放页频谱参数', () {
    test('约 -60 dB 的高频成分能带动右侧，强弱仍可区分', () {
      final soft = _analyze(9000, 0.002);
      final loud = _analyze(9000, 0.008);
      final high = soft.skip(26).reduce(math.max);
      expect(high, greaterThan(0.10));
      expect(loud.skip(26).reduce(math.max), greaterThan(high + 0.10));
      expect(soft.take(26), everyElement(lessThan(0.01)));
    });

    test('底鼓、琴键频段分开，静音不制造动态', () {
      final bass = _analyze(75, 0.1);
      final piano = _analyze(880, 0.1);
      expect(bass.take(9).reduce(math.max), greaterThan(0.4));
      expect(piano.skip(14).take(8).reduce(math.max), greaterThan(0.4));
      expect(bass.skip(26), everyElement(0.0));
      expect(_analyze(0, 0), everyElement(0.0));
    });

    test('内部平滑足够轻，不与 UI 层补间叠加成双重平滑', () {
      final settings = kSpectrumSettings;
      // mpv 内部做一次 EMA，PlayerSpectrumStrip 按帧再做一次指数逼近。
      // 两层都重就把瞬态抹平了，鼓点和铺底听起来、看起来都一样。
      expect(
        settings.attackSmoothing,
        greaterThanOrEqualTo(0.7),
        reason: '内部上升平滑过重会吃掉瞬态，和 UI 层补间叠成双重平滑',
      );
      expect(
        settings.releaseSmoothing,
        greaterThanOrEqualTo(0.25),
        reason: '内部衰减平滑过重会把上一帧的形状拖进下一帧，频段差异糊成一片',
      );
      expect(settings.attackSmoothing, lessThanOrEqualTo(1));
      expect(settings.releaseSmoothing, lessThanOrEqualTo(1));
    });

    test('频段数在窄条上仍然分得清每根柱子', () {
      final settings = kSpectrumSettings;
      // 条宽约 300dp 时，64 段每柱只有 4-5px，相邻频段挤在一起看不出边界。
      expect(
        settings.bandCount,
        lessThanOrEqualTo(48),
        reason:
            '段数过多会让每根柱子窄到无法单独辨认，'
            '「看得出音调不同」首先得「看得出是不同的柱子」',
      );
      expect(settings.bandCount, greaterThanOrEqualTo(16));
    });

    test('频率轴覆盖人耳主要乐音区，且不越过 Nyquist', () {
      final settings = kSpectrumSettings;
      // 上沿收到 16 kHz：大多数乐器的泛音已在此之下，再往上只是空气感，
      // 却要占掉一大截条宽。
      expect(settings.bandLowHz, lessThanOrEqualTo(40));
      expect(settings.bandHighHz, greaterThanOrEqualTo(14000));
      // 44.1k 采样的 Nyquist 是 22.05k；这里留足余量，避免高采样率
      // 之外的源被静默钳到边界上。
      expect(settings.bandHighHz, lessThan(22050));
    });

    test('FFT 尺寸保持 A/V 同步阈值内的分辨率', () {
      final settings = kSpectrumSettings;
      // 2048 点在 48 kHz 下跨 42.7 ms，低于 ~80 ms 的同步阈值；
      // 同时给出约 23 Hz 的频率分辨率，足以分开底鼓与 sub-bass。
      expect(settings.fftSize, 2048);
      expect(settings.overlapFactor, 4);
      expect(settings.emitInterval.inMilliseconds, lessThanOrEqualTo(40));
    });
  });
}
