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
      // 平台选择换成品牌色胶囊：链接页与登录页各一处，不再用系统下拉菜单。
      expect(
        RegExp(r'_ImportPlatformSelector\(').allMatches(importDialog).length,
        2,
      );
      expect(importDialog, isNot(contains('DropdownButtonFormField')));
      // 文件页读的是文本歌单，不是音频。
      expect(importDialog, contains('_importPlaylistFile('));
      expect(importDialog, contains('_PlaylistFormatChips'));
      // 登录页不再是禁用占位：按钮直接打开扫码面板，解析逻辑由面板回调。
      expect(importDialog, contains('showPlaylistLoginSheet('));
      expect(importDialog, contains('importAccountPlaylist'));
      expect(importDialog, isNot(contains('platformLoginUnavailableAction')));
      expect(importDialog, isNot(contains('importAccountIntro')));
    },
  );

  test('platform sign-in copy is complete in both locales', () {
    final zh =
        jsonDecode(readSource('lib/l10n/app_zh.arb')) as Map<String, dynamic>;
    final en =
        jsonDecode(readSource('lib/l10n/app_en.arb')) as Map<String, dynamic>;

    // 已经接了扫码登录，原来那套「官方授权未获批」的说明必须一起消失，
    // 否则界面在登录、文案却说不能登录。
    expect(
      zh.keys.where((key) => key.startsWith('platformLoginUnavailable')),
      isEmpty,
    );
    expect(
      en.keys.where((key) => key.startsWith('platformLoginUnavailable')),
      isEmpty,
    );

    final keys =
        zh.keys.where((key) => key.startsWith('playlistLogin')).toList()
          ..sort();
    expect(keys, isNotEmpty);
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final key in keys) {
      expect(en[key], isA<String>(), reason: '英文缺少 $key');
      expect((en[key] as String).trim(), isNotEmpty, reason: '英文 $key 为空');
      expect(
        placeholder
            .allMatches(en[key] as String)
            .map((match) => match[1])
            .toSet(),
        placeholder
            .allMatches(zh[key] as String)
            .map((match) => match[1])
            .toSet(),
        reason: '$key 的占位符中英不一致',
      );
    }

    expect(zh['playlistLoginQrHint'], contains('{app}'));
    expect(zh['playlistLoginIntro'], contains('安全存储'));
    expect(zh['playlistLoginCookieIntro'], contains('kuwo.cn'));
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

  test('排序面板标题与更多操作面板对齐，不再多一条抓手占位', () {
    final source = readSource(
      'lib/features/playlist/presentation/playlist_screen.dart',
    );
    final sortMenu = source.substring(
      source.indexOf('void _showSortMenu('),
      source.indexOf('Future<bool> _importPlaylistFile('),
    );

    expect(sortMenu, contains('KoyzeSheetTitle('));
    expect(sortMenu, contains('KoyzeSheetAction('));
    expect(
      sortMenu,
      isNot(contains('KoyzeSheetGrabber')),
      reason: '标题前再垫 12pt 会比其它动作面板矮一截',
    );
  });
}
