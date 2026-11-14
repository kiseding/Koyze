import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'route_entrance_gate.dart';

/// Keeps song order row-major while switching between a vertical list and a
/// two-column grid in landscape windows.
///
/// 入场动效期间会把滚动缓存区（`cacheExtent`，默认 250px ≈ 3.5 行）临时收到 0：
/// 卡片展开那一帧只有「屏幕里这一屏」是用户看得见的，屏幕外那几行纯属白建
/// （实测建的行 15 → 12，该帧 46ms → 39ms）。动效播完立刻恢复调用方给的值，
/// 所以滚动预取、快速滑动时不出白块的行为和以前完全一样。
///
/// 注意方向：把缓存区调**大**（比如"屏幕外 5 行"= 360px）比默认更费，别当成优化。
class AdaptiveSongList extends StatelessWidget {
  const AdaptiveSongList.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.itemExtent,
    this.landscapeItemExtent = 84,
    this.cacheExtent,
    this.trimCacheWhileEntering = true,
    this.physics,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final double landscapeItemExtent;
  final double? cacheExtent;

  /// 入场动效播放期间是否把缓存区收到 0（见类注释）。关掉只用于测试对比。
  final bool trimCacheWhileEntering;

  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
    return RouteEntranceGate(
      // 恢复缓存区会多建几行；这一帧落在动效末段——那里位移最慢，
      // 掉一帧最看不出来，比让动效起步时顿一下好。
      builder: (context, settled) => _buildList(
        context,
        settled ? cacheExtent : (trimCacheWhileEntering ? 0 : cacheExtent),
      ),
    );
  }

  Widget _buildList(BuildContext context, double? cacheExtent) {
    final size = MediaQuery.sizeOf(context);
    final physicalSize = View.of(context).physicalSize;
    final landscape =
        size.width > size.height || physicalSize.width > physicalSize.height;
    if (!landscape) {
      return ListView.builder(
        controller: controller,
        padding: padding,
        itemExtent: itemExtent,
        scrollCacheExtent: cacheExtent == null
            ? null
            : ScrollCacheExtent.pixels(cacheExtent),
        physics: physics,
        keyboardDismissBehavior: keyboardDismissBehavior,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return GridView.builder(
      controller: controller,
      padding: padding,
      scrollCacheExtent: cacheExtent == null
          ? null
          : ScrollCacheExtent.pixels(cacheExtent),
      physics: physics,
      keyboardDismissBehavior: keyboardDismissBehavior,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: landscapeItemExtent,
        crossAxisSpacing: 8,
        mainAxisSpacing: 4,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
