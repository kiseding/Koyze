import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/home/presentation/widgets/mini_bar.dart';

/// 迷你播放栏的几何是「morph 起落点」的唯一真相：
/// 全屏播放器收起时要精确落到这条栏的矩形上，算错就会出现
/// "卡一下再跳"的观感。
///
/// 这里直接测 `KoyzeMiniBarMetrics` 的输出，而不是去源码里找
/// `kMiniBarHeight = 66` 这行字——后者在重命名常量时会误报，
/// 在几何算错时反而可能仍然通过。
void main() {
  group('常量契约', () {
    test('竖屏栏高与内边距', () {
      expect(kMiniBarHeight, 66);
      expect(kMiniBarSideMargin, 12);
      expect(kMiniBarBottomGap, 8);
      expect(kMiniBarArtworkSize, 50);
      expect(kMiniBarPaddingLeft, 8);
      expect(kMiniBarPaddingRight, 7);
      expect(kMiniBarControlsWidth, 180);
    });

    test('水平内边距之和小于栏高，否则封面会被压扁', () {
      expect(
        kMiniBarPaddingLeft + kMiniBarPaddingRight,
        lessThan(kMiniBarHeight),
      );
    });
  });

  group('KoyzeMiniBarMetrics', () {
    const screen = Size(400, 800);

    test('栏贴底边并留出安全区', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 34);
      expect(m.barRect.bottom, screen.height - 34 - kMiniBarBottomGap);
      expect(m.barRect.top, screen.height - 34 - kMiniBarBottomGap - kMiniBarHeight);
      expect(m.barRect.height, kMiniBarHeight);
    });

    test('栏宽等于屏宽减去两侧边距', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 0);
      expect(m.barRect.left, kMiniBarSideMargin);
      expect(m.barRect.width, screen.width - kMiniBarSideMargin * 2);
    });

    test('无安全区时也贴住底边', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 0);
      expect(m.barRect.bottom, screen.height - kMiniBarBottomGap);
    });

    test('封面矩形在栏内垂直居中、水平靠左内边距', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 0);
      expect(m.artworkRect.left, m.barRect.left + kMiniBarPaddingLeft);
      expect(m.artworkRect.width, kMiniBarArtworkSize);
      expect(m.artworkRect.height, kMiniBarArtworkSize);
      expect(
        m.artworkRect.center.dy,
        closeTo(m.barRect.center.dy, 0.01),
        reason: '封面应在栏内垂直居中',
      );
    });

    test('播放键在右侧控件区内、垂直居中，且不越过封面', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 0);
      // 控件区是「栏右侧、扣掉右内边距、宽 kMiniBarControlsWidth」的一条带，
      // 播放键在其中水平居中。
      final controlsLeft = m.barRect.right - kMiniBarPaddingRight - kMiniBarControlsWidth;
      expect(
        m.playRect.center.dx,
        closeTo(controlsLeft + kMiniBarControlsWidth / 2, 0.01),
      );
      expect(m.playRect.center.dy, closeTo(m.barRect.center.dy, 0.01));
      expect(m.playRect.width, 38);
      expect(m.playRect.height, 38);
      expect(
        m.playRect.left,
        greaterThan(m.artworkRect.right),
        reason: '播放键必须在封面右侧，否则会和封面重叠',
      );
      expect(
        m.playRect.right,
        lessThanOrEqualTo(m.barRect.right - kMiniBarPaddingRight + 0.01),
        reason: '播放键不能越出栏的右内边距',
      );
    });

    test('内容避让高度覆盖整条栏', () {
      final m = KoyzeMiniBarMetrics(screen: screen, bottomInset: 20);
      expect(
        m.contentObstruction,
        greaterThanOrEqualTo(20 + kMiniBarHeight),
        reason: '滚动内容必须至少避让到栏的顶边',
      );
    });

    test('极窄屏不产生负宽度', () {
      final m = KoyzeMiniBarMetrics(
        screen: const Size(10, 800),
        bottomInset: 0,
      );
      expect(m.barRect.width, greaterThanOrEqualTo(0));
      expect(m.barRect.width, lessThanOrEqualTo(10));
    });

    test('安全区变化时栏高不变，只整体上移', () {
      final a = KoyzeMiniBarMetrics(screen: screen, bottomInset: 0);
      final b = KoyzeMiniBarMetrics(screen: screen, bottomInset: 40);
      expect(b.barRect.height, a.barRect.height);
      expect(a.barRect.top - b.barRect.top, 40);
    });
  });
}
