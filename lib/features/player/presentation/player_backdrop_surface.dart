import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/glass_config.dart';
import '../../../core/widgets/artwork_image.dart';

/// 一张封面铺满整块区域并虚化，不含底色与遮罩。
///
/// 播放页的背景切换要在两张封面之间交叉淡入，所以虚化必须能单独拿出
/// 一层来用；遮罩与底色由调用方叠加一次，两张叠在一起时才不会压两遍。
class PlayerBackdropArtwork extends StatelessWidget {
  const PlayerBackdropArtwork({
    super.key,
    required this.artwork,
    required this.blur,
  });

  final String? artwork;

  /// 已经换算过的生效 sigma（含性能模式缩放）。0 表示不虚化。
  final double blur;

  @override
  Widget build(BuildContext context) {
    final url = artwork;
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: Colors.transparent);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // 放在无界高度里（例如某些面板里）时 biggest 会是 Infinity，
        // OverflowBox 会直接抛断言；退回屏幕尺寸兜底。
        final side = size.isFinite && size.longestSide > 0
            ? size.longestSide
            : MediaQuery.sizeOf(context).longestSide;
        return OverflowBox(
          alignment: Alignment.center,
          minWidth: side,
          maxWidth: side,
          minHeight: side,
          maxHeight: side,
          // 背景不是「稍微虚化的封面」，而应该是一整片从封面里长出来的颜色，
          // 所以用播放页自己的档位而不是卡片档的 8。封面同时按 360 宽解码再
          // 拉满屏，细节在模糊之前就已经没了，也省掉一次全分辨率解码。
          child: ImageFiltered(
            imageFilter: AppGlass.liquidFilter(blur: blur, saturation: 1.45),
            child: ArtworkImage(
              url,
              cacheWidth: 360,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
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
  });

  final String? artwork;

  /// 生效 sigma，见 `PlayerBackdrop.effectiveBlur`。
  final double blur;

  /// 遮罩不透明度，0~1。
  final double scrim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
        PlayerBackdropArtwork(artwork: artwork, blur: blur),
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
