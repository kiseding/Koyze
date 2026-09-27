import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/motion/motion_tokens.dart';
import 'package:koyze/core/performance/low_memory.dart';

void main() {
  test('4GB and smaller devices simplify visual effects', () {
    expect(isLowMemoryDevice(null), isFalse);
    expect(isLowMemoryDevice(0), isFalse);
    expect(isLowMemoryDevice(3 * 1024 * 1024 * 1024), isTrue);
    expect(isLowMemoryDevice(lowMemoryLimitBytes), isTrue);
    expect(isLowMemoryDevice(4 * 1000 * 1000 * 1000), isTrue);
    expect(isLowMemoryDevice(lowMemoryLimitBytes + 1), isFalse);
    expect(isLowMemoryDevice(6 * 1024 * 1024 * 1024), isFalse);
  });

  test('the effects switch follows memory until the user chooses', () {
    expect(resolveSimplifyEffects(lowMemoryDevice: true, stored: null), isTrue);
    expect(
      resolveSimplifyEffects(lowMemoryDevice: false, stored: null),
      isFalse,
    );
    expect(
      resolveSimplifyEffects(lowMemoryDevice: true, stored: false),
      isFalse,
    );
    expect(
      resolveSimplifyEffects(lowMemoryDevice: false, stored: true),
      isTrue,
    );
  });

  test('the effects switch removes explicit transition time', () {
    LowMemory.active = false;
    addTearDown(() => LowMemory.active = false);
    expect(
      effectsDuration(const Duration(milliseconds: 220)),
      const Duration(milliseconds: 220),
    );
    LowMemory.active = true;
    expect(effectsDuration(const Duration(milliseconds: 220)), Duration.zero);
    final style = effectsAnimationStyle();
    expect(style.duration, Duration.zero);
    expect(style.reverseDuration, Duration.zero);
  });
}
