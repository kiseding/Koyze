import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/player/presentation/widgets/player_progress_bar.dart';

const Color _accent = Color(0xFF1DB954);
const Color _track = Color(0xFF43474E);

Widget _app({required double ratio, Color accent = _accent}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: PlayerProgressBar(
            ratio: ratio,
            accentColor: accent,
            trackColor: _track,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('PlayerProgressGeometry', () {
    test('起点不绘制已播放部分，滑块贴住轨道左端', () {
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 0,
      );

      expect(geometry.thumbLeft, 0);
      expect(geometry.fillWidth, 0);
    });

    test('滑块压住起点时隐藏细尖角', () {
      // center = 13，滑块左缘只离开起点 3px，不足 minVisibleFill。
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 13 / 300,
      );

      expect(geometry.thumbLeft, 3);
      expect(geometry.fillWidth, 0);
    });

    test('滑块离开起点后填充画到滑块左缘', () {
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 0.5,
      );

      expect(geometry.thumbLeft, 140);
      expect(geometry.fillWidth, 140);
    });

    test('低进度时填充不越过滑块左缘露出月牙', () {
      // center = 20，滑块左缘在 10，进度很小但仍过阈值。
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 20 / 300,
      );

      expect(geometry.thumbLeft, 10);
      // 填充只画到滑块左缘 10，而不是圆心 20，滑块左侧不会露出残影。
      expect(geometry.fillWidth, 10);
    });

    test('末端滑块不越出轨道', () {
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 1,
      );

      expect(geometry.thumbLeft, 280);
      expect(geometry.fillWidth, 300);
    });

    test('脏数据不会产生 NaN 或负宽度', () {
      final invalid = PlayerProgressGeometry.resolve(
        trackWidth: double.nan,
        ratio: double.nan,
      );
      expect(invalid.thumbLeft, 0);
      expect(invalid.fillWidth, 0);

      final narrow = PlayerProgressGeometry.resolve(
        trackWidth: 8,
        ratio: 0.5,
      );
      expect(narrow.thumbLeft, 0);
      expect(narrow.fillWidth, 0);

      final over = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 2,
      );
      expect(over.thumbLeft, 280);
      expect(over.fillWidth, 300);
    });
  });

  group('PlayerProgressBar', () {
    testWidgets('起点只显示滑块，不显示填充', (tester) async {
      await tester.pumpWidget(_app(ratio: 0));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(PlayerProgressBar));
      final thumb = tester.getRect(find.byKey(PlayerProgressBar.thumbKey));

      expect(find.byKey(PlayerProgressBar.fillKey), findsNothing);
      expect(thumb.left, bar.left);
    });

    testWidgets('超过阈值后填充从轨道左端开始', (tester) async {
      // center = 15，滑块左缘离开起点 5px，刚过阈值。
      await tester.pumpWidget(_app(ratio: 0.05));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(PlayerProgressBar));
      final fill = tester.getRect(find.byKey(PlayerProgressBar.fillKey));

      expect(fill.left, bar.left);
      // 填充画到滑块左缘 5px，而非圆心 15px。
      expect(fill.width, 5);
    });

    testWidgets('中途滑块位置对应进度且不越界', (tester) async {
      await tester.pumpWidget(_app(ratio: 0.5));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(PlayerProgressBar));
      final thumb = tester.getRect(find.byKey(PlayerProgressBar.thumbKey));

      expect(thumb.left - bar.left, 140);
      expect(thumb.width, PlayerProgressGeometry.thumbSize);
      expect(thumb.right, lessThanOrEqualTo(bar.right));
    });

    testWidgets('滑块比已播放部分更深，填充仍用强调色', (tester) async {
      await tester.pumpWidget(_app(ratio: 0.5));
      await tester.pumpAndSettle();

      final thumb = tester.widget<Container>(
        find.byKey(PlayerProgressBar.thumbKey),
      );
      final thumbColor = (thumb.decoration! as BoxDecoration).color!;
      final fill = tester.widget<DecoratedBox>(
        find.byKey(PlayerProgressBar.fillKey),
      );
      final fillColor = (fill.decoration as BoxDecoration).color;

      expect(thumbColor.computeLuminance(),
          lessThan(_accent.computeLuminance()));
      expect(fillColor, _accent);
    });
  });
}
