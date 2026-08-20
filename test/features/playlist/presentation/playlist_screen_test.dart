import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playlist screen does not resize for the keyboard', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();

    expect(source, contains('resizeToAvoidBottomInset: false'));
  });

  test('import dialog guards local state after every async dismissal path', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();
    final importDialog = source.substring(
      source.indexOf('Future<void> _showImportDialog('),
      source.indexOf('void _showPlaylistMoreMenu('),
    );

    // 点击弹窗外空白可关闭（取消导入）。
    expect(importDialog, contains('barrierDismissible: true'));
    expect(
      RegExp(
        r'if \(!ctx\.mounted\) return;\s+setLocal\(\(\) => busy = false\)',
      ).hasMatch(importDialog),
      isTrue,
    );
    expect(
      RegExp(
        r'catch \(e\) \{\s+if \(!ctx\.mounted\) return;\s+setLocal',
      ).hasMatch(importDialog),
      isTrue,
    );
  });

  test('local music card opens the playlist player view', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();
    final card = source.substring(
      source.indexOf('Widget _buildLocalCard('),
      source.indexOf('Widget _buildRecentCard('),
    );

    expect(card, contains('captureExpandRect: true'));
    expect(card, contains("pathParameters: {'playlistId': 'local'}"));
    expect(card, isNot(contains("context.push('/local-music')")));
  });

  test('playlist cards use immediate animated play feedback', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();

    expect(RegExp(r'CardPlayButton\(').allMatches(source).length, 4);
    expect(
      source,
      contains("import '../../../core/widgets/card_play_button.dart';"),
    );
  });

  test('playlist body is lazily built and never spreads full song lists', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ListView.builder('));
    // 全量展开映射是屏幕外内容被构建的根源，必须移除。
    expect(source, isNot(contains('...filteredPlaylists.map')));
    expect(source, isNot(contains('...songHits.map')));
    // 列表主体是轻量描述 + 按索引构建。
    expect(source, contains('_bodyItems('));
    expect(source, contains('_buildBodyItem('));
  });
}
