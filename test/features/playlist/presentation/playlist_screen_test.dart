import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../../support/source_text.dart';

void main() {
  test('playlist screen does not resize for the keyboard', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );

    expect(source, contains('resizeToAvoidBottomInset: false'));
  });

  test('import dialog guards local state after every async dismissal path', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );
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

  test(
    'playlist import dialog combines link, file and platform sign-in tabs',
    () {
      final source = readSource(
        'lib/features/playlist/presentation/playlist_screen.dart',
      );
      final importDialog = source.substring(
        source.indexOf('Future<void> _showImportDialog('),
        source.indexOf('void _showPlaylistMoreMenu('),
      );

      expect(source, isNot(contains('semanticLabel: S.of(context).importM3u')));
      expect(importDialog, contains('SegmentedButton<int>'));
      expect(importDialog, contains('importTabLink'));
      expect(importDialog, contains('importTabFile'));
      expect(importDialog, contains('importTabAccount'));
      expect(importDialog, contains('DropdownButtonFormField<String>'));
      expect(importDialog, contains('final imported = await _importM3uFile('));
      expect(importDialog, contains('onPressed: null'));
      expect(importDialog, isNot(contains('importAccountIntro')));
    },
  );

  test('platform sign-in notices match verified official access scopes', () {
    final zh = jsonDecode(readSource('lib/l10n/app_zh.arb')) as Map<String, dynamic>;
    final en = jsonDecode(readSource('lib/l10n/app_en.arb')) as Map<String, dynamic>;

    expect(zh['platformLoginUnavailableQQ'], contains('合作接入和审核'));
    expect(zh['platformLoginUnavailableQQ'], contains('个人开发者'));
    expect(zh['platformLoginUnavailableKuwo'], contains('酷狗 App 的官方信息清单'));
    expect(zh['platformLoginUnavailableKuwo'], contains('第三方开发者'));
    expect(zh['platformLoginUnavailableKugou'], contains('官方小程序'));
    expect(zh['platformLoginUnavailableKugou'], contains('独立 App'));
    expect(zh['platformLoginUnavailableNetease'], contains('ncm-cli'));
    expect(zh['platformLoginUnavailableNetease'], contains('商务接入'));
    expect(en['platformLoginUnavailableQQ'], contains('individual developers'));
    expect(en['platformLoginUnavailableKuwo'], contains('third-party developer'));
    expect(en['platformLoginUnavailableKugou'], contains('mini-app API'));
    expect(en['platformLoginUnavailableNetease'], contains('ncm-cli'));
  });

  test('local music card opens the playlist player view', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );
    final card = source.substring(
      source.indexOf('Widget _buildLocalCard('),
      source.indexOf('Widget _buildRecommendCard('),
    );

    expect(card, contains('_PresetCard('));
    expect(card, contains("pathParameters: {'playlistId': 'local'}"));
    expect(card, isNot(contains("context.push('/local-music')")));
  });

  test('playlist cards use immediate animated play feedback', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );

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
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );

    expect(source, contains('ListView.builder('));
    // 全量展开映射是屏幕外内容被构建的根源，必须移除。
    expect(source, isNot(contains('...filteredPlaylists.map')));
    expect(source, isNot(contains('...songHits.map')));
    // 列表主体是轻量描述 + 按索引构建。
    expect(source, contains('_bodyItems('));
    expect(source, contains('_buildBodyItem('));
  });

  test('预设卡的留白由卡高与图标推出来，四边同一个数', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );
    final card = source.substring(source.indexOf('class _PresetCard'));

    // 图标 52 在 72 高的卡里垂直居中，四边各留 10。原先图标 38、四边 17，
    // 一行五张看下来全是空盒子；留白再涨回去就等于把这条又改回去了。
    expect(card, contains('static const double _height = 72;'));
    expect(card, contains('static const double _iconExtent = 52;'));
    expect(
      card,
      contains('static const double _inset = (_height - _iconExtent) / 2;'),
    );
    expect(card, contains('padding: const EdgeInsets.all(_inset)'));
    expect(card, contains('height: _height'));
    expect((72.0 - 52.0) / 2, 10.0);
  });
}
