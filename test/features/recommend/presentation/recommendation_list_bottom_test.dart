// 「猜你喜欢」的列表必须一直画到屏幕最底边。
//
// 之前整页套了一层 SafeArea(bottom: true)，滚动视口在 Home 指示条上方就
// 结束了：最后一行被齐刷刷砍断（序号和播放按钮只剩上半截），下面还留一条
// 和列表分界明显的空带，看着就像凭空多出一块白。
//
// 现在页面画到屏幕底边，该留的距离改成列表自己的 bottom padding，
// 于是「没滚动时贴着屏幕边缘裁切」+「滚到底时最后一行完整露出来」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/recommend/domain/recommendation_engine.dart';
import 'package:koyze/features/recommend/presentation/recommendation_provider.dart';
import 'package:koyze/features/recommend/presentation/recommendation_screen.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// iPhone 16 Pro：402×874 逻辑像素，底部手势条 34。
const Size _screen = Size(402, 874);
const double _safeBottom = 34;

List<RecommendedSong> _songs(int count) {
  return [
    for (var i = 0; i < count; i++)
      RecommendedSong(
        song: MusicItem(
          id: 's$i',
          name: '曲目 ${i + 1}',
          singer: '测试歌手',
          album: '测试专辑',
          source: 'builtin',
          platform: 'kw',
        ),
        score: 100 - i.toDouble(),
        reasons: const ['常听'],
      ),
  ];
}

Future<void> _pumpScreen(WidgetTester tester, {int count = 12}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3.0;
  tester.view.padding = const FakeViewPadding(bottom: _safeBottom * 3);
  tester.view.viewPadding = const FakeViewPadding(bottom: _safeBottom * 3);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMusicProvider.overrideWithValue(null),
        recommendationProvider.overrideWith(
          () => RecommendationNotifier(loader: () async => _songs(count)),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme(),
        home: const RecommendationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('滚动区域铺到屏幕最底边，不在安全区上方提前收口', (tester) async {
    await _pumpScreen(tester);

    final rect = tester.getRect(find.byType(ListView));
    expect(
      rect.bottom,
      moreOrLessEquals(_screen.height, epsilon: 0.5),
      reason:
          '列表底边应当和屏幕底边重合；停在 height - $_safeBottom '
          '就会在最后一行下面留一条空带',
    );
  });

  testWidgets('滚到底时最后一行完整露出，不被手势条压住', (tester) async {
    await _pumpScreen(tester);

    await tester.drag(find.byType(ListView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    final last = tester.getRect(find.byType(ListTile).last);
    final gap = _screen.height - last.bottom;
    expect(
      gap,
      greaterThanOrEqualTo(_safeBottom - 0.5),
      reason: '最后一行整行都要在 Home 指示条上方',
    );
    // 也别缩得太狠：多留的应该只是设计上的 24，而不是一条空带。
    expect(gap, lessThanOrEqualTo(_safeBottom + 24 + 0.5));
  });
}
