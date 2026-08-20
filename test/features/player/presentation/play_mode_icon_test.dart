import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('play mode icons keep their intended direction while switching', () {
    final source = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();
    final controls = source.substring(
      source.indexOf("tooltip: '播放模式'"),
      source.indexOf("semanticLabel: '上一首'"),
    );

    expect(controls, contains('AnimatedSwitcher'));
    expect(controls, isNot(contains('AnimatedRotation')));
    expect(source, contains('return Icons.trending_flat'));
    expect(source, contains('return Icons.shuffle'));
  });
}
