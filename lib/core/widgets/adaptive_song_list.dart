import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Keeps song order row-major while switching between a vertical list and a
/// two-column grid in landscape windows.
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
  final ScrollPhysics? physics;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) {
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
            : ScrollCacheExtent.pixels(cacheExtent!),
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
          : ScrollCacheExtent.pixels(cacheExtent!),
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
