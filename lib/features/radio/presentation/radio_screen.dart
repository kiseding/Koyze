import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../l10n/app_strings.dart';
import '../../player/presentation/player_provider.dart';
import '../domain/radio_station.dart';
import 'radio_provider.dart';

/// 网络电台页。
///
/// 内容全部来自 Radio Browser 的公开接口，不做本地收藏——想留住某个电台
/// 就直接把它当作一首歌加进收藏，走的是同一条队列，不需要第二套播放路径。
class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends ConsumerState<RadioScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 输入时不要每敲一个字就打一次电台 API：服务是志愿者在扛。
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      ref.read(radioQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final stationsAsync = ref.watch(radioStationsProvider);
    final selectedTag = ref.watch(radioTagProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          leading: FxIconButton(
            tooltip: s.back,
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            s.radio,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onScaffold(context),
            ),
          ),
        ),
        body: Column(
          children: [
            SizedBox(
              height: MediaQuery.paddingOf(context).top + kToolbarHeight,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchField(
                controller: _controller,
                hint: s.radioSearchHint,
                onChanged: _onChanged,
                onClear: () {
                  _controller.clear();
                  _debounce?.cancel();
                  ref.read(radioQueryProvider.notifier).state = '';
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _TagChip(
                    label: s.radioPopular,
                    selected: selectedTag.isEmpty,
                    onTap: () => ref.read(radioTagProvider.notifier).state = '',
                  ),
                  for (final tag in kRadioTags)
                    _TagChip(
                      label: tag,
                      selected: selectedTag == tag,
                      onTap: () =>
                          ref.read(radioTagProvider.notifier).state = tag,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: stationsAsync.when(
                loading: () => const Center(child: AppLoadingIndicator()),
                error: (error, _) => _RadioError(
                  message: s.radioFailed,
                  retryLabel: s.retry,
                  onRetry: () => ref.invalidate(radioStationsProvider),
                ),
                data: (stations) {
                  if (stations.isEmpty) {
                    return Center(
                      child: Text(
                        s.radioEmpty,
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 13,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      return _StationTile(
                        station: station,
                        onTap: () => _play(stations, index),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _play(List<RadioStation> stations, int index) {
    final items = [for (final station in stations) station.toMusicItem()];
    ref
        .read(playerServiceProvider)
        .setQueue(items, startIndex: index, manualPlayName: items[index].name);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: 14, color: AppColors.onScaffold(context)),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 14, color: AppColors.mutedText(context)),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppColors.mutedText(context),
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.mutedText(context),
              ),
              onPressed: onClear,
            );
          },
        ),
        filled: true,
        fillColor: AppColors.fill(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          color: selected ? accent : AppColors.onScaffold(context),
        ),
        selectedColor: accent.withValues(alpha: 0.16),
        side: BorderSide(
          color: selected ? accent : AppColors.cardBorder(context),
        ),
        backgroundColor: Colors.transparent,
        showCheckmark: false,
      ),
    );
  }
}

class _StationTile extends StatelessWidget {
  const _StationTile({required this.station, required this.onTap});

  final RadioStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: _StationArtwork(station: station),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      station.subtitleParts,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_circle_fill_rounded, color: accent, size: 28),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// 封面：很多电台的 favicon 是 404 或 HTML，`errorBuilder` 兜住即可，
/// 不必为它引入图片缓存组件——列表页滚动时 Flutter 自带的图片缓存够用。
class _StationArtwork extends StatelessWidget {
  const _StationArtwork({required this.station});

  final RadioStation station;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.fill(context),
      child: Icon(
        Icons.radio_rounded,
        size: 22,
        color: AppColors.mutedText(context),
      ),
    );
    final url = station.favicon;
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

class _RadioError extends StatelessWidget {
  const _RadioError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 32,
            color: AppColors.mutedText(context),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: AppColors.mutedText(context)),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(retryLabel)),
        ],
      ),
    );
  }
}
