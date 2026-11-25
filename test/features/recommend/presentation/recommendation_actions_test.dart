import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/core/widgets/favorite_button.dart';
import 'package:koyze/core/widgets/fx_icon_button.dart';
import 'package:koyze/features/ai/domain/ai_config.dart';
import 'package:koyze/features/ai/presentation/ai_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';
import 'package:koyze/features/recommend/presentation/recommendation_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

List<RecommendedSong> _songs() => [
  RecommendedSong(
    song: MusicItem(
      id: 'song-1',
      name: '测试歌曲',
      singer: '测试歌手',
      album: '测试专辑',
      source: 'builtin',
      platform: 'kw',
    ),
    score: 100,
    reasons: const ['常听'],
  ),
];

void main() {
  testWidgets('歌曲行使用收藏按钮，未配置时 AI 入口提示错误且不发送任务', (tester) async {
    await _pumpScreen(tester, const AiConfig());

    expect(find.byType(FavoriteButton), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);

    final aiButton = find.byTooltip('让 AI 改进猜你喜欢');
    expect(aiButton, findsOneWidget);
    expect(find.text('让 AI 改进猜你喜欢'), findsNothing);
    await tester.tap(aiButton);
    await tester.pumpAndSettle();

    expect(find.text('请先填写有效的 http(s) 地址、模型和密钥'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecommendationScreen)),
    );
    expect(container.read(aiChatProvider).entries, isEmpty);
  });

  testWidgets('配置完整时 AI 图标点亮、留出右边距并发送推荐任务', (tester) async {
    const config = AiConfig(
      baseUrl: 'https://api.example.com/v1',
      model: 'test-model',
    );
    await _pumpScreen(tester, config, apiKey: 'test-key');

    final button = tester.widget<FxIconButton>(
      find.widgetWithIcon(FxIconButton, Icons.auto_awesome_rounded),
    );
    expect(
      button.color,
      AppColors.accentOf(tester.element(find.byType(RecommendationScreen))),
    );

    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.byTooltip('让 AI 改进猜你喜欢'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(padding.padding, const EdgeInsets.only(right: 16));

    await tester.tap(find.byTooltip('让 AI 改进猜你喜欢'));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecommendationScreen)),
    );
    expect(
      container.read(aiChatProvider).entries.first.text,
      contains('改进「猜你喜欢」歌单'),
    );
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AiConfig config, {
  String? apiKey,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMusicProvider.overrideWithValue(null),
        recommendationProvider.overrideWith(
          () => RecommendationNotifier(loader: () async => _songs()),
        ),
        aiConfigProvider.overrideWith(() => _TestAiConfigNotifier(config)),
        aiApiKeyProvider.overrideWith((ref) async => apiKey),
        aiChatProvider.overrideWith(AiChatNotifier.new),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme(),
        builder: (context, child) => AppNotificationHost(child: child!),
        home: const RecommendationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestAiConfigNotifier extends AiConfigNotifier {
  _TestAiConfigNotifier(this.config);

  final AiConfig config;

  @override
  AiConfig build() => config;

  @override
  Future<String?> loadKey({String? baseUrl}) async => 'test-key';
}
