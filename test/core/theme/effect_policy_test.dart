import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/performance/low_memory.dart';
import 'package:koyze/core/theme/effect_policy.dart';

/// 在指定无障碍偏好下读一次判定结果。
Future<bool> _read(
  WidgetTester tester, {
  bool highContrast = false,
  bool disableAnimations = false,
}) async {
  late bool result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            disableAnimations: disableAnimations,
          ),
          child: Builder(
            builder: (inner) {
              result = prefersFlatSurfaces(inner);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  return result;
}

void main() {
  tearDown(() => LowMemory.active = false);

  testWidgets('默认设置不动材质', (tester) async {
    expect(await _read(tester), isFalse);
  });

  testWidgets('增强对比度时退实色', (tester) async {
    expect(await _read(tester, highContrast: true), isTrue);
  });

  testWidgets('系统关掉动画时退实色', (tester) async {
    expect(await _read(tester, disableAnimations: true), isTrue);
  });

  testWidgets('应用内关掉特效时退实色', (tester) async {
    LowMemory.active = true;
    expect(await _read(tester), isTrue);
  });

  testWidgets('没有 MediaQuery 时按不降级处理', (tester) async {
    late bool result;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            result = prefersFlatSurfaces(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(result, isFalse);
  });
}
