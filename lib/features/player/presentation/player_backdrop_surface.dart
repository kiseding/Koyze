import 'package:flutter/material.dart';

import '../../../core/performance/low_memory.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/glass_config.dart';
import '../../../core/widgets/artwork_image.dart';

/// 一张封面铺满整块区域并虚化，不含底色与遮罩。
///
/// 播放页的背景切换要在两张封面之间交叉淡入，所以虚化必须能单独拿出
/// 一层来用；遮罩与底色由调用方叠加一次，两张叠在一起时才不会压两遍。
/// 一张封面铺满整块区域并虚化，不含底色与遮罩。
///
/// 播放页的背景切换要在两张封面之间交叉淡入，所以虚化必须能单独拿出一层
/// 来用；遮罩与底色由调用方叠加一次，两张叠在一起时才不会压两遍。
///
/// [flowing] 打开后做极慢的漂移（缩放 + 微旋转 + 平移）。**变换放在虚化
/// 外层**：虚化结果缓存成一层，每帧只做一次图层变换；反过来把变换塞进
/// `ImageFiltered` 里，会让整屏模糊每帧重算一遍——正是之前卡顿的来源。
class PlayerBackdropArtwork extends StatefulWidget {
  const PlayerBackdropArtwork({
    super.key,
    required this.artwork,
    required this.blur,
    this.flowing = false,
  });

  final String? artwork;

  /// 已经换算过的生效 sigma（含性能模式缩放）。0 表示不虚化。
  final double blur;

  /// 是否缓慢漂移。
  final bool flowing;

  @override
  State<PlayerBackdropArtwork> createState() => _PlayerBackdropArtworkState();
}

class _PlayerBackdropArtworkState extends State<PlayerBackdropArtwork>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(PlayerBackdropArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flowing != widget.flowing) _syncController();
  }

  void _syncController() {
    if (!widget.flowing) {
      _controller?.stop();
      return;
    }
    _controller ??= AnimationController(
      vsync: this,
      // 慢到看不出"在动"，只在过一会儿回来时发现构图变了。
      duration: const Duration(seconds: 26),
    )..repeat(reverse: true);
    if (!_controller!.isAnimating) _controller!.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.artwork;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Colors.transparent);
    }
    // 性能模式 / 减弱动效时不漂移：这一层只是装饰，不值得为它每帧变换整屏。
    final animate =
        widget.flowing && !LowMemory.active && !reduceMotion(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 放在无界高度里（例如某些面板里）时 biggest 会是 Infinity，
        // OverflowBox 会直接抛断言；退回屏幕尺寸兜底。
        final side = size.isFinite && size.longestSide > 0
            ? size.longestSide
            : MediaQuery.sizeOf(context).longestSide;
        final layer = RepaintBoundary(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: side,
            maxWidth: side,
            minHeight: side,
            maxHeight: side,
            // 背景不是「稍微虚化的封面」，而应该是一整片从封面里长出来的颜色，
            // 所以用播放页自己的档位而不是卡片档的 8。封面同时按 360 宽解码再
            // 拉满屏，细节在模糊之前就已经没了，也省掉一次全分辨率解码。
            child: ImageFiltered(
              imageFilter: AppGlass.liquidFilter(
                blur: widget.blur,
                saturation: 1.45,
              ),
              child: ArtworkImage(
                url,
                cacheWidth: 360,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        );

        final controller = _controller;
        if (!animate || controller == null) return layer;

        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(controller.value);
            return Transform.translate(
              offset: Offset((t - 0.5) * 18, (0.5 - t) * 12),
              child: Transform.rotate(
                angle: (t - 0.5) * 0.012,
                child: Transform.scale(scale: 1.08 + t * 0.05, child: child),
              ),
            );
          },
          child: layer,
        );
      },
    );
  }
}

/// 播放页背景的完整合成：底色 + 虚化封面 + 可读性遮罩。
///
/// 播放页与设置里的预览面板共用这一层，所以「预览看到的」和「真的进去
/// 看到的」不会因为参数取整方式不同而对不上。
class PlayerBackdropSurface extends StatelessWidget {
  const PlayerBackdropSurface({
    super.key,
    required this.artwork,
    required this.blur,
    required this.scrim,
    this.flowing = false,
  });

  final String? artwork;

  /// 生效 sigma，见 `PlayerBackdrop.effectiveBlur`。
  final double blur;

  /// 遮罩不透明度，0~1。
  final double scrim;

  /// 是否让背景缓慢漂移。
  final bool flowing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        PlayerBackdropArtwork(
          artwork: artwork,
          blur: blur,
          flowing: flowing,
        ),
        ColoredBox(
          color: GlassEffectConfig.playerBackdropScrimFor(
            Theme.of(context).brightness,
            opacity: scrim,
          ),
        ),
      ],
    );
  }
}
