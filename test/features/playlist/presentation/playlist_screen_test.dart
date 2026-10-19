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
      source.indexOf('Widget _buildRecommendCard('),
    );

    expect(card, contains('_PresetCard('));
    expect(card, contains("pathParameters: {'playlistId': 'local'}"));
    expect(card, isNot(contains("context.push('/local-music')")));
  });

  test('playlist cards use immediate animated play feedback', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();

    // 五个入口共用一枚 _PresetCard，播放反馈只实现一次；如果哪天又散回
    // 五份手写卡片，这里的计数会先炸。
    expect(RegExp(r'CardPlayButton\(').allMatches(source).length, 1);
    expect(source, contains('class _PresetCard extends StatelessWidget'));
    expect(RegExp(r'return _PresetCard\(').allMatches(source).length, 5);
    expect(source, contains('_BodyPresetGrid'));
    expect(source, contains('_buildSubsonicCard'));
    expect(source, isNot(contains('_BodyNasCard')));
    expect(source, contains("context.push('/subsonic')"));
    expect(source, contains('subsonicLibrarySongsProvider'));
    expect(source, isNot(contains('subsonicPlaylistsProvider')));
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

  test('预设卡的左右内边距跟上下留白取同一个数', () {
    final source = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();
    final card = source.substring(source.indexOf('class _PresetCard'));

    // 图标 38 在高 72 的卡里垂直居中，上下各留 17；左右如果写死 12，
    // 图标就会比上下更贴边——这正是这张卡看起来"歪"的原因。
    expect(card, contains('static const double _height = 72;'));
    expect(card, contains('static const double _iconExtent = 38;'));
    expect(
      card,
      contains(
        'static const double _inset = (_height - _iconExtent) / 2;',
      ),
    );
    expect(card, contains('horizontal: _inset'));
    expect(card, contains('height: _height'));
  });
}
