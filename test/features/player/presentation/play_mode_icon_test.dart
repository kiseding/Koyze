import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('play mode icons keep their intended direction while switching', () {
    final source = File(
      'lib/features/player/presentation/player_screen.dart',
    ).readAsStringSync();
    final strings = File('lib/l10n/app_strings.dart').readAsStringSync();
    final controls = source.substring(
      source.indexOf('tooltip: S.of(context).playMode'),
      source.indexOf('semanticLabel: S.of(context).previous'),
    );
    expect(strings, contains("en ? 'Play mode' : '播放模式'"));
    expect(strings, contains("en ? 'Previous' : '上一首'"));

    expect(controls, contains('AnimatedSwitcher'));
    expect(controls, isNot(contains('AnimatedRotation')));
    expect(source, contains('return Icons.repeat;'));
    expect(source, isNot(contains('return Icons.trending_flat')));
    expect(source, contains('return Icons.shuffle'));
  });
}
