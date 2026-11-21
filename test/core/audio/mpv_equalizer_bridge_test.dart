import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/audio/equalizer_bridge.dart';
import 'package:koyze/core/audio/mpv_equalizer_bridge.dart';
import 'package:koyze/features/equalizer/domain/equalizer_settings.dart';

void main() {
  group('buildMpvEqualizerFilters', () {
    test('关闭时返回空列表，链路里不挂任何滤镜', () {
      expect(
        buildMpvEqualizerFilters(
          enabled: false,
          gains: const [6, 6, 6, 6, 6],
        ),
        isEmpty,
      );
    });

    test('全平（0 dB）时不挂滤镜', () {
      // 挂一条全零的滤镜链只会白烧 CPU，听感完全一样。
      expect(
        buildMpvEqualizerFilters(enabled: true, gains: const [0, 0, 0, 0, 0]),
        isEmpty,
      );
      expect(
        buildMpvEqualizerFilters(
          enabled: true,
          gains: const [0.04, -0.04, 0, 0, 0],
        ),
        isEmpty,
      );
    });

    test('每个非零频段生成一个滤镜条目，按频率顺序排列', () {
      final filters = buildMpvEqualizerFilters(
        enabled: true,
        gains: const [3, 0, -2.5, 0, 1.25],
      );
      // 五段布局相邻相隔约 1.95 个倍频程，带宽按此自动推算（两端夹在
      // 0.5~2 的上限内，因此都是 1.95）。
      expect(filters, <String>[
        'equalizer=f=60:width_type=o:width=1.94:g=3',
        'equalizer=f=910:width_type=o:width=1.98:g=-2.5',
        'equalizer=f=14000:width_type=o:width=1.96:g=1.25',
      ]);
    });

    test('增益被夹到布局的上下限，越界值不会写到 mpv', () {
      final filters = buildMpvEqualizerFilters(
        enabled: true,
        gains: const [40, -40, 0, 0, 0],
      );
      expect(filters, <String>[
        'equalizer=f=60:width_type=o:width=1.94:g=12',
        'equalizer=f=230:width_type=o:width=1.96:g=-12',
      ]);
    });

    test('增益数量少于频段数时，缺的段按 0 dB 处理', () {
      // 老版本只存了 1 段的自定义曲线，不应因此崩掉或错位。
      expect(
        buildMpvEqualizerFilters(enabled: true, gains: const [5]),
        <String>['equalizer=f=60:width_type=o:width=1.94:g=5'],
      );
    });

    test('非有限值被忽略，不会写出 NaN', () {
      expect(
        buildMpvEqualizerFilters(
          enabled: true,
          gains: const [double.nan, 2, double.infinity, 0, 0],
        ),
        <String>['equalizer=f=230:width_type=o:width=1.96:g=2'],
      );
    });

    test('小数增益不会被写成 2.50 这种冗余形式', () {
      final filters = buildMpvEqualizerFilters(
        enabled: true,
        gains: const [2.5, -0.5, 0, 0, 0],
      );
      expect(filters, <String>[
        'equalizer=f=60:width_type=o:width=1.94:g=2.5',
        'equalizer=f=230:width_type=o:width=1.96:g=-0.5',
      ]);
    });
  });

  group('mpvEqualizerBandWidthOctaves', () {
    test('五段布局：带宽覆盖到相邻频段的中点', () {
      // 60/230/910/3600/14000 的相邻间隔都是 1.94~1.98 个倍频程。
      // 滤波器必须单侧伸到间距的一半（约 0.97）才能把两个频段接上，
      // 也就是总宽约 1.95。固定写 1 会让每段只覆盖一半，中间留出缺口，
      // 五个频段各自提升在听感上几乎等于没开。
      for (var i = 0; i < kMpvEqualizerLayout.bandCount; i++) {
        final width = mpvEqualizerBandWidthOctaves(kMpvEqualizerLayout, i);
        expect(
          width,
          closeTo(1.95, 0.06),
          reason: '第 $i 段（${kMpvEqualizerLayout.centerFrequencies[i]}Hz）',
        );
      }
    });

    test('十段布局：间距正好一个倍频程时带宽回到 1', () {
      // 十段布局的相邻间隔是整倍频程，中点距离 0.5，总宽就是 1 ——
      // 与老代码固定写 1 的结果一致，说明这条改动不会把密布局弄坏。
      const tenBand = EqualizerBandLayout(
        minDecibels: -15,
        maxDecibels: 15,
        centerFrequencies: <double>[
          32,
          64,
          125,
          250,
          500,
          1000,
          2000,
          4000,
          8000,
          16000,
        ],
      );
      for (var i = 0; i < tenBand.bandCount; i++) {
        expect(
          mpvEqualizerBandWidthOctaves(tenBand, i),
          closeTo(1, 0.05),
          reason: '第 $i 段（${tenBand.centerFrequencies[i]}Hz）',
        );
      }
    });

    test('带宽被夹在上下限内，不会出现极端值', () {
      // 极疏（两个频段相隔 8 个倍频程）与极密（相隔 1/4 个倍频程）。
      const sparse = EqualizerBandLayout(
        minDecibels: -12,
        maxDecibels: 12,
        centerFrequencies: <double>[50, 12800],
      );
      const dense = EqualizerBandLayout(
        minDecibels: -12,
        maxDecibels: 12,
        centerFrequencies: <double>[1000, 1190, 1410],
      );
      for (final layout in <EqualizerBandLayout>[sparse, dense]) {
        for (var i = 0; i < layout.bandCount; i++) {
          final width = mpvEqualizerBandWidthOctaves(layout, i);
          expect(width, greaterThanOrEqualTo(kEqualizerMinBandWidthOctaves));
          expect(width, lessThanOrEqualTo(kEqualizerMaxBandWidthOctaves));
        }
      }
    });

    test('单个频段退回 1 倍频程，不抛异常', () {
      const single = EqualizerBandLayout(
        minDecibels: -12,
        maxDecibels: 12,
        centerFrequencies: <double>[1000],
      );
      expect(mpvEqualizerBandWidthOctaves(single, 0), 1);
    });
  });

  test('拼成一条 af 字符串时用逗号分隔（诊断输出用）', () {
    expect(
      buildMpvEqualizerFilter(enabled: true, gains: const [3, 0, -3, 0, 0]),
      'equalizer=f=60:width_type=o:width=1.94:g=3,'
      'equalizer=f=910:width_type=o:width=1.98:g=-3',
    );
    expect(buildMpvEqualizerFilter(enabled: false, gains: const [3]), '');
  });

  test('mpv 频段布局与回退布局保持一致', () {
    // 用户的「自定义」曲线是按频段索引存的。两边频率一旦分叉，
    // 已经保存的曲线会整体错位，而且不会有任何报错。
    expect(
      kMpvEqualizerLayout.centerFrequencies,
      kFallbackEqualizerLayout.centerFrequencies,
    );
    expect(kMpvEqualizerLayout.minDecibels, kFallbackEqualizerLayout.minDecibels);
    expect(kMpvEqualizerLayout.maxDecibels, kFallbackEqualizerLayout.maxDecibels);
  });
}