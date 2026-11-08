import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/presentation/word_motion.dart';

void main() {
  group('solveWordMotion', () {
    test('词开始前不动', () {
      final motion = solveWordMotion(
        positionMs: 500,
        wordStartMs: 1000,
        wordEndMs: 2000,
        isEmphasized: false,
      );
      expect(motion.offsetEm, 0);
      expect(motion.scale, 1);
    });

    test('词开始后上浮 0.05em', () {
      final motion = solveWordMotion(
        positionMs: 2000,
        wordStartMs: 1000,
        wordEndMs: 2000,
        isEmphasized: false,
      );
      expect(motion.offsetEm, closeTo(-0.05, 1e-6));
    });

    test('强调词在时间窗中点放大且带辉光', () {
      final mid = solveWordMotion(
        positionMs: 1500,
        wordStartMs: 1000,
        wordEndMs: 3000,
        isEmphasized: true,
      );
      expect(mid.scale, greaterThan(1.0));
      expect(mid.glowAlpha, greaterThan(0));
    });

    test('强调结束后回到常态', () {
      final after = solveWordMotion(
        positionMs: 3000,
        wordStartMs: 1000,
        wordEndMs: 3000,
        isEmphasized: true,
      );
      expect(after.scale, closeTo(1.0, 1e-6));
      expect(after.glowAlpha, closeTo(0, 1e-6));
    });
  });

  group('shouldEmphasize', () {
    test('短词不强调', () {
      expect(
        shouldEmphasize(durationMs: 400, text: 'la'),
        isFalse,
      );
    });

    test('中文长字强调', () {
      expect(shouldEmphasize(durationMs: 1200, text: '沉'), isTrue);
    });

    test('英文长单词超过七个字母不强调', () {
      expect(
        shouldEmphasize(durationMs: 1500, text: 'extraordinary'),
        isFalse,
      );
      expect(shouldEmphasize(durationMs: 1500, text: 'shizumu'), isTrue);
    });
  });

  group('CubicBezierEasing', () {
    test('两端固定', () {
      final easing = CubicBezierEasing(0.2, 0.4, 0.58, 1.0);
      expect(easing.transform(0), 0);
      expect(easing.transform(1), 1);
    });

    test('中段单调', () {
      final easing = CubicBezierEasing(0.3, 0.0, 0.58, 1.0);
      var last = -1.0;
      for (var x = 0.0; x <= 1.0; x += 0.1) {
        final y = easing.transform(x);
        expect(y, greaterThanOrEqualTo(last - 1e-9));
        last = y;
      }
    });
  });
}
