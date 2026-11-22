import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/widgets/koyze_menu.dart';

Widget _host({
  required ValueChanged<String> onSelected,
  bool disableAnimations = false,
  List<String> labels = const ['First action', 'Second action'],
}) {
  return MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      size: const Size(390, 844),
    ),
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [
            KoyzePopupMenuButton<String>(
              key: const ValueKey('menu-trigger'),
              onSelected: onSelected,
              itemBuilder: (context) => [
                for (var i = 0; i < labels.length; i++)
                  PopupMenuItem<String>(
                    value: 'item$i',
                    child: Text(labels[i]),
                  ),
              ],
            ),
          ],
        ),
        body: const SizedBox.expand(),
      ),
    ),
  );
}

void _setViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('menu-trigger')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu hugs its widest label instead of the anchor width', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    await _openMenu(tester);

    final surface = tester.getRect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
    );
    // 触发按钮只有 44dp 宽，菜单曾经固定 272dp 宽，短标签右边空一大片。
    expect(surface.width, lessThan(272));
    expect(surface.width, greaterThanOrEqualTo(168));
    expect(surface.left, greaterThanOrEqualTo(12));
    expect(surface.right, lessThanOrEqualTo(390 - 12));
    expect(find.text('First action'), findsOneWidget);
  });

  testWidgets('long labels stop growing at the menu cap', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(
      _host(
        onSelected: (_) {},
        labels: const ['删除已下载的全部歌曲并清理缓存文件并同时重置播放队列让它彻底回到初始状态', '短'],
      ),
    );
    await _openMenu(tester);

    final surface = tester.getRect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
    );
    expect(surface.width, 336);
    expect(surface.right, lessThanOrEqualTo(390 - 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('菜单在三点按钮下方展开，不盖住按钮', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    final trigger = tester.getRect(find.byKey(const ValueKey('menu-trigger')));
    await _openMenu(tester);

    final surface = tester.getRect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
    );
    // 用户对三点菜单的默认预期是「从按钮下面掉出来」，按钮本身仍完整可见。
    // 旧实现两个分支都与按钮重叠（anchor.top 或 anchor.bottom - height），
    // 观感上菜单是从按钮身上长出来的。
    expect(
      surface.top,
      greaterThanOrEqualTo(trigger.bottom + 5),
      reason: '菜单顶边应在按钮底边下方留出缝隙，实际 surface=$surface '
          'trigger=$trigger',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('菜单采样背后内容做模糊，而不是只盖一层半透明底色', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    await _openMenu(tester);

    // 用户能在彩色封面/图片上看出「这个菜单没虚化」：底下的内容一条条透出来，
    // 和 App 里其它玻璃面（顶栏、弹窗、底栏）完全不是一个材质。
    // BackdropFilter 的存在就是「真的做了背景模糊」的可判定证据。
    final blur = find.descendant(
      of: find.byKey(const ValueKey('koyze-menu-morph-surface')),
      matching: find.byType(BackdropFilter),
    );
    expect(
      blur,
      findsAtLeastNWidgets(1),
      reason: '菜单必须走 GlassSurface 的背景采样，不能只靠 alpha',
    );
  });

  testWidgets('anchored menu returns the selected PopupMenuItem value', (
    tester,
  ) async {
    _setViewport(tester);
    String? selected;
    await tester.pumpWidget(_host(onSelected: (value) => selected = value));
    await _openMenu(tester);

    await tester.tap(find.text('Second action'));
    await tester.pumpAndSettle();

    expect(selected, 'item1');
    expect(find.text('Second action'), findsNothing);
  });

  testWidgets('escape dismisses the anchored menu', (tester) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}));
    await _openMenu(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
      findsNothing,
    );
    expect(find.text('First action'), findsNothing);
  });

  testWidgets('reduced motion opens and closes without a lingering route', (
    tester,
  ) async {
    _setViewport(tester);
    await tester.pumpWidget(_host(onSelected: (_) {}, disableAnimations: true));
    await _openMenu(tester);
    expect(find.text('First action'), findsOneWidget);

    await tester.tapAt(const Offset(24, 400));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('koyze-menu-morph-surface')),
      findsNothing,
    );
  });
}
