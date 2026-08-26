import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/features/player/domain/music_item.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import '../motion/motion_tokens.dart';
import 'app_notification.dart';
import 'fx_icon_button.dart';

/// 歌曲收藏按钮：空心 → 红心，点击带 q 弹动效。
/// 用于歌单详情、榜单详情、播放队列等歌曲列表行的最右侧。
///
/// [isFavorite] 由外部传入时直接使用该值（适合长列表：页面级一次性读取
/// 收藏集合，避免每个可见行创建独立的异步收藏查询）；为 null 时按钮内部
/// 通过 provider 查询收藏状态。
class FavoriteButton extends ConsumerStatefulWidget {
  const FavoriteButton({
    super.key,
    required this.song,
    this.iconSize = 24,
    this.activeColor = const Color(0xFFFF4D6D),
    this.isFavorite,
  });

  final MusicItem song;
  final double iconSize;
  final Color activeColor;
  final bool? isFavorite;

  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  bool _pending = false;
  bool? _optimisticFavorite;

  /// q 弹缩放：1.0 → 1.45 → 0.85 → 1.0。
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.45,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.45,
        end: 0.85,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.85,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 30,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_pending) return;
    final current = _currentFavorite;
    setState(() {
      _pending = true;
      _optimisticFavorite = !current;
    });
    if (!reduceMotion(context)) unawaited(_controller.forward(from: 0));
    // Yield one frame so the heart animation/state paints before the potentially
    // expensive playlist persistence work begins.
    await Future<void>.delayed(Duration.zero);
    try {
      await ref.read(toggleFavoriteProvider)(widget.song);
    } catch (error) {
      if (!mounted) return;
      setState(() => _optimisticFavorite = current);
      showAppNotification('收藏失败: $error', type: AppNotificationType.error);
    } finally {
      if (mounted) {
        setState(() {
          _pending = false;
          _optimisticFavorite = null;
        });
      }
    }
  }

  bool get _currentFavorite {
    final optimistic = _optimisticFavorite;
    if (optimistic != null) return optimistic;
    return widget.isFavorite ??
        ref
            .watch(isSongFavoriteProvider(widget.song.identityKey))
            .valueOrNull ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = _currentFavorite;
    final heartColor = isFavorite
        ? widget.activeColor
        : AppColors.mutedText(context);
    return FxIconButton(
      tooltip: isFavorite ? '取消收藏' : '收藏',
      padding: const EdgeInsets.all(8),
      iconSize: widget.iconSize,
      onPressed: _pending ? null : _toggle,
      icon: ScaleTransition(
        scale: _scale,
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          color: heartColor,
          size: widget.iconSize,
        ),
      ),
    );
  }
}
