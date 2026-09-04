import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bottom chrome preserves mini-player shadow clearance', () {
    final source = File(
      'lib/features/home/presentation/main_scaffold.dart',
    ).readAsStringSync();

    expect(source, contains('bottomInset == 0 ? 2.0 : 0.0'));
    expect(source, contains('final navHeight = 36.0'));
    expect(source, contains('const miniGap = 11.0'));
    expect(source, contains('bottomInset == 0 ? 11.0 : 0.0'));
    expect(
      source,
      contains(
        'bottomInset == 0\n'
        '        ? navHeight + 16 + bottomClearance + miniGap',
      ),
    );
    expect(source, contains('bottom: miniBottom'));
    expect(source, contains('bottom: bottomClearance'));
    expect(source, contains('height: height + 16'));
    expect(source, contains('height: height,'));
    expect(source, contains('GlassSurface('));
    expect(source, contains('style: AppGlassStyle.bar'));
    expect(source, contains('fade: AppGlassFade.up'));
  });
}
