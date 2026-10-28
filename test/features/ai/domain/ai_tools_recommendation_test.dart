import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_tools.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';

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

RecommendedSong recommended(String name, String singer, double score) =>
    RecommendedSong(
      song: song('$name-$singer', name, singer),
      score: score,
      reasons: ['常听 $singer'],
    );

void main() {
  test('get_recommendations 把当前结果和已设的调整一起读出来', () async {
    final fakes = ToolFakes();
    fakes.recommendations.setItems([
      recommended('晴天', '周杰伦', 0.92),
      recommended('夜曲', '周杰伦', 0.71),
    ]);

    final result = await run(fakes.toolbox(), AiToolbox.getRecommendationsTool, {
      'limit': 1,
    });

    expect(result['ready'], isTrue);
    expect(result['total'], 2);
    final songs = (result['songs'] as List).cast<Map<String, dynamic>>();
    expect(songs.single['title'], '晴天');
    expect(songs.single['artist'], '周杰伦');
    expect(songs.single['score'], 0.92);
    expect(songs.single['reasons'], ['常听 周杰伦']);
  });

  test('edit_recommendations 把置顶、屏蔽和口味拼进同一份调校并重算', () async {
    final fakes = ToolFakes();
    final result = await run(
      fakes.toolbox(),
      AiToolbox.editRecommendationsTool,
      {
        'pin': [
          {'title': '晴天', 'artist': '周杰伦'},
        ],
        'exclude': ['夜曲'],
        'exclude_artists': ['某人'],
        'focus': '多来点粤语老歌',
      },
    );

    expect(result['ok'], isTrue);
    expect(result['summary'], contains('置顶 1 首'));
    expect(result['summary'], contains('屏蔽 1 首'));
    expect(result['summary'], contains('屏蔽 1 位歌手'));
    expect(result['summary'], contains('多来点粤语老歌'));

    final tuning = fakes.recommendations.tuning;
    expect(tuning.pinned.single.title, '晴天');
    expect(tuning.excludedSongs.single.title, '夜曲');
    expect(tuning.excludedArtists, ['某人']);
    expect(tuning.focus, '多来点粤语老歌');
    // 改完之后一定重算过一次，模型才能立刻看到新结果。
    expect(fakes.recommendations.refreshes, 1);
  });

  test('多次调用是叠加而不是覆盖', () async {
    final fakes = ToolFakes();
    final toolbox = fakes.toolbox();
    await run(toolbox, AiToolbox.editRecommendationsTool, {
      'pin': [
        {'title': '晴天'},
      ],
    });
    await run(toolbox, AiToolbox.editRecommendationsTool, {
      'pin': [
        {'title': '夜曲'},
      ],
    });

    expect(
      fakes.recommendations.tuning.pinned.map((ref) => ref.title),
      ['晴天', '夜曲'],
    );
  });

  test('clear 能撤销指定的一类，all 全清', () async {
    final fakes = ToolFakes();
    final toolbox = fakes.toolbox();
    await run(toolbox, AiToolbox.editRecommendationsTool, {
      'pin': [
        {'title': '晴天'},
      ],
      'exclude_artists': ['周杰伦'],
      'focus': '安静点',
    });

    await run(toolbox, AiToolbox.editRecommendationsTool, {
      'clear': ['artists'],
    });
    expect(fakes.recommendations.tuning.excludedArtists, isEmpty);
    expect(fakes.recommendations.tuning.pinned, isNotEmpty);
    expect(fakes.recommendations.tuning.focus, '安静点');

    await run(toolbox, AiToolbox.editRecommendationsTool, {
      'clear': ['all'],
    });
    expect(fakes.recommendations.tuning.isEmpty, isTrue);
  });

  test('什么都不给时返回错误，不会白跑一次重算', () async {
    final fakes = ToolFakes();
    final result = await run(fakes.toolbox(), AiToolbox.editRecommendationsTool);
    expect(result['error'], contains('没有要改的内容'));
    expect(fakes.recommendations.refreshes, 0);
  });

  test('只读模式下猜你喜欢工具只剩查询那一个', () async {
    final fakes = ToolFakes();
    final toolbox = fakes.toolbox(allowActions: false);
    final names = [
      for (final spec in toolbox.specs) (spec['function'] as Map)['name'],
    ];

    expect(names, contains(AiToolbox.getRecommendationsTool));
    expect(names, isNot(contains(AiToolbox.editRecommendationsTool)));

    // 就算模型硬调，也只会拿到一句拒绝而不是真的改了。
    final result = await run(toolbox, AiToolbox.editRecommendationsTool, {
      'exclude_artists': ['周杰伦'],
    });
    expect(result['error'], contains('执行权限'));
    expect(fakes.recommendations.tuning.isEmpty, isTrue);
  });
}
