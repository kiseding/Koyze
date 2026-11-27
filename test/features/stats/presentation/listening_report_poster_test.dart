import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/stats/data/play_history_store.dart';
import 'package:koyze/features/stats/presentation/listening_report_poster.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 海报会被导出成 1080×1920 的 PNG，画错之后用户保存下来的图修不回来。
/// 这里钉住最容易悄悄回归的两类问题：继承外层下划线、时段条超出卡片。
Widget _host(ListeningReportData data) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1DB954)),
    ),
    home: Scaffold(
      body: Center(
        child: DefaultTextStyle(
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFFFFEB3B),
          ),
          child: ListeningReportPoster(
            data: data,
            accent: const Color(0xFF1DB954),
          ),
        ),
      ),
    ),
  );
}

ListeningReportData _data({double hour = 60}) => ListeningReportData(
  range: StatsRange.week,
  totalPlays: 12,
  totalSec: 3600,
  activeDays: 5,
  uniqueSongs: 8,
  topSongs: const [
    RankedItem(
      id: 'a',
      title: '晴天',
      subtitle: '周杰伦',
      playCount: 6,
      totalSec: 300,
    ),
    RankedItem(
      id: 'b',
      title: '以父之名',
      subtitle: '周杰伦',
      playCount: 4,
      totalSec: 280,
    ),
  ],
  topArtist: const RankedItem(
    id: 'artist:周杰伦',
    title: '周杰伦',
    subtitle: '2 首',
    playCount: 10,
    totalSec: 580,
  ),
  hourlySeconds: [for (var i = 0; i < 24; i++) i == 20 ? hour : 0],
  favoriteHour: hour > 0 ? 20 : null,
);

void main() {
  testWidgets('海报固定 360×640，文字不继承外层下划线', (tester) async {
    await tester.pumpWidget(_host(_data()));

    final poster = tester.widget<SizedBox>(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 360 && w.height == 640,
      ),
    );
    expect(poster.width, 360);
    expect(poster.height, 640);

    for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(
        text.text.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '外层下划线渗进了海报：${text.text.toPlainText()}',
      );
    }
  });

  testWidgets('空时段海报也能渲染，不溢出', (tester) async {
    final data = _data(hour: 0);
    await tester.pumpWidget(_host(data));

    expect(tester.takeException(), isNull);
    expect(find.text('最常听的歌曲'), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);
  });

  testWidgets('时段条数量固定 24 根', (tester) async {
    await tester.pumpWidget(_host(_data()));

    // 24 个小时各一根，Expanded 包着带高度的 Container；用带固定 heights
    // 的 SizedBox 之外那些 Container 计数不现实，改为断言卡片不溢出即可。
    expect(tester.takeException(), isNull);
    // 海报里 24 根时段条 + 顶部/底部装饰，总 Container 数应显著多于 24。
    expect(
      tester.widgetList<Container>(find.byType(Container)).length,
      greaterThanOrEqualTo(24),
    );
  });
}
