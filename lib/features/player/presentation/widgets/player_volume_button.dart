import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../l10n/app_strings.dart';
import '../../../settings/presentation/settings_provider.dart';

/// Full-player volume control. Sits beside download and opens upward.
class PlayerVolumeButton extends ConsumerStatefulWidget {
  const PlayerVolumeButton({super.key, this.horizontal = false});

  /// Landscape players use a sideways slider; portrait keeps the tall one.
  final bool horizontal;

  @override
  ConsumerState<PlayerVolumeButton> createState() => _PlayerVolumeButtonState();
}

class _PlayerVolumeButtonState extends ConsumerState<PlayerVolumeButton>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnimationController _panel;
  bool _open = false;
  int _sequence = 0;
  double? _unmuteLevel;

  @override
  void initState() {
    super.initState();
    _panel = AnimationController(
      vsync: this,
      duration: MotionDuration.normal,
      reverseDuration: MotionDuration.micro,
    );
  }

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  Future<void> _setOpen(bool open) async {
    if (_open == open) return;
    _open = open;
    final sequence = ++_sequence;
    if (open) {
      _panel.value = 0;
      _portal.show();
      if (mounted) setState(() {});
      if (reduceMotion(context)) {
        _panel.value = 1;
        return;
      }
      await _panel.forward();
      return;
    }
    if (!reduceMotion(context)) {
      await _panel.reverse();
    } else {
      _panel.value = 0;
    }
    if (!mounted || sequence != _sequence) return;
    _portal.hide();
    setState(() {});
  }

  void _setVolume(double value) {
    ref.read(playbackVolumeProvider.notifier).setVolume(value);
  }

  void _toggleMute(double volume) {
    HapticFeedback.selectionClick();
    if (volume <= 0.001) {
      _setVolume(_unmuteLevel ?? 0.8);
      return;
    }
    _unmuteLevel = volume;
    _setVolume(0);
  }

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(playbackVolumeProvider);
    final s = S.of(context);
    final icon = _volumeIcon(volume);
    final active = _open || volume < 0.999;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setOpen(false),
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: widget.horizontal
                  ? Alignment.topRight
                  : Alignment.topCenter,
              followerAnchor: widget.horizontal
                  ? Alignment.bottomRight
                  : Alignment.bottomCenter,
              offset: Offset(0, widget.horizontal ? -4 : -6),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _panel,
                  curve: MotionCurve.easeOut,
                  reverseCurve: MotionCurve.easeIn,
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: widget.horizontal
                        ? const Offset(0, 0.35)
                        : Offset.zero,
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _panel,
                      curve: MotionCurve.easeOut,
                      reverseCurve: MotionCurve.easeIn,
                    ),
                  ),
                  child: ScaleTransition(
                    alignment: widget.horizontal
                        ? Alignment.bottomRight
                        : Alignment.bottomCenter,
                    scale: Tween<double>(begin: 0.92, end: 1).animate(
                      CurvedAnimation(
                        parent: _panel,
                        curve: MotionCurve.iosSpring,
                        reverseCurve: MotionCurve.easeIn,
                      ),
                    ),
                    child: _VolumePanel(
                      volume: volume,
                      horizontal: widget.horizontal,
                      onChanged: _setVolume,
                      onMute: () => _toggleMute(volume),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Pressable(
          tooltip: s.volume,
          semanticLabel: s.volume,
          selected: _open,
          scale: 0.9,
          onTap: () => _setOpen(!_open),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AnimatedSwitcher(
              duration: motionDuration(context, MotionDuration.micro),
              switchInCurve: MotionCurve.iosSpring,
              switchOutCurve: MotionCurve.easeIn,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Icon(
                icon,
                key: ValueKey<IconData>(icon),
                color: active
                    ? AppColors.accentOf(context)
                    : AppColors.secondaryText(context),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _volumeIcon(double volume) {
  if (volume <= 0.001) return Icons.volume_off_rounded;
  if (volume < 0.45) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

class _VolumePanel extends StatelessWidget {
  const _VolumePanel({
    required this.volume,
    required this.horizontal,
    required this.onChanged,
    required this.onMute,
  });

  final double volume;
  final bool horizontal;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    final percentLabel = AnimatedSwitcher(
      duration: motionDuration(context, MotionDuration.micro),
      child: Text(
        '$percent',
        key: ValueKey<int>(percent),
        textAlign: TextAlign.center,
        maxLines: 1,
        style: TextStyle(
          color: AppColors.onScaffold(context),
          fontSize: horizontal ? 14 : 15,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    final mute = Pressable(
      semanticLabel: volume <= 0.001
          ? S.of(context).unmute
          : S.of(context).mute,
      scale: 0.9,
      onTap: onMute,
      child: Padding(
        padding: EdgeInsets.all(horizontal ? 6 : 6),
        child: Icon(
          volume <= 0.001
              ? Icons.volume_off_rounded
              : Icons.volume_mute_rounded,
          size: 22,
          color: AppColors.secondaryText(context),
        ),
      ),
    );
    final track = _VolumeTrack(
      volume: volume,
      horizontal: horizontal,
      onChanged: onChanged,
    );
    return Material(
      key: const Key('volume-panel'),
      type: MaterialType.transparency,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(horizontal ? 20 : 28),
        padding: horizontal
            ? const EdgeInsets.fromLTRB(8, 8, 12, 8)
            : const EdgeInsets.fromLTRB(8, 14, 8, 10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: horizontal ? 0.16 : 0.28),
            blurRadius: horizontal ? 12 : 24,
            offset: Offset(0, horizontal ? 4 : 10),
          ),
        ],
        child: horizontal
            ? SizedBox(
                width: _VolumeTrack.panelLength - 20,
                child: Row(
                  children: [
                    mute,
                    const Spacer(),
                    track,
                    const Spacer(),
                    SizedBox(width: 34, child: percentLabel),
                  ],
                ),
              )
            : SizedBox(
                width: _VolumeTrack.hitExtent,
                height: _VolumeTrack.panelLength - 24,
                child: Column(
                  children: [
                    percentLabel,
                    const Spacer(),
                    track,
                    const Spacer(),
                    mute,
                  ],
                ),
              ),
      ),
    );
  }
}

class _VolumeTrack extends StatelessWidget {
  const _VolumeTrack({
    required this.volume,
    required this.horizontal,
    required this.onChanged,
  });

  final double volume;
  final bool horizontal;
  final ValueChanged<double> onChanged;

  /// Halfway between the old portrait bar (148) and landscape bar (140).
  static const double length = 144;

  /// Halfway between the old portrait panel (243) and landscape panel (246).
  static const double panelLength = 244.5;

  /// Halfway between the old portrait bar (36) and landscape bar (16).
  static const double thickness = 26;
  static const double hitExtent = 36;

  double get _length => length;

  void _update(double position) {
    final next = horizontal
        ? (position / _length).clamp(0.0, 1.0)
        : (1 - position / _length).clamp(0.0, 1.0);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final track = AppColors.fill2(context);
    return GestureDetector(
      key: Key(
        horizontal ? 'volume-track-horizontal' : 'volume-track-vertical',
      ),
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _update(
        horizontal ? details.localPosition.dx : details.localPosition.dy,
      ),
      onHorizontalDragUpdate: horizontal
          ? (details) => _update(details.localPosition.dx)
          : null,
      onVerticalDragUpdate: horizontal
          ? null
          : (details) => _update(details.localPosition.dy),
      child: SizedBox(
        width: horizontal ? _length : hitExtent,
        height: horizontal ? hitExtent : _length,
        child: Center(
          child: SizedBox(
            key: const Key('volume-track-bar'),
            width: horizontal ? _length : thickness,
            height: horizontal ? thickness : _length,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(thickness / 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(thickness / 2),
                child: Align(
                  alignment: horizontal
                      ? Alignment.centerLeft
                      : Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    widthFactor: horizontal ? volume.clamp(0.0, 1.0) : 1,
                    heightFactor: horizontal ? 1 : volume.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: horizontal
                              ? Alignment.centerLeft
                              : Alignment.bottomCenter,
                          end: horizontal
                              ? Alignment.centerRight
                              : Alignment.topCenter,
                          colors: [accent, accent.withValues(alpha: 0.72)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
