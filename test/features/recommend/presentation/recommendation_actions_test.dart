import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/favorite_button.dart';
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
  testWidgets('歌曲行使用收藏按钮，标题栏 AI 图标发送推荐任务提示', (tester) async {
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
          aiChatProvider.overrideWith(AiChatNotifier.new),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme(),
          home: const RecommendationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FavoriteButton), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);

    final aiButton = find.byTooltip('让 AI 改进猜你喜欢');
    expect(aiButton, findsOneWidget);
    expect(find.text('让 AI 改进猜你喜欢'), findsNothing);
    await tester.tap(aiButton);
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(RecommendationScreen)),
    );
    final chat = container.read(aiChatProvider);
    expect(chat.entries.first.text, contains('改进「猜你喜欢」歌单'));
    expect(chat.entries.first.text, contains('不要播放歌曲或创建新歌单'));
    expect(chat.entries.first.isUser, isTrue);
  });
}
