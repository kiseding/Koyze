import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sung word lyrics use the theme accent while pending words stay white',
    () {
      final source = File(
        'lib/features/lyric/presentation/lyric_view.dart',
      ).readAsStringSync();

      // 逐字行未唱的字使用前景色（暗色模式下即白色），不再用绿色暗化。
      expect(source, contains('? accent'));
      expect(source, contains('activeColor: accent'));
      expect(
        RegExp(r'line\.hasWordTiming\s*\?\s*primary').hasMatch(source),
        isTrue,
      );
      expect(source, contains('lineColor.withValues(alpha: 0.35)'));
      expect(
        source,
        isNot(contains('activeColor: widget.isFullScreen ? primary')),
      );
    },
  );
}
