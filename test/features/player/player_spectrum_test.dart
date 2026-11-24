import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/audio_spectrum.dart';
import 'package:koyze/core/storage/storage_service.dart';
import 'package:koyze/features/player/domain/player_spectrum_settings.dart';
import 'package:koyze/features/player/presentation/widgets/player_spectrum_painter.dart';
import 'package:koyze/features/settings/presentation/settings_notifiers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 频谱条的三块：持久化设置、频谱帧的数据清洗、五种样式的绘制。
///
/// 绘制部分是真的把 painter 画进一张图再看像素——形状类的代码（贝塞尔、
/// 镜像、渐变）靠读代码看不出对不对，只能验证「应该有色块的地方有色块」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerSpectrumSettings', () {
    Future<StorageService> storageWith(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return StorageService.forTesting(await SharedPreferences.getInstance());
    }

    test('空存储时默认关闭、样式为光点', () async {
      final storage = await storageWith(<String, Object>{});
      final notifier = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      // 默认关：这一行高度留给「下一句歌词」，信息密度更高。
      expect(notifier.value.enabled, isFalse);
      expect(notifier.value.style, SpectrumStyle.dots);
    });

    test('拨开关与换样式都落盘，重建 notifier 能读回来', () async {
      final storage = await storageWith(<String, Object>{});
      final first = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      await first.setStyle(SpectrumStyle.steps);
      await first.setEnabled(false);

      final second = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);
      expect(second.value.style, SpectrumStyle.steps);
      expect(second.value.enabled, isFalse);
    });

    test('未知样式名退回光点，坏 enabled 退回默认', () async {
      final storage = await storageWith(<String, Object>{
        'player_spectrum_v1': '{"enabled":"yes","style":"spiral"}',
      });
      final notifier = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      // 一份坏掉的设置不该让播放器起不来。`enabled` 不是 bool 时退回默认
      // 值（现在是 false），样式名不认识时退回默认的光点。
      expect(notifier.value.enabled, isFalse);
      expect(notifier.value.style, SpectrumStyle.dots);
    });

    test('样式名是稳定字符串，改枚举名不会让旧设置失效', () {
      // 断言具体的字面量，而不是 enum.name：后者一改名就把用户的设置弄丢。
      expect(SpectrumStyle.bars.storageValue, 'bars');
      expect(SpectrumStyle.leds.storageValue, 'leds');
      expect(SpectrumStyle.dots.storageValue, 'dots');
      expect(SpectrumStyle.ridges.storageValue, 'ridges');
      expect(SpectrumStyle.steps.storageValue, 'steps');
      for (final style in SpectrumStyle.values) {
        expect(
          SpectrumStyle.fromStorage(style.storageValue),
          style,
          reason: '每个 storageValue 都必须能被解析回自身',
        );
      }
    });

    test('光点排在样式面板第一位，也是默认样式', () {
      // 面板直接按 values 顺序渲染，所以「第一项」和「默认值」必须同时改，
      // 否则用户看到的选中项会落在列表中间。
      expect(SpectrumStyle.values.first, SpectrumStyle.dots);
      expect(const PlayerSpectrumSettings().style, SpectrumStyle.dots);
    });

    test('相等性与 JSON 往返', () {
      const settings = PlayerSpectrumSettings(
        enabled: false,
        style: SpectrumStyle.dots,
      );
      final restored = PlayerSpectrumSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.hashCode, settings.hashCode);
      // 缺字段的旧数据也要能读：升级后不该丢用户已选的样式。
      expect(
        PlayerSpectrumSettings.fromJson(const {'style': 'steps'}).style,
        SpectrumStyle.steps,
      );
    });
  });

  group('SpectrumFrame', () {
    test('全零或极小值判为静音', () {
      expect(
        const SpectrumFrame(bands: [0, 0, 0]).isSilent,
        isTrue,
      );
      // 阈值 0.004：mpv 在极安静的段落仍会吐出千分之几的残值，
      // 把它们当有声会让「暂停后停下动画」失效。
      expect(
        const SpectrumFrame(bands: [0.001, 0.003]).isSilent,
        isTrue,
      );
    });

    test('有一根柱子超过阈值就不是静音', () {
      expect(const SpectrumFrame(bands: [0, 0, 0.02]).isSilent, isFalse);
    });
  });

  group('SpectrumPainter', () {
    /// 把 painter 画进一张 ARGB 图，返回像素。
    Future<ByteData> rasterize(
      SpectrumPainter painter, {
      int width = 120,
      int height = 40,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!;
    }

    /// 统计不透明像素的数量。背景是画布默认的透明黑，因此「画上了东西」
    /// 等价于 alpha > 0。
    int opaquePixels(ByteData data) {
      final bytes = data.buffer.asUint8List();
      var count = 0;
      for (var i = 3; i < bytes.length; i += 4) {
        if (bytes[i] > 8) count++;
      }
      return count;
    }

    final bands = List<double>.generate(
      16,
      (i) => 0.25 + 0.7 * (i % 4) / 3,
    );

    for (final style in SpectrumStyle.values) {
      test('${style.storageValue} 样式会真的画出像素', () async {
        final data = await rasterize(
          SpectrumPainter(
            display: bands,
            peak: bands,
            style: style,
            accent: const Color(0xFF8B82EA),
            trackColor: const Color(0xFF333333),
          ),
        );
        // 五种样式都必须落到画布上。光点只占几个亮核、光带只有一圈边，
        // 像素数差别很大，所以只断言「有相当量的不透明像素」。
        expect(
          opaquePixels(data),
          greaterThan(120),
          reason: '${style.storageValue} 画出来几乎是空的',
        );
      });
    }

    test('空数据显示空态底纹，而不是一片空白', () async {
      final empty = await rasterize(
        const SpectrumPainter(
          display: [],
          peak: [],
          style: SpectrumStyle.bars,
          accent: Color(0xFF8B82EA),
          trackColor: Color(0xFF333333),
        ),
      );
      // 空态仍有一排等高的轨道柱，否则这块区域会变成一条纯空白，
      // 「其它元素不动」的视觉连续性就断了。
      expect(opaquePixels(empty), greaterThan(0));
    });

    test('电平样式是分段的：列内存在未点亮的暗带', () async {
      final data = await rasterize(
        SpectrumPainter(
          display: List<double>.filled(24, 0.55),
          peak: List<double>.filled(24, 0.55),
          style: SpectrumStyle.leds,
          accent: const Color(0xFF8B82EA),
          trackColor: const Color(0xFF333333),
        ),
      );
      final bytes = data.buffer.asUint8List();
      const width = 120;
      const height = 40;
      int alphaAt(int x, int y) => bytes[(y * width + x) * 4 + 3];

      // 逐列数「亮 → 暗」的切换次数。电平表每一格之间必有缝，柱状没有；
      // 这条断言就是在钉住「分段」这个结构特征，而不是「画了东西」。
      var best = 0;
      for (var x = 0; x < width; x++) {
        var transitions = 0;
        var previousLit = false;
        for (var y = 0; y < height; y++) {
          final lit = alphaAt(x, y) > 110;
          if (previousLit && !lit) transitions++;
          previousLit = lit;
        }
        if (transitions > best) best = transitions;
      }
      expect(best, greaterThanOrEqualTo(2), reason: '电平表没画出分段，等于一根细柱');
    });

    test('光点样式是亮点加细尾，不是实心柱', () async {
      Future<int> brightPixels(SpectrumStyle style) async {
        final data = await rasterize(
          SpectrumPainter(
            display: List<double>.filled(24, 0.55),
            peak: List<double>.filled(24, 0.55),
            style: style,
            accent: const Color(0xFF8B82EA),
            trackColor: const Color(0xFF333333),
          ),
        );
        final bytes = data.buffer.asUint8List();
        var count = 0;
        for (var i = 3; i < bytes.length; i += 4) {
          if (bytes[i] > 150) count++;
        }
        return count;
      }

      final bars = await brightPixels(SpectrumStyle.bars);
      final dots = await brightPixels(SpectrumStyle.dots);
      // 同样幅值下，柱状是整片亮，光点只有几个亮核加一根淡尾线。
      // 若两者像素数接近，说明光点退化成了「换皮柱子」。
      expect(
        dots,
        lessThan(bars ~/ 2),
        reason: '光点的亮像素（$dots）和柱状（$bars）太接近，形状没有真正区分开',
      );
    });

    test('阶梯把连续幅值量化到有限档位', () async {
      // 24 列幅值平滑递增，跨满量程。不做量化时会有二十来种不同的柱高；
      // 量化后只允许出现个位数种高度——这是这一档和柱状的根本差别。
      final values = [
        for (var i = 0; i < 24; i++) (0.10 + i * 0.034).clamp(0.0, 1.0),
      ];
      final data = await rasterize(
        SpectrumPainter(
          display: values,
          peak: const [],
          style: SpectrumStyle.steps,
          accent: const Color(0xFF8B82EA),
          trackColor: const Color(0xFF333333),
        ),
      );
      final bytes = data.buffer.asUint8List();
      const width = 120;
      const height = 40;
      int alphaAt(int x, int y) => bytes[(y * width + x) * 4 + 3];

      // 每列取最上面的不透明像素。列宽 5px，取中心。
      final tops = <int>{};
      for (var column = 0; column < values.length; column++) {
        final x = column * 5 + 2;
        var top = height;
        for (var y = 0; y < height; y++) {
          if (alphaAt(x, y) > 40) {
            top = y;
            break;
          }
        }
        tops.add(top);
      }

      expect(
        tops.length,
        lessThanOrEqualTo(9),
        reason: '柱高种类太多（${tops.length} 种），说明没有量化成台阶',
      );
      expect(tops.length, greaterThan(3), reason: '整条被压成了一级，没有台阶感');
    });

    test('比例尺一致：更高的幅值画出更高的柱', () async {
      Future<int> columnHeight(double value) async {
        final data = await rasterize(
          SpectrumPainter(
            display: [value],
            peak: [value],
            style: SpectrumStyle.bars,
            accent: const Color(0xFF8B82EA),
            trackColor: const Color(0xFF333333),
          ),
          width: 20,
        );
        final bytes = data.buffer.asUint8List();
        const width = 20;
        const height = 40;
        var topmost = height;
        for (var y = 0; y < height; y++) {
          for (var x = 0; x < width; x++) {
            if (bytes[(y * width + x) * 4 + 3] > 40) {
              topmost = topmost < y ? topmost : y;
              break;
            }
          }
        }
        return height - topmost;
      }

      final low = await columnHeight(0.2);
      final high = await columnHeight(0.9);
      expect(high, greaterThan(low + 8), reason: '幅值到高度的映射没有单调性');
    });

    group('重绘判定', () {
      SpectrumPainter painter(
        List<double> display, {
        required int revision,
      }) =>
          SpectrumPainter(
            display: display,
            peak: display,
            style: SpectrumStyle.bars,
            accent: const Color(0xFF8B82EA),
            trackColor: const Color(0xFF333333),
            revision: revision,
          );

      test('原地改幅值后，靠 revision 判定要重绘', () {
        // 真实链路就是这样：补间直接在同一个 List 上改元素。新旧 painter
        // 持有同一个引用，靠 identity 比较会永远认为「没变」，画面停在首帧。
        final display = List<double>.of(bands);
        final before = painter(display, revision: 0);

        display[0] = (display[0] + 0.4).clamp(0.0, 1.0);
        final after = painter(display, revision: 1);

        expect(
          after.shouldRepaint(before),
          isTrue,
          reason: '原地更新没有被识别，频谱会变成静态的',
        );
      });

      test('数据与样式都没变时不重绘', () {
        final display = List<double>.of(bands);
        expect(
          painter(display, revision: 7).shouldRepaint(painter(display, revision: 7)),
          isFalse,
          reason: '每帧都无条件重绘会白白吃掉渲染时间',
        );
      });

      test('换样式即使 revision 不变也要重绘', () {
        final display = List<double>.of(bands);
        final before = painter(display, revision: 3);
        final after = SpectrumPainter(
          display: display,
          peak: display,
          style: SpectrumStyle.steps,
          accent: const Color(0xFF8B82EA),
          trackColor: const Color(0xFF333333),
          revision: 3,
        );
        expect(after.shouldRepaint(before), isTrue);
      });
    });
  });
}