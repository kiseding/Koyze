import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/compact_high_resolution_scale.dart';

void main() {
  test('phone, desktop, and normal tablet densities stay unchanged', () {
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.android,
        logicalSize: const Size(392, 852),
        devicePixelRatio: 3,
      ),
      1,
    );
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.iOS,
        logicalSize: const Size(1920, 1080),
        devicePixelRatio: 1,
      ),
      1,
    );
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.android,
        logicalSize: const Size(800, 1280),
        devicePixelRatio: 2,
      ),
      1,
    );
  });

  test('under-reported car head unit density enlarges the interface', () {
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.android,
        logicalSize: const Size(1920, 1080),
        devicePixelRatio: 1,
      ),
      closeTo(2.0769, 0.001),
    );
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.android,
        logicalSize: const Size(1280, 720),
        devicePixelRatio: 1,
      ),
      closeTo(1.3846, 0.001),
    );
    expect(
      compactHighResolutionScale(
        platform: TargetPlatform.android,
        logicalSize: const Size(2560, 1440),
        devicePixelRatio: 1,
      ),
      2.2,
    );
  });
}
