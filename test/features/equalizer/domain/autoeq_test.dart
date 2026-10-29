import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_gain.dart';
import 'package:koyze/features/equalizer/domain/autoeq.dart';

const String _parametricEq = '''
Preamp: -6.2 dB
Filter 1: ON PK Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
Filter 3: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.70
Filter 4: OFF PK Fc 1000 Hz Gain 9.9 dB Q 1.00
''';

const String _graphicEq = '''
GraphicEQ: 20 -1.5; 21 -1.5; 22 -1.4; 1000 0.0; 20000 -4.0
''';

void main() {
  group('parseAutoEq parametric', () {
    test('reads preamp and every filter', () {
      final profile = parseAutoEq(_parametricEq, name: 'Sundara');
      expect(profile, isNotNull);
      expect(profile!.name, 'Sundara');
      expect(profile.preampDb, -6.2);
      expect(profile.filters, hasLength(4));
      expect(profile.filters.first.type, 'PK');
      expect(profile.filters.first.frequencyHz, 105);
      expect(profile.filters[1].isLowShelf, isTrue);
      expect(profile.filters[2].isHighShelf, isTrue);
      expect(profile.filters[3].enabled, isFalse);
    });

    test('samples a dense, ascending curve inside the audio band', () {
      final profile = parseAutoEq(_parametricEq, name: 'x')!;
      expect(profile.curve, hasLength(48));
      expect(profile.curve.first.frequencyHz, closeTo(20, 0.001));
      expect(profile.curve.last.frequencyHz, closeTo(20000, 1));
      for (var i = 1; i < profile.curve.length; i++) {
        expect(
          profile.curve[i].frequencyHz,
          greaterThan(profile.curve[i - 1].frequencyHz),
        );
      }
    });

    test('peaking boost peaks at its own centre frequency', () {
      final filter = AutoEqFilter(
        type: 'PK',
        frequencyHz: 1000,
        gainDb: 6,
        q: 1,
      );
      expect(filter.gainAt(1000), closeTo(6, 0.05));
      // 一倍的频偏处已经明显衰减。
      expect(filter.gainAt(2000), lessThan(3));
      expect(filter.gainAt(2000), greaterThan(0));
    });

    test('disabled filter contributes nothing', () {
      const filter = AutoEqFilter(
        type: 'PK',
        frequencyHz: 1000,
        gainDb: 6,
        q: 1,
        enabled: false,
      );
      expect(filter.gainAt(1000), 0);
    });

    test('low shelf lifts the bass, not the treble', () {
      const shelf = AutoEqFilter(
        type: 'LSC',
        frequencyHz: 120,
        gainDb: 5,
        q: 0.7,
      );
      expect(shelf.gainAt(30), greaterThan(4));
      expect(shelf.gainAt(8000), closeTo(0, 0.5));
    });

    test('preamp is folded into the curve', () {
      final withPreamp = parseAutoEq(_parametricEq, name: 'a')!;
      final withoutPreamp = parseAutoEq(
        _parametricEq.replaceFirst('Preamp: -6.2 dB', ''),
        name: 'b',
      )!;
      for (var i = 0; i < withPreamp.curve.length; i++) {
        expect(
          withPreamp.curve[i].gainDb - withoutPreamp.curve[i].gainDb,
          closeTo(-6.2, 0.001),
        );
      }
    });
  });

  group('parseAutoEq graphic', () {
    test('uses the sampled points directly', () {
      final profile = parseAutoEq(_graphicEq, name: 'Graphic')!;
      expect(profile.filters, isEmpty);
      expect(profile.curve, hasLength(5));
      expect(profile.curve.first.frequencyHz, 20);
      expect(profile.curve.first.gainDb, closeTo(-1.5, 0.001));
      expect(profile.curve.last.frequencyHz, 20000);
    });

    test('drops unparsable and non-positive frequencies', () {
      final profile = parseAutoEq(
        'GraphicEQ: 0 -3.0; abc -1; 100 2.0; 200 1.0',
        name: 'x',
      )!;
      expect(profile.curve.map((p) => p.frequencyHz), [100, 200]);
    });

    test('needs at least two usable points', () {
      expect(parseAutoEq('GraphicEQ: 100 2.0', name: 'x'), isNull);
    });
  });

  test('rejects files with no recognisable curve', () {
    expect(parseAutoEq('hello world', name: 'x'), isNull);
    expect(parseAutoEq('', name: 'x'), isNull);
  });

  test('toPreset keeps the name and exposes band gains', () {
    final profile = parseAutoEq(_parametricEq, name: 'Sundara')!;
    final preset = profile.toPreset();
    expect(preset.id, 'autoeq');
    expect(preset.label, 'Sundara');
    // 10 段设备的增益：低频被抬起来，且峰值不超过安全天花板。
    final gains = preset.gainsFor([
      31,
      62,
      125,
      250,
      500,
      1000,
      2000,
      4000,
      8000,
      16000,
    ]);
    expect(gains, hasLength(10));
    for (final gain in gains) {
      expect(gain, lessThanOrEqualTo(kEqualizerPeakCeilingDb + 0.05));
    }
    expect(gains.first, greaterThan(gains.last));
  });
}
