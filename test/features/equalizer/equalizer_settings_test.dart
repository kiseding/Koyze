import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/features/equalizer/domain/equalizer_preset.dart';
import 'package:koyze/features/equalizer/domain/equalizer_settings.dart';

/// Android 上最常见的 5 段布局。
const List<double> _fiveBands = <double>[60, 230, 910, 3600, 14000];

/// 部分设备暴露的 10 段布局。
const List<double> _tenBands = <double>[
  32,
  64,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

const EqualizerBandLayout _fiveBandLayout = EqualizerBandLayout(
  minDecibels: -15,
  maxDecibels: 15,
  centerFrequencies: _fiveBands,
);

const EqualizerBandLayout _tenBandLayout = EqualizerBandLayout(
  minDecibels: -15,
  maxDecibels: 15,
  centerFrequencies: _tenBands,
);

void main() {
  group('预设曲线', () {
    test('每个预设的 id 唯一、控制点按频率升序', () {
      final ids = equalizerPresets.map((preset) => preset.id).toList();
      expect(ids.toSet().length, ids.length, reason: '预设 id 不能重复');
      for (final preset in equalizerPresets) {
        expect(preset.curve.length, greaterThanOrEqualTo(2));
        for (var i = 1; i < preset.curve.length; i++) {
          expect(
            preset.curve[i].frequencyHz,
            greaterThan(preset.curve[i - 1].frequencyHz),
            reason: '${preset.id} 的控制点必须按频率升序',
          );
        }
      }
    });

    test('原声预设处处为 0 dB', () {
      final flat = equalizerPresetById('flat')!;
      for (final frequency in <double>[20, 60, 500, 3600, 14000, 20000]) {
        expect(flat.gainAt(frequency), 0);
      }
    });

    test('控制点处取到预设值，并按峰值对齐 0 dB', () {
      final bass = equalizerPresetById('bass')!;
      expect(bass.gainAt(60), 4);
      expect(bass.gainAt(230), 2.5);
      expect(bass.gainsFor(_fiveBands), <double>[0, -1.5, -4, -5, -5.5]);
    });

    test('相邻控制点之间按对数频率线性插值', () {
      final bass = equalizerPresetById('bass')!;
      // 60Hz(4dB) 与 230Hz(2.5dB) 的几何中点上应恰好取到 3.25dB。
      final geometricMean = math.sqrt(60 * 230);
      expect(bass.gainAt(geometricMean), closeTo(3.25, 1e-9));
      // 线性频率轴的 145Hz 在对数轴上偏高频一侧，取值必须低于线性插值。
      expect(bass.gainAt((60 + 230) / 2), lessThan(3.25));
    });

    test('两端之外取端点值', () {
      final treble = equalizerPresetById('treble')!;
      expect(treble.gainAt(10), -1.5); // 低于最低控制点 60Hz
      expect(treble.gainAt(24000), 4); // 高于最高控制点 14kHz
      expect(treble.gainAt(0), -1.5); // 非法频率不抛异常
    });

    test('所有预设在任何采样点都不超过 ±12 dB', () {
      for (final preset in equalizerPresets) {
        for (var frequency = 20.0; frequency <= 20000; frequency *= 1.1) {
          final gain = preset.gainAt(frequency);
          expect(
            gain.abs(),
            lessThanOrEqualTo(12),
            reason: '${preset.id} 在 ${frequency.round()}Hz 超出范围',
          );
        }
      }
    });

    test('同一曲线可采样到 5 段与 10 段两种布局', () {
      final rock = equalizerPresetById('rock')!;
      expect(rock.gainsFor(_fiveBands).length, 5);
      expect(rock.gainsFor(_tenBands).length, 10);
      // 低频段在两种布局下取到的值应当接近（都落在 60Hz 控制点附近）。
      // 采样后削峰：摇滚 60Hz 是峰值，施加值为 0 dB。
      expect(rock.gainsFor(_fiveBands).first, closeTo(0, 0.5));
      expect(rock.gainsFor(_tenBands).first, closeTo(0, 0.5));
    });

    test('未知 id 的标签回落到自定义', () {
      expect(equalizerPresetLabel('bass'), '低音增强');
      expect(equalizerPresetLabel(kCustomPresetId), '自定义');
      expect(equalizerPresetLabel('nope'), '自定义');
      expect(equalizerPresetById('nope'), isNull);
    });
  });

  group('EqualizerSettings', () {
    test('默认关闭、原声、无增益', () {
      const settings = EqualizerSettings();
      expect(settings.enabled, isFalse);
      expect(settings.presetId, kDefaultPresetId);
      expect(settings.gains, isEmpty);
      expect(settings.isCustom, isFalse);
      expect(settings.presetLabel, '原声');
    });

    test('段数一致时沿用保存的增益', () {
      const settings = EqualizerSettings(
        presetId: kCustomPresetId,
        gains: <double>[1, 2, 3, 4, 5],
      );
      expect(settings.gainsFor(_fiveBandLayout), <double>[1, 2, 3, 4, 5]);
      expect(settings.isCustom, isTrue);
    });

    test('段数不一致时回落到预设曲线', () {
      const settings = EqualizerSettings(
        presetId: 'bass',
        gains: <double>[6, 4, 1, 0, 0],
      );
      final gains = settings.gainsFor(_tenBandLayout);
      expect(gains.length, 10);
      expect(gains.first, closeTo(0, 0.5));
      expect(gains.last, closeTo(-5.5, 0.5));
    });

    test('段数不一致且为自定义时视为原声', () {
      const settings = EqualizerSettings(
        presetId: kCustomPresetId,
        gains: <double>[6, 4, 1, 0, 0],
      );
      expect(settings.gainsFor(_tenBandLayout), List<double>.filled(10, 0));
    });

    test('JSON 往返保持状态', () {
      const settings = EqualizerSettings(
        enabled: true,
        presetId: 'rock',
        gains: <double>[-1, 0.5, 2],
      );
      final restored = EqualizerSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.gains, <double>[-1, 0.5, 2]);
    });

    test('损坏或缺失字段回落到默认值', () {
      expect(EqualizerSettings.fromJson(<String, dynamic>{}).enabled, isFalse);
      expect(
        EqualizerSettings.fromJson(<String, dynamic>{}).presetId,
        kDefaultPresetId,
      );

      final restored = EqualizerSettings.fromJson(<String, dynamic>{
        'enabled': 'yes',
        'preset': '',
        'gains': <dynamic>[1, 'x', null, 2.5],
      });
      expect(restored.enabled, isFalse, reason: '非布尔值不当作开启');
      expect(restored.presetId, kDefaultPresetId);
      expect(restored.gains, <double>[1, 2.5], reason: '非数值项被丢弃');
    });

    test('同一份数据相等、不同增益不相等', () {
      const a = EqualizerSettings(enabled: true, gains: <double>[1, 2]);
      const b = EqualizerSettings(enabled: true, gains: <double>[1, 2]);
      const c = EqualizerSettings(enabled: true, gains: <double>[1, 3]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('gainsForPreset 遇到未知预设返回全 0', () {
      expect(
        gainsForPreset(kCustomPresetId, _fiveBands),
        List<double>.filled(5, 0),
      );
    });

    test('命名预设忽略已保存的旧正向增益，按当前曲线重采样', () {
      const settings = EqualizerSettings(
        presetId: 'bass',
        gains: <double>[6, 4, 1, 0, 0],
      );
      expect(settings.gainsFor(_fiveBandLayout), <double>[
        0,
        -1.5,
        -4,
        -5,
        -5.5,
      ]);
    });
  });
}
