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

    test('填充延伸到滑块圆心并由滑块覆盖交界', () {
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 0.5,
      );

      expect(geometry.thumbLeft, 140);
      expect(geometry.fillWidth, 150);
      expect(
        geometry.fillWidth,
        geometry.thumbLeft + PlayerProgressGeometry.thumbRadius,
      );
    });

    test('低进度时填充延伸到圆心并保持直角端点', () {
      final geometry = PlayerProgressGeometry.resolve(
        trackWidth: 300,
        ratio: 20 / 300,
      );

      expect(geometry.thumbLeft, 10);
      expect(geometry.fillWidth, 20);
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

      final narrow = PlayerProgressGeometry.resolve(trackWidth: 8, ratio: 0.5);
      expect(narrow.thumbLeft, 0);
      expect(narrow.fillWidth, 0);

      final over = PlayerProgressGeometry.resolve(trackWidth: 300, ratio: 2);
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

    testWidgets('超过阈值后填充延伸到滑块下方', (tester) async {
      // center = 15，滑块左缘离开起点 5px；填充延伸到圆心并被滑块盖住。
      await tester.pumpWidget(_app(ratio: 0.05));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(PlayerProgressBar));
      final fill = tester.getRect(find.byKey(PlayerProgressBar.fillKey));

      expect(fill.left, bar.left);
      expect(fill.width, 15);
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
      final thumbDecoration = thumb.decoration! as BoxDecoration;
      final thumbColor = thumbDecoration.color!;
      final fill = tester.widget<ColoredBox>(
        find.byKey(PlayerProgressBar.fillKey),
      );

      expect(
        thumbColor.computeLuminance(),
        lessThan(_accent.computeLuminance()),
      );
      expect(fill.color, _accent);
      expect(thumbDecoration.boxShadow, isNull);
    });
  });
}
