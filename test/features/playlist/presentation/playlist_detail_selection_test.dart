import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/features/playlist/data/playlist_repository.dart';
import 'package:koyze/features/playlist/domain/playlist.dart';
import 'package:koyze/features/playlist/presentation/playlist_detail_screen.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 收藏列表的多选工具条。
///
/// 这里锁的是一个很容易复发的布局约束：AppBar 把 `leading` 收成 56pt 宽，
/// 一个 48pt 的图标按钮刚好放得下，第二个会被排到盒子外面——图标画得出来、
/// 甚至盖在标题上，但点它的位置不在父盒子范围内，命中不了，表现就是
/// 「按钮点不动」。所以多选的全选按钮必须在 `actions` 里。
void main() {
  Playlist favoritesWith(int count) {
    final now = DateTime.utc(2026);
    return Playlist(
      id: 'favorites',
      name: '收藏列表',
      createdAt: now,
      updatedAt: now,
      songs: List.generate(
        count,
        (i) => MusicItem(
          id: 'song-$i',
          name: 'Song $i',
          singer: 'Artist $i',
          source: 'kw',
        ),
      ),
    );
  }

  Future<void> pumpFavorites(WidgetTester tester, Playlist playlist) async {
    final container = ProviderContainer(
      overrides: [
        playlistRepositoryProvider.overrideWithValue(
          _MemoryRepository(
            PlaylistSnapshot(schemaVersion: 1, playlists: [playlist]),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playlistServiceProvider).init();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('进入多选后全选按钮可以点，点完变成取消全选', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));
    expect(tester.takeException(), isNull, reason: '打开页面不该有溢出或断言');

    // 长按任意一行进入多选。
    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: '多选工具条出现时不该有 RenderFlex 溢出',
    );

    expect(find.byIcon(Icons.select_all), findsOneWidget);
    expect(find.byTooltip('全选'), findsOneWidget);

    // 关键断言：这个按钮必须真的能被点到。位置若落在 leading 盒子外，
    // tap 会因为目标不在命中链上而失败。
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();

    expect(
      find.byIcon(Icons.deselect),
      findsOneWidget,
      reason: '全选后按钮应切换成「取消全选」',
    );
    expect(find.text('已选 30 首'), findsOneWidget, reason: '整页 30 首应全部选中');
    expect(tester.takeException(), isNull);
  });

  testWidgets('再点一次取消全选，一首不剩时退回普通模式', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));

    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    expect(find.text('已选 30 首'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.deselect));
    await tester.pumpAndSettle();

    // 取消全选后没有选中项，多选工具条自动收起。
    expect(find.byIcon(Icons.select_all), findsNothing);
    expect(find.byIcon(Icons.deselect), findsNothing);
    expect(find.byTooltip('播放全部'), findsOneWidget, reason: '回到普通模式的工具栏');
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量取消收藏是实心药丸按钮，带选中数量且可点', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));

    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();

    // 批量取消收藏是这个工具条里唯一的破坏性动作，必须和旁边两个裸图标
    // 按钮有明确层级差：实心爱心（不是描边 favorite_border）、专属底座
    // （带底色和描边）、把当前选中数量直接写在按钮上。
    expect(
      find.byIcon(Icons.favorite),
      findsOneWidget,
      reason: '批量取消收藏应该用实心心形；描边心形在 48pt 下和下载图标分不开',
    );
    // 数量跟随选中数：刚进多选是 1 首。
    expect(find.text('1'), findsOneWidget, reason: '按钮上应显示当前选中数量');

    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pumpAndSettle();
    expect(find.text('30'), findsOneWidget, reason: '全选后按钮上的数量应变成 30');

    // 关键：这个按钮必须真的能点到（不能像 leading 里那样落在盒子外）。
    expect(
      find.byTooltip('取消收藏已选歌曲'),
      findsOneWidget,
      reason: '批量取消收藏按钮应带有「取消收藏」提示',
    );
    await tester.tap(find.byTooltip('取消收藏已选歌曲'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('批量取消收藏有专属 error 色底座，不是裸图标', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));

    await tester.longPress(find.text('Song 0'));
    await tester.pumpAndSettle();

    // 这个动作一次抹掉整批收藏且不可撤销，必须和旁边「全选」「下载」两个
    // 透明底裸图标有实体层级差：专属描边底座 + error 色。
    // 只查图标形状不够——描边/实心靠的是材质，底座才是「这是个按钮」的
    // 主要信号。
    final pill = find.descendant(
      of: find.byTooltip('取消收藏已选歌曲'),
      matching: find.byType(DecoratedBox),
    );
    expect(pill, findsWidgets, reason: '批量取消收藏应有带装饰的底座');

    final decorated = tester
        .widgetList<DecoratedBox>(pill)
        .map((box) {
          final d = box.decoration;
          return d is BoxDecoration ? d : null;
        })
        .whereType<BoxDecoration>()
        .toList();

    final pillBase = decorated.where(
      (d) => d.border != null && d.borderRadius == BorderRadius.circular(14),
    );
    expect(
      pillBase,
      isNotEmpty,
      reason: '底座应该是圆角 14 的填充 + 描边，和裸图标按钮区分开',
    );

    // 底色和描边都必须是 error 色（destructive），且是半透明淡色底——
    // 实心红底会读成「主操作」，而这个动作是破坏性的。
    final base = pillBase.first;
    bool near(double actual, double expected) =>
        (actual - expected).abs() < 0.02;
    bool sameRgb(Color? c) =>
        c != null &&
        near(c.r, AppColors.error.r) &&
        near(c.g, AppColors.error.g) &&
        near(c.b, AppColors.error.b);

    expect(
      sameRgb(base.color) && near(base.color!.a, 0.13),
      isTrue,
      reason: '底座底色应是 error 色 13% 淡化，实际 ${base.color}',
    );

    final border = base.border;
    final borderColor = border is Border ? border.top.color : null;
    expect(
      sameRgb(borderColor) && near(borderColor!.a, 0.55),
      isTrue,
      reason: '描边应是 error 色 55% 淡化，实际 $borderColor',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通模式不出现批量取消收藏按钮', (tester) async {
    await pumpFavorites(tester, favoritesWith(30));

    // 未进多选模式时这个按钮根本不存在。
    // 注意不能用「实心心形」判断——收藏列表里每首歌的收藏按钮本来就是
    // 实心的，全页有十几颗。
    expect(find.byTooltip('取消收藏已选歌曲'), findsNothing);
    expect(find.byTooltip('播放全部'), findsOneWidget);
  });
}

class _MemoryRepository implements PlaylistRepository {
  _MemoryRepository(this.snapshot);

  PlaylistSnapshot snapshot;

  @override
  Future<PlaylistSnapshot> load() async => snapshot;

  @override
  Future<void> save(PlaylistSnapshot value) async => snapshot = value;
}
