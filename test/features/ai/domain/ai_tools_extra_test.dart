import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_schedule.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';

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

void main() {
  group('均衡器', () {
    test('读出来是平台支持、当前预设与每个频段的增益', () async {
      final fakes = ToolFakes();
      fakes.equalizer
        ..enabled = true
        ..presetId = 'bass'
        ..gains = const [6, 4, 0, -1, -2];

      final result = await run(fakes.toolbox(), AiToolbox.getEqualizerTool);

      expect(result['supported'], isTrue);
      expect(result['enabled'], isTrue);
      expect(result['preset'], 'bass');
      expect(result['presets'], contains('bass'));
      expect(result['range'], {'min_db': -12.0, 'max_db': 12.0});
      final bands = result['bands'] as List;
      expect(bands, hasLength(5));
      expect((bands.first as Map)['hz'], 60);
      expect((bands.first as Map)['gain_db'], 6.0);
    });

    test('平台不支持时直接报错，不会假装改成功', () async {
      final fakes = ToolFakes(equalizer: FakeEqualizer(supported: false));

      final result = await run(
        fakes.toolbox(),
        AiToolbox.setEqualizerTool,
        {'enabled': true},
      );

      expect(result['error'], contains('没有可用的均衡器'));
      expect(fakes.equalizer.calls, isEmpty);
    });

    test('预设、频段、开关按顺序生效', () async {
      final fakes = ToolFakes();

      final result = await run(
        fakes.toolbox(),
        AiToolbox.setEqualizerTool,
        {
          'preset': 'bass',
          'bands': [
            {'hz': 60, 'gain_db': 5},
            {'hz': 14000, 'gain_db': -3},
          ],
          'enabled': true,
        },
      );

      expect(result['error'], isNull);
      expect(fakes.equalizer.calls, [
        'preset:bass',
        'band:60.0:5.0',
        'band:14000.0:-3.0',
        'enabled:true',
      ]);
      expect(fakes.equalizer.gains.first, 5);
      expect(fakes.equalizer.gains.last, -3);
    });

    test('设备上没有这个频段时记进 skipped，不当成功', () async {
      final fakes = ToolFakes();

      final result = await run(
        fakes.toolbox(),
        AiToolbox.setEqualizerTool,
        {
          'bands': [
            {'hz': 30000, 'gain_db': 4},
          ],
        },
      );

      expect(result['skipped'], isNotEmpty);
      expect(fakes.equalizer.gains, everyElement(0));
    });

    test('未知预设被拒绝，并给出可用清单', () async {
      final fakes = ToolFakes();

      final result = await run(
        fakes.toolbox(),
        AiToolbox.setEqualizerTool,
        {'preset': 'nightcore'},
      );

      expect(result['error'], contains('没有这个预设'));
      expect(result['presets'], contains('flat'));
      expect(fakes.equalizer.presetId, 'flat');
    });

    test('reset 会恢复平直', () async {
      final fakes = ToolFakes();
      fakes.equalizer.gains = const [6, 6, 6, 6, 6];

      final result = await run(
        fakes.toolbox(),
        AiToolbox.setEqualizerTool,
        {'reset': true},
      );

      expect(result['error'], isNull);
      expect(fakes.equalizer.gains, everyElement(0));
    });
  });

  group('听歌统计', () {
    test('range 透传给端口，返回次数、时长与三张榜', () async {
      final fakes = ToolFakes();

      final result = await run(
        fakes.toolbox(),
        AiToolbox.listeningStatsTool,
        {'range': 'month'},
      );

      expect(fakes.stats.lastRange, 'month');
      expect(result['range'], 'month');
      expect(result['playCount'], 42);
      expect(result['minutes'], 60);
      expect(result['activeDays'], 3);
      expect((result['topSongs'] as List).first, {
        'title': '晴天',
        'subtitle': '周杰伦',
        'playCount': 12,
        'minutes': 50,
      });
    });

    test('不认识的 range 退回 week', () async {
      final fakes = ToolFakes();

      await run(fakes.toolbox(), AiToolbox.listeningStatsTool, {
        'range': '昨天',
      });

      expect(fakes.stats.lastRange, 'week');
    });
  });

  group('歌词', () {
    test('不给参数就取当前播放的那首', () async {
      final fakes = ToolFakes();
      fakes.playback.currentSong = song('9', '夜曲', '周杰伦');

      final result = await run(fakes.toolbox(), AiToolbox.lyricsTool);

      expect(result['title'], '夜曲');
      expect(fakes.lyrics.requested, ['夜曲']);
      final lines = result['lines'] as List;
      expect(lines.first, {'at': 0, 'text': '故事的小黄花'});
      expect(result['total'], 2);
    });

    test('没有播放中的歌时提示改用 title', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.lyricsTool);

      expect(result['error'], contains('没有播放中的歌曲'));
      expect(fakes.lyrics.requested, isEmpty);
    });

    test('按歌名取，走一次搜索解析', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.lyricsTool, {
        'title': '晴天',
        'artist': '周杰伦',
      });

      expect(result['title'], '晴天');
      expect(fakes.queries, isNotEmpty);
    });

    test('取不到歌词就报错，不返回空行列表', () async {
      final fakes = ToolFakes();
      fakes.lyrics.lines = null;
      fakes.playback.currentSong = song('9', '夜曲', '周杰伦');

      final result = await run(fakes.toolbox(), AiToolbox.lyricsTool);

      expect(result['error'], contains('没有取到歌词'));
      expect(result['lines'], isNull);
    });
  });

  group('榜单', () {
    test('列出全部榜单，带 platform:id 形式的 id', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.listChartsTool);

      expect(result['charts'], [
        {'id': 'tx:26', 'name': '热歌榜', 'platform': 'tx'},
        {'id': 'kw:93', 'name': '飙升榜', 'platform': 'kw'},
      ]);
    });

    test('可以按平台过滤', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.listChartsTool, {
        'platform': 'kw',
      });

      expect((result['charts'] as List), hasLength(1));
      expect((result['charts'] as List).single['id'], 'kw:93');
    });

    test('按名称播放榜单，从第一首开始', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.playChartTool, {
        'chart': '热歌',
      });

      expect(result['chart'], '热歌榜');
      expect(result['startedAt'], 0);
      expect(fakes.playback.played, isNotEmpty);
    });

    test('榜单空了不硬播', () async {
      final fakes = ToolFakes();
      fakes.charts.songsEmpty = true;

      final result = await run(fakes.toolbox(), AiToolbox.playChartTool, {
        'chart': 'tx:26',
      });

      expect(result['error'], contains('没有取到歌曲'));
      expect(fakes.playback.played, isEmpty);
    });

    test('不存在的榜单报错', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.playChartTool, {
        'chart': '火星榜',
      });

      expect(result['error'], contains('没有这个榜单'));
    });
  });

  group('定时任务', () {
    test('列表把分钟数还原成 HH:mm', () async {
      final fakes = ToolFakes();
      fakes.schedules.tasks.add(
        const AiScheduledTask(
          id: 'task_1',
          title: '早间',
          prompt: '把新歌加进通勤',
          minuteOfDay: 8 * 60 + 5,
          cadence: AiScheduleCadence.weekdays,
        ),
      );

      final result = await run(fakes.toolbox(), AiToolbox.listSchedulesTool);

      final first = (result['schedules'] as List).single as Map;
      expect(first['time'], '08:05');
      expect(first['cadence'], 'weekdays');
      expect(first['enabled'], isTrue);
    });

    test('create 解析 HH:mm 与重复方式', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.manageScheduleTool, {
        'action': 'create',
        'title': '早间通勤',
        'prompt': '把昨天新增的歌加进「通勤」歌单',
        'time': '8:00',
        'cadence': 'weekdays',
      });

      expect(result['created'], isNotNull);
      expect(result['time'], '08:00');
      expect(fakes.schedules.tasks.single.minuteOfDay, 480);
      expect(fakes.schedules.tasks.single.title, '早间通勤');
    });

    test('weekly 缺 weekday 时拒绝', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.manageScheduleTool, {
        'action': 'create',
        'title': '周末',
        'prompt': '推十首',
        'time': '10:00',
        'cadence': 'weekly',
      });

      expect(result['error'], contains('weekday'));
      expect(fakes.schedules.tasks, isEmpty);
    });

    test('时间格式不对时拒绝', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.manageScheduleTool, {
        'action': 'create',
        'title': 'x',
        'prompt': 'y',
        'time': '八点',
      });

      expect(result['error'], contains('HH:mm'));
    });

    test('pause / remove / run 都按 id 生效', () async {
      final fakes = ToolFakes();
      await run(fakes.toolbox(), AiToolbox.manageScheduleTool, {
        'action': 'create',
        'title': '早间',
        'prompt': '推歌',
        'time': '08:00',
      });
      final id = fakes.schedules.tasks.single.id;

      final paused = await run(
        fakes.toolbox(),
        AiToolbox.manageScheduleTool,
        {'action': 'pause', 'id': id},
      );
      expect(paused['enabled'], isFalse);

      final ran = await run(
        fakes.toolbox(),
        AiToolbox.manageScheduleTool,
        {'action': 'run', 'id': id},
      );
      expect(ran['ok'], isTrue);
      expect(ran['result'], '好了');

      final removed = await run(
        fakes.toolbox(),
        AiToolbox.manageScheduleTool,
        {'action': 'remove', 'id': id},
      );
      expect(removed['removed'], id);
      expect(fakes.schedules.tasks, isEmpty);
    });

    test('id 不存在时报错而不是静默成功', () async {
      final fakes = ToolFakes();

      final result = await run(fakes.toolbox(), AiToolbox.manageScheduleTool, {
        'action': 'remove',
        'id': 'task_404',
      });

      expect(result['error'], contains('没有这个任务'));
    });
  });

  test('重新扫描本地曲库返回新增数量', () async {
    final fakes = ToolFakes();
    fakes.local.added = 7;

    final result = await run(fakes.toolbox(), AiToolbox.rescanLocalTool);

    expect(result['added'], 7);
    expect(fakes.local.calls, 1);
  });

  test('只读模式下这些写工具整个不下发', () {
    final fakes = ToolFakes();
    final names = fakes
        .toolbox(allowActions: false)
        .specs
        .map((spec) => (spec['function'] as Map)['name'])
        .toSet();

    for (final writeTool in [
      AiToolbox.setEqualizerTool,
      AiToolbox.playChartTool,
      AiToolbox.manageScheduleTool,
      AiToolbox.rescanLocalTool,
    ]) {
      expect(names, isNot(contains(writeTool)), reason: writeTool);
    }
    for (final readTool in [
      AiToolbox.getEqualizerTool,
      AiToolbox.listeningStatsTool,
      AiToolbox.lyricsTool,
      AiToolbox.listChartsTool,
      AiToolbox.listSchedulesTool,
    ]) {
      expect(names, contains(readTool), reason: readTool);
    }
  });
}
