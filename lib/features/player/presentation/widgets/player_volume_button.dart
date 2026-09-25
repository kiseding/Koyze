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
  const PlayerVolumeButton({super.key});

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
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -6),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _panel,
                  curve: MotionCurve.easeOut,
                  reverseCurve: MotionCurve.easeIn,
                ),
                child: ScaleTransition(
                  alignment: Alignment.bottomCenter,
                  scale: Tween<double>(begin: 0.86, end: 1).animate(
                    CurvedAnimation(
                      parent: _panel,
                      curve: MotionCurve.iosSpring,
                      reverseCurve: MotionCurve.easeIn,
                    ),
                  ),
                  child: _VolumePanel(
                    volume: volume,
                    onChanged: _setVolume,
                    onMute: () => _toggleMute(volume),
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
    required this.onChanged,
    required this.onMute,
  });

  final double volume;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Material(
      type: MaterialType.transparency,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: motionDuration(context, MotionDuration.micro),
                child: Text(
                  '$percent',
                  key: ValueKey<int>(percent),
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _VolumeTrack(volume: volume, onChanged: onChanged),
              const SizedBox(height: 6),
              Pressable(
                semanticLabel: volume <= 0.001
                    ? S.of(context).unmute
                    : S.of(context).mute,
                scale: 0.9,
                onTap: onMute,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    volume <= 0.001
                        ? Icons.volume_off_rounded
                        : Icons.volume_mute_rounded,
                    size: 20,
                    color: AppColors.secondaryText(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VolumeTrack extends StatelessWidget {
  const _VolumeTrack({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  static const double _height = 148;

  void _update(double dy) {
    final next = (1 - dy / _height).clamp(0.0, 1.0);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final track = AppColors.fill2(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _update(details.localPosition.dy),
      onVerticalDragUpdate: (details) => _update(details.localPosition.dy),
      child: SizedBox(
        width: 36,
        height: _height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: volume.clamp(0.0, 1.0),
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [accent, accent.withValues(alpha: 0.72)],
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
