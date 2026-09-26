import 'package:flutter_test/flutter_test.dart';
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
}
