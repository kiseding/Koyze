import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';
import 'package:koyze/features/source_check/domain/source_check_report.dart';

import 'ai_tool_fakes.dart';

Future<Map<String, dynamic>> run(
  AiToolbox toolbox,
  String name, [
  Map<String, dynamic> arguments = const {},
]) async {
  final output = await toolbox.call(
    AiToolCall(id: 'c1', name: name, arguments: arguments),
  );
  return jsonDecode(output) as Map<String, dynamic>;
}

SourceCheckBook checkedBook() => const SourceCheckBook().withReport(
  SourceCheckReport(
    sourceId: 's1',
    sourceName: '源一',
    testedAt: DateTime(2026, 10, 28),
    perPlatform: {
      'tx': SourceCheckPlatformReport(
        platform: 'tx',
        testedAt: DateTime(2026, 10, 28),
        qualities: const {
          'flac': SourceCheckResult(
            platform: 'tx',
            quality: 'flac',
            verdict: SourceCheckVerdict.ok,
            latencyMs: 120,
          ),
        },
      ),
    },
  ),
);

void main() {
  test('search_library returns compact songs and honours the limit', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.searchLibrary, {
      'query': '周杰伦',
      'limit': 1,
    });

    expect(fakes.queries, ['周杰伦']);
    expect(result['songs'], [
      {'id': '1', 'title': '晴天', 'artist': '周杰伦', 'platform': 'tx'},
    ]);
  });

  test('list_playlists marks the built-in playlists', () async {
    final fakes = ToolFakes(playlists: [playlist('p1', '我的收藏', [])]);
    final result = await run(fakes.toolbox(), AiToolbox.listPlaylists);

    expect(result['playlists'], [
      {'id': 'p1', 'name': '我的收藏', 'songs': 0},
      {'id': 'favorites', 'name': '收藏列表', 'songs': 0, 'system': true},
    ]);
  });

  test('get_playlist resolves by name and lists its songs', () async {
    final fakes = ToolFakes(
      playlists: [
        playlist('p1', '我的收藏', [
          song('1', '晴天', '周杰伦'),
          song('2', '夜曲', '周杰伦'),
        ]),
      ],
    );
    final result = await run(fakes.toolbox(), AiToolbox.getPlaylist, {
      'playlist': '我的收藏',
    });

    expect(result['name'], '我的收藏');
    expect(result['total'], 2);
    expect((result['songs'] as List).first['title'], '晴天');
  });

  test('source_status reports the last check per script', () async {
    final fakes = ToolFakes();
    fakes.sources.book = checkedBook();

    final result = await run(fakes.toolbox(), AiToolbox.sourceStatus);
    final sources = result['sources'] as List;

    expect(sources[0], {
      'id': 's1',
      'name': '源一',
      'enabled': true,
      'tested': true,
      'okPlatforms': 1,
      'totalPlatforms': 1,
      'platforms': ['tx'],
    });
    expect(sources[1], {
      'id': 's2',
      'name': '源二',
      'enabled': false,
      'tested': false,
    });
  });

  test(
    'changing tools stay hidden and refuse to run when actions are off',
    () async {
      final fakes = ToolFakes();
      final toolbox = fakes.toolbox(allowActions: false);
      final names = toolbox.specs
          .map((spec) => (spec['function'] as Map)['name'])
          .toList();

      expect(names, contains(AiToolbox.searchLibrary));
      expect(names, isNot(contains(AiToolbox.playSong)));
      expect(names, isNot(contains(AiToolbox.createPlaylistTool)));

      final result = await run(toolbox, AiToolbox.playerControl, {
        'action': 'play',
      });

      expect(result['error'], isNotNull);
      expect(fakes.playback.calls, isEmpty);
    },
  );

  test('play_song resolves the title and starts playback', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.playSong, {
      'title': '晴天',
      'artist': '周杰伦',
    });

    expect((result['playing'] as Map)['title'], '晴天');
    expect(fakes.playback.played.single.name, '晴天');
    expect(fakes.playback.isPlaying, isTrue);
  });

  test(
    'player_control, shuffle and repeat change the playback state',
    () async {
      final fakes = ToolFakes();
      fakes.playback
        ..currentSong = song('1', '晴天', '周杰伦')
        ..isPlaying = true;
      final toolbox = fakes.toolbox();

      await run(toolbox, AiToolbox.playerControl, {'action': 'toggle'});
      expect(fakes.playback.isPlaying, isFalse);

      await run(toolbox, AiToolbox.setPlayMode, {
        'shuffle': true,
        'repeat': 'one',
      });
      expect(fakes.playback.shuffleEnabled, isTrue);
      expect(fakes.playback.repeatMode, 'one');
    },
  );

  test(
    'set_volume clamps the percentage and seek clamps to the track',
    () async {
      final fakes = ToolFakes();
      fakes.playback.currentSong = song(
        '9',
        '长歌',
        '某人',
        duration: const Duration(minutes: 4),
      );
      final toolbox = fakes.toolbox();

      final volume = await run(toolbox, AiToolbox.setVolumeTool, {
        'percent': 150,
      });
      expect(volume['volumePercent'], 100);
      expect(fakes.playback.volume, 1);

      final seek = await run(toolbox, AiToolbox.seekTool, {'percent': 50});
      expect(seek['positionSeconds'], 120);
      expect(fakes.playback.lastSeek, const Duration(minutes: 2));
    },
  );

  test('queue_songs can insert next or append to the end', () async {
    final fakes = ToolFakes();
    final toolbox = fakes.toolbox();

    await run(toolbox, AiToolbox.queueSongs, {
      'songs': [
        {'title': '晴天'},
        {'title': '夜曲'},
      ],
      'position': 'next',
    });

    expect(fakes.playback.enqueued.map((item) => item.name), ['晴天', '夜曲']);
    expect(fakes.playback.calls, contains('enqueueNext'));
  });

  test('create_playlist resolves songs and reports what it skipped', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.createPlaylistTool, {
      'name': '深夜写代码',
      'description': '安静的曲子',
      'songs': [
        {'title': '晴天', 'artist': '周杰伦'},
        {'title': '完全不存在的歌', 'artist': '无名氏'},
      ],
    });

    expect(result['created'], isTrue);
    expect(result['added'], 1);
    expect((result['skipped'] as List).single, '完全不存在的歌 · 无名氏');
    expect(fakes.playlists.items.last.name, '深夜写代码');
  });

  test(
    'add_songs_to_playlist and remove_songs_from_playlist move songs',
    () async {
      final fakes = ToolFakes(
        playlists: [
          playlist('p1', '通勤', [song('2', '夜曲', '周杰伦')]),
        ],
      );
      final toolbox = fakes.toolbox();

      final added = await run(toolbox, AiToolbox.addSongsTool, {
        'playlist': '通勤',
        'songs': [
          {'title': '晴天'},
        ],
      });
      expect(added['added'], 1);

      final removed = await run(toolbox, AiToolbox.removeSongsTool, {
        'playlist': '通勤',
        'songs': [
          {'title': '夜曲'},
        ],
      });
      expect(removed['removed'], 1);
      expect(fakes.playlists.items.first.songs.single.name, '晴天');
    },
  );

  test('delete_playlist refuses to touch the built-in lists', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.deletePlaylistTool, {
      'playlist': 'favorites',
    });

    expect(result['error'], contains('系统歌单'));
    expect(fakes.playlists.deleted, isEmpty);
  });

  test('delete_playlist removes a user playlist by name', () async {
    final fakes = ToolFakes(playlists: [playlist('p1', '临时', [])]);
    final result = await run(fakes.toolbox(), AiToolbox.deletePlaylistTool, {
      'playlist': '临时',
    });

    expect(result['deleted'], isTrue);
    expect(fakes.playlists.deleted, ['p1']);
  });

  test('set_favorite toggles the current song', () async {
    final fakes = ToolFakes();
    fakes.playback.currentSong = song('1', '晴天', '周杰伦');
    final toolbox = fakes.toolbox();

    final added = await run(toolbox, AiToolbox.setFavoriteTool, {
      'current_song': true,
    });
    expect(added['changed'], ['晴天']);
    expect(
      await fakes.playlists.isFavorite(fakes.playback.currentSong!),
      isTrue,
    );

    final removed = await run(toolbox, AiToolbox.setFavoriteTool, {
      'current_song': true,
      'favorite': false,
    });
    expect(removed['changed'], ['晴天']);
    expect(
      await fakes.playlists.isFavorite(fakes.playback.currentSong!),
      isFalse,
    );
  });

  test('set_app_setting only accepts known keys and values', () async {
    final fakes = ToolFakes();
    final toolbox = fakes.toolbox();

    final theme = await run(toolbox, AiToolbox.setAppSettingTool, {
      'key': 'theme',
      'value': 'dark',
    });
    expect(theme['value'], 'dark');
    expect(fakes.settings.themeMode, 'dark');

    final bad = await run(toolbox, AiToolbox.setAppSettingTool, {
      'key': 'nope',
      'value': 1,
    });
    expect(bad['error'], contains('未知设置项'));
  });

  test('mark_disliked and the sleep timer change playback state', () async {
    final fakes = ToolFakes();
    fakes.playback.currentSong = song('1', '晴天', '周杰伦');
    final toolbox = fakes.toolbox();

    final marked = await run(toolbox, AiToolbox.markDislikedTool, {
      'current_song': true,
    });
    expect(marked['songs'], ['晴天']);
    expect(
      fakes.playback.disliked,
      contains(fakes.playback.currentSong!.identityKey),
    );

    final timer = await run(toolbox, AiToolbox.setSleepTimerTool, {
      'minutes': 30,
    });
    expect(timer['minutes'], 30);
    expect(fakes.playback.sleepTimer, const Duration(minutes: 30));

    final cancelled = await run(toolbox, AiToolbox.setSleepTimerTool, {
      'minutes': 0,
    });
    expect(cancelled['active'], isFalse);
    expect(fakes.playback.sleepTimer, isNull);
  });

  test('a call with no usable argument returns an error object', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.searchLibrary);

    expect(result['error'], contains('query'));
  });
}
