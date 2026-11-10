import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/lyric/presentation/lyric_display_screen.dart';
import 'package:koyze/features/lyric/presentation/lyric_preview.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';

/// 这一页的所有文案都走 [S]；测试必须把语言固定成中文，否则会回落到英文，
/// 按中文断言就会全是假阴性。
Widget _host({
  List<Override> overrides = const [],
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LyricDisplayScreen(),
    ),
  );
}

S _strings(WidgetTester tester) =>
    S.of(tester.element(find.byType(LyricDisplayScreen)));

/// 这一页内容比默认的 800×600 测试视口长得多，ListView 只会构建可见区间，
/// 屏幕外的分组标题和开关根本没被 build，断言会假阴性。把视口拉高，
/// 让整页一次建完。
Future<void> _pump(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Locale locale = const Locale('zh'),
}) async {
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(overrides: overrides, locale: locale));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('不再有「呈现方式」，改成上下模糊', (tester) async {
    await _pump(tester);

    final s = _strings(tester);

    // 单行/轮盘/滚动三选一已经撤掉，歌词只有一种呈现方式。
    expect(find.text('呈现方式'), findsNothing);
    for (final label in ['滚动', '单行', '轮盘']) {
      expect(find.text(label), findsNothing, reason: '旧布局选项仍在：$label');
    }

    expect(find.text(s.lyricBlur), findsOneWidget);
    // 入场动画保留。
    expect(find.text(s.lyricEntrance), findsOneWidget);
    // 像素点阵换成自定义字体。
    expect(find.text('像素点阵'), findsNothing);
    expect(find.text(s.lyricFont), findsWidgets);
  });

  testWidgets('是整页而不是弹窗：有返回按钮、没有关闭按钮', (tester) async {
    await _pump(tester);

    expect(find.byType(AppBar), findsOneWidget);
    // 弹窗才有的关闭图标。
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('拖动模糊滑杆时预览立即跟着变', (tester) async {
    await _pump(tester);

    final before = tester
        .widgetList<ImageFiltered>(
          find.descendant(
            of: find.byType(LyricPreview),
            matching: find.byType(ImageFiltered),
          ),
        )
        .length;
    expect(before, greaterThan(0), reason: '默认 0.4 档，远处几行应该是糊的');

    // 拖到最左：0 档。
    await tester.drag(find.byType(Slider).first, const Offset(-600, 0));
    await tester.pumpAndSettle();

    final after = tester
        .widgetList<ImageFiltered>(
          find.descendant(
            of: find.byType(LyricPreview),
            matching: find.byType(ImageFiltered),
          ),
        )
        .length;
    expect(after, 0, reason: '0 档时一行都不该套模糊');
  });

  testWidgets('换入场动画会重放预览的入场', (tester) async {
    await _pump(tester);

    final s = _strings(tester);
    await tester.tap(find.text(s.lyricEntranceFade));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    // 过渡中预览里至少有一层没到终值的透明度。
    final opacities = tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byType(LyricPreview),
            matching: find.byType(Opacity),
          ),
        )
        .map((widget) => widget.opacity);
    expect(opacities.any((value) => value < 1), isTrue);
  });

  testWidgets('没有选过字体时显示跟随主题，且没有「恢复默认」', (tester) async {
    await _pump(tester);

    final s = _strings(tester);
    expect(find.text(s.lyricFontDefaultName), findsOneWidget);
    // 只有选过字体才出现这一个「恢复默认」（重置滑杆的那条用的是同一个词，
    // 所以按 key 断言，避免和页面底部的重置按钮混淆）。
    expect(find.byKey(const Key('lyric-font-reset')), findsNothing);
    expect(find.text(s.lyricFontPick), findsOneWidget);
  });

  testWidgets('翻译、音译开关能改到预览', (tester) async {
    await _pump(tester);

    final s = _strings(tester);

    // 默认都开：预览里的日文行会带罗马音与译文。
    expect(find.text('shizumu you ni'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, s.lyricRoman));
    await tester.pumpAndSettle();
    expect(find.text('shizumu you ni'), findsNothing);
  });

  testWidgets('重置把所有滑杆拉回默认', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(lyricScaleProvider.notifier).setScale(1.3);
    container.read(lyricBlurProvider.notifier).setBlur(1);

    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _host()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_strings(tester).resetToDefault));
    await tester.pumpAndSettle();

    expect(container.read(lyricScaleProvider), 1);
    expect(container.read(lyricBlurProvider), LyricBlurNotifier.defaultBlur);
  });

  testWidgets('真机小屏上不溢出，且能一直滚到底部的重置按钮', (tester) async {
    // 390×844 是常见手机视口；这一页塞了预览 + 五组设置，最容易出问题
    // 的就是「内容比屏幕长」和「预览区高度写死导致溢出」。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 底部重置按钮一开始在屏幕外，滚到底必须能摸到。
    final reset = find.text(_strings(tester).resetToDefault);
    await tester.scrollUntilVisible(reset, 300);
    expect(reset, findsOneWidget);
  });

  testWidgets('列表顶部让出了半透明标题栏的高度', (tester) async {
    // 让 body 从栏下穿过（extendBodyBehindAppBar）之后，内容的起点必须
    // 自己下移一个栏高；漏掉这一步，第一张卡片会钻进标题底下。
    await _pump(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.extendBodyBehindAppBar, isTrue);

    final list = tester.widget<ListView>(find.byType(ListView));
    final padding = list.padding! as EdgeInsets;
    expect(padding.top, greaterThan(kToolbarHeight));
  });
}
