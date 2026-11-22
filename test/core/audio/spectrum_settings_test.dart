import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_spectrum_factory_native.dart';

/// 频谱条「看不出音调差别」是一类**回归起来毫无声响**的 bug：形状照常
/// 渲染、照常随时间跳动，只是所有柱子高度趋同。它不报错、不掉帧，肉眼
/// 也说不清哪里不对——所以必须把「为什么会趋同」的那几条参数钉住。
void main() {
  group('播放页频谱参数', () {
    test('dB 窗口收窄到音乐的常见动态范围', () {
      final settings = kSpectrumSettings;
      // 默认 -100/-30 是 70 dB 的窗口。流行乐母带基本落在 -45~-8 dB，
      // 压进 70 dB 之后所有频段都挤在中段，相邻柱子的差不到一格像素。
      final window = settings.maxDb - settings.minDb;
      expect(
        window,
        lessThanOrEqualTo(50),
        reason: 'dB 窗口超过 50 会让所有频段挤在同一高度区间，'
            '频谱看起来「一样高」。实际 $window dB '
            '(${settings.minDb} → ${settings.maxDb})',
      );
      expect(settings.maxDb, greaterThan(settings.minDb));
      // 上沿不能压到 -20 以上：那样正常的人声就已经削顶，动态全丢。
      expect(settings.maxDb, lessThanOrEqualTo(-10));
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
        reason: '段数过多会让每根柱子窄到无法单独辨认，'
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