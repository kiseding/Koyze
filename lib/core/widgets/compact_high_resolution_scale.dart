import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Scale used when a small, high-resolution Android panel reports too low a
/// density. Car head units often do this: a 1280×720 or 1920×1080 panel is
/// exposed as mdpi/hdpi, so Flutter lays the UI out in far too many logical
/// pixels and every control looks tiny.
///
/// Phones (high density, short logical side) and correctly configured tablets
/// (density above 1.6) stay at 1. The same thresholds are applied in
/// `MainActivity` before the Flutter view is created.
double compactHighResolutionScale({
  required TargetPlatform platform,
  required Size logicalSize,
  required double devicePixelRatio,
}) {
  if (platform != TargetPlatform.android || devicePixelRatio <= 0) return 1;
  final logicalShortest = logicalSize.shortestSide;
  final physicalShortest = logicalShortest * devicePixelRatio;
  if (physicalShortest < 700 ||
      logicalShortest < 640 ||
      devicePixelRatio > 1.6) {
    return 1;
  }
  const targetLogicalShortest = 520.0;
  final scale = logicalShortest / targetLogicalShortest;
  if (scale <= 1.05) return 1;
  return scale > 2.2 ? 2.2 : scale;
}

/// Lays the app out in fewer logical pixels and scales it back up to the
/// window, so under-reported Android densities render at a usable size.
class CompactHighResolutionFrame extends StatelessWidget {
  const CompactHighResolutionFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = compactHighResolutionScale(
      platform: defaultTargetPlatform,
      logicalSize: media.size,
      devicePixelRatio: media.devicePixelRatio,
    );
    if (scale <= 1) return child;
    final size = Size(media.size.width / scale, media.size.height / scale);
    return FittedBox(
      fit: BoxFit.fill,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            devicePixelRatio: media.devicePixelRatio * scale,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: child,
        ),
      ),
    );
  }
}
