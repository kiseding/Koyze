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

    test('空存储时默认开启、样式为柱状', () async {
      final storage = await storageWith(<String, Object>{});
      final notifier = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      expect(notifier.value.enabled, isTrue);
      expect(notifier.value.style, SpectrumStyle.bars);
    });

    test('拨开关与换样式都落盘，重建 notifier 能读回来', () async {
      final storage = await storageWith(<String, Object>{});
      final first = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      await first.setStyle(SpectrumStyle.ribbon);
      await first.setEnabled(false);

      final second = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);
      expect(second.value.style, SpectrumStyle.ribbon);
      expect(second.value.enabled, isFalse);
    });

    test('未知样式名退回柱状，坏 enabled 退回默认', () async {
      final storage = await storageWith(<String, Object>{
        'player_spectrum_v1': '{"enabled":"yes","style":"spiral"}',
      });
      final notifier = PlayerSpectrumNotifier(storage: () async => storage);
      await Future<void>.delayed(Duration.zero);

      // 一份坏掉的设置不该让播放器起不来，也不该让频谱消失。
      expect(notifier.value.enabled, isTrue);
      expect(notifier.value.style, SpectrumStyle.bars);
    });

    test('样式名是稳定字符串，改枚举名不会让旧设置失效', () {
      // 断言具体的字面量，而不是 enum.name：后者一改名就把用户的设置弄丢。
      expect(SpectrumStyle.bars.storageValue, 'bars');
      expect(SpectrumStyle.pills.storageValue, 'pills');
      expect(SpectrumStyle.mirror.storageValue, 'mirror');
      expect(SpectrumStyle.wave.storageValue, 'wave');
      expect(SpectrumStyle.ribbon.storageValue, 'ribbon');
      for (final style in SpectrumStyle.values) {
        expect(
          SpectrumStyle.fromStorage(style.storageValue),
          style,
          reason: '每个 storageValue 都必须能被解析回自身',
        );
      }
    });

    test('相等性与 JSON 往返', () {
      const settings = PlayerSpectrumSettings(
        enabled: false,
        style: SpectrumStyle.mirror,
      );
      final restored = PlayerSpectrumSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.hashCode, settings.hashCode);
      // 缺字段的旧数据也要能读：升级后不该丢用户已选的样式。
      expect(
        PlayerSpectrumSettings.fromJson(const {'style': 'wave'}).style,
        SpectrumStyle.wave,
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
        // 五种样式都必须落到画布上。mirror 只占中线两侧、wave/ribbon 是
        // 细线，像素数差别很大，所以只断言「有相当量的不透明像素」。
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

    test('镜像样式上下对称', () async {
      final data = await rasterize(
        SpectrumPainter(
          display: bands,
          peak: bands,
          style: SpectrumStyle.mirror,
          accent: const Color(0xFF8B82EA),
          trackColor: const Color(0xFF333333),
        ),
      );
      final bytes = data.buffer.asUint8List();
      const width = 120;
      const height = 40;

      int alphaAt(int x, int y) => bytes[(y * width + x) * 4 + 3];

      // 取一根足够高的柱子所在列，比较相对中线对称的两个像素。
      var checked = 0;
      for (var x = 0; x < width; x += 3) {
        for (var dy = 1; dy < height ~/ 2 - 2; dy++) {
          final top = alphaAt(x, height ~/ 2 - 1 - dy);
          final bottom = alphaAt(x, height ~/ 2 + dy);
          if (top > 40 || bottom > 40) {
            expect(
              (top - bottom).abs(),
              lessThan(90),
              reason: '列 $x 偏移 $dy 处上下不对称（$top vs $bottom）',
            );
            checked++;
            break;
          }
        }
      }
      expect(checked, greaterThan(5), reason: '没找到足够的柱子列来验证对称');
    });

    test('比例尺一致：更高的幅值画出更高的柱', () async {
      Future<int> columnHeight(double value) async {
        final data = await rasterize(
          SpectrumPainter(
            display: [value],
            peak: [value],
            style: SpectrumStyle.pills,
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
  });
}