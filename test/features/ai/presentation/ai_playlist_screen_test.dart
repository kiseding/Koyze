import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/network/music_source_service.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/domain/ai_playlist_planner.dart';
import 'package:koyze/features/ai/presentation/ai_playlist_screen.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/custom_source/domain/custom_source_service.dart';
import 'package:koyze/features/player/domain/music_item.dart';

void main() {
  testWidgets('turns a sentence into a checked playlist draft', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '深夜写代码，纯音乐，不要太吵',
    );
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.text('深夜编码'), findsOneWidget);
    expect(find.text('2 of 3 songs found'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));

    final boxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList(growable: false);
    // 匹配上的两首预勾选，没匹配到的那行连勾选框都点不动。
    expect(boxes[0].value, isTrue);
    expect(boxes[1].value, isTrue);
    expect(boxes[2].value, isFalse);
    expect(boxes[2].onChanged, isNull);
    expect(find.textContaining('Not found:'), findsOneWidget);

    // 取消勾选后仅剩一首，创建按钮仍然可用。
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create playlist'),
    );
    expect(create.onPressed, isNotNull);
  });

  testWidgets('keeps the generate button idle when AI is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(_app(configured: false));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '随便来点');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    // 没有配置就只在原地提示，不会进入生成流程。
    expect(find.text('Generate'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Create playlist'), findsNothing);
  });

  testWidgets('an empty draft falls back to idle without a list', (
    tester,
  ) async {
    await tester.pumpWidget(_app(emptyDraft: true));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '来点歌');
    await tester.tap(find.text('Generate'));
    await tester.pumpAndSettle();

    expect(find.text('Generate'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });
}

Widget _app({
  bool configured = true,
  bool emptyDraft = false,
}) {
  return ProviderScope(
    overrides: [
      aiConfigProvider.overrideWith(() => _FakeConfig(configured)),
      aiPlannerProvider.overrideWithValue(_FakePlanner(emptyDraft: emptyDraft)),
      aiMatcherProvider.overrideWithValue(_FakeMatcher()),
    ],
    child: const MaterialApp(home: AiPlaylistScreen()),
  );
}

class _FakeConfig extends AiConfigNotifier {
  _FakeConfig(this.configured);

  final bool configured;

  @override
  AiConfig build() => configured
      ? const AiConfig(baseUrl: 'https://api.test/v1', model: 'm')
      : AiConfig.empty;

  @override
  Future<String?> loadKey({String? baseUrl}) async =>
      configured ? 'sk-test' : null;
}

class _FakePlanner extends AiPlaylistPlanner {
  _FakePlanner({required this.emptyDraft});

  final bool emptyDraft;

  @override
  Future<AiPlaylistDraft> plan({
    required AiConfig config,
    required String apiKey,
    required String request,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (emptyDraft) {
      return const AiPlaylistDraft(name: '空', description: '', songs: []);
    }
    return const AiPlaylistDraft(
      name: '深夜编码',
      description: '低刺激的纯音乐',
      songs: [
        AiSongRequest(title: '晴天', artist: '周杰伦'),
        AiSongRequest(title: '稻香', artist: '周杰伦'),
        AiSongRequest(title: '不存在的曲子', artist: '某人'),
      ],
    );
  }
}

class _FakeMatcher extends AiPlaylistMatcher {
  _FakeMatcher() : super(service: MusicSourceService(_NoopService()));

  @override
  Future<List<AiSongMatch>> match(
    List<AiSongRequest> requests, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final matches = <AiSongMatch>[
      AiSongMatch(request: requests[0], song: _song('晴天'), score: 1),
      AiSongMatch(request: requests[1], song: _song('稻香'), score: 1),
      AiSongMatch(request: requests[2], song: null, score: 0),
    ];
    onProgress?.call(requests.length, requests.length);
    return matches;
  }
}

MusicItem _song(String name) =>
    MusicItem(id: name, name: name, singer: '周杰伦', source: 'kw');

class _NoopService extends CustomSourceService {
  @override
  Future<void> init() async {}
}
