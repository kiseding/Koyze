import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/music_item.dart';
import 'player_provider.dart';

/// 打开「编辑播放队列」面板。
///
/// 队列面板本身是分页的（大歌单只加载一页），跨页拖动没有意义，所以
/// 排序单独做成一张面板：它只对当前已载入的队列生效，拖完立即写回
/// 播放器，正在播放的那首不会被打断。
void showQueueEditSheet(BuildContext context) {
  showKoyzeSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _QueueEditSheet(),
  );
}

class _QueueEditSheet extends ConsumerStatefulWidget {
  const _QueueEditSheet();

  @override
  ConsumerState<_QueueEditSheet> createState() => _QueueEditSheetState();
}

class _QueueEditSheetState extends ConsumerState<_QueueEditSheet> {
  late List<MediaItem> _items;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    final service = ref.read(playerServiceProvider);
    _items = List<MediaItem>.of(service.queue);
    _currentIndex = service.currentIndex;
  }

  Future<void> _move(int oldIndex, int newIndex) async {
    // 这里用的是 `onReorderItem`：它已经替我们扣掉了「先摘出再插入」造成的
    // 下标偏移，不需要再判 `newIndex > oldIndex`。
    final target = newIndex;
    if (target == oldIndex) return;
    final service = ref.read(playerServiceProvider);
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(target, item);
      if (_currentIndex == oldIndex) {
        _currentIndex = target;
      } else if (oldIndex < _currentIndex && target >= _currentIndex) {
        _currentIndex -= 1;
      } else if (oldIndex > _currentIndex && target <= _currentIndex) {
        _currentIndex += 1;
      }
    });
    await service.moveInQueue(oldIndex, target);
  }

  Future<void> _remove(int index) async {
    final service = ref.read(playerServiceProvider);
    setState(() {
      _items.removeAt(index);
      if (index < _currentIndex) _currentIndex -= 1;
    });
    await service.removeFromQueue(index);
  }

  Future<void> _playNext(int index) async {
    final item = _items[index];
    Navigator.pop(context);
    final song = MusicItem.fromJson(item.extras ?? const {});
    await ref.read(playerServiceProvider).playNext(song);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KoyzeSheetGrabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.drag_indicator_rounded,
                  color: AppColors.accentOf(context),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.queueEditTitle,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(s.done),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.cardBorder(context), height: 1),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.62,
              ),
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: _items.length,
                onReorderItem: _move,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final isPlaying = index == _currentIndex;
                  return ListTile(
                    key: ValueKey('${item.id}-$index'),
                    dense: true,
                    minTileHeight: 56,
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: AppColors.mutedText(context),
                        size: 20,
                      ),
                    ),
                    title: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isPlaying
                            ? AppColors.accentOf(context)
                            : AppColors.onScaffold(context),
                        fontWeight: isPlaying
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      item.artist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.mutedText(context),
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: AppColors.mutedText(context),
                        size: 20,
                      ),
                      onSelected: (value) {
                        if (value == 'next') _playNext(index);
                        if (value == 'remove') _remove(index);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'next', child: Text(s.playNext)),
                        if (!isPlaying)
                          PopupMenuItem(
                            value: 'remove',
                            child: Text(s.removeFromQueue),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
