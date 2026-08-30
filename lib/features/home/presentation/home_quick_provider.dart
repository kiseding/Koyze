import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/storage_service.dart';

enum HomeQuickAction { sleepTimer, themeToggle }

class HomeQuickFeature {
  const HomeQuickFeature({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.route = '',
    this.action,
    this.enabledByDefault = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  final HomeQuickAction? action;
  final bool enabledByDefault;
}

const homeQuickFeatures = <HomeQuickFeature>[
  HomeQuickFeature(
    id: 'recommend',
    title: '猜你喜欢',
    subtitle: '根据历史推荐',
    icon: Icons.auto_awesome,
    route: '/recommend',
    color: Color(0xFFFF8F1F),
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'local',
    title: '本地音乐',
    subtitle: '设备上的歌曲',
    icon: Icons.library_music,
    route: 'localPlaylist',
    color: Colors.purple,
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'downloads',
    title: '下载管理',
    subtitle: '任务与进度',
    icon: Icons.download_rounded,
    route: '/download',
    color: Color(0xFF0A84FF),
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'stats',
    title: '听歌统计',
    subtitle: '周月年排行',
    icon: Icons.bar_chart_rounded,
    route: '/stats',
    color: Color(0xFF28A745),
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'sleep_timer',
    title: '睡眠定时',
    subtitle: '定时停止播放',
    icon: Icons.bedtime_outlined,
    action: HomeQuickAction.sleepTimer,
    color: Color(0xFF5B7DB1),
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'theme',
    title: '切换主题',
    subtitle: '深色 / 浅色',
    icon: Icons.palette_outlined,
    action: HomeQuickAction.themeToggle,
    color: Color(0xFF9E9E9E),
    enabledByDefault: true,
  ),
  HomeQuickFeature(
    id: 'favorites',
    title: '收藏列表',
    subtitle: '查看收藏歌曲',
    icon: Icons.favorite_rounded,
    route: 'favoritesPlaylist',
    color: Color(0xFFE53935),
  ),
  HomeQuickFeature(
    id: 'recent',
    title: '最近播放',
    subtitle: '继续最近听过的歌',
    icon: Icons.history_rounded,
    route: 'recentPlaylist',
    color: Color(0xFF2196F3),
  ),
  HomeQuickFeature(
    id: 'leaderboard',
    title: '榜单',
    subtitle: '热门歌曲排行',
    icon: Icons.leaderboard_rounded,
    route: '/leaderboard',
    color: Color(0xFF8E44AD),
  ),
  HomeQuickFeature(
    id: 'search',
    title: '搜索歌曲',
    subtitle: '快速查找音乐',
    icon: Icons.search_rounded,
    route: '/search',
    color: Color(0xFF546E7A),
  ),
  HomeQuickFeature(
    id: 'playlists',
    title: '歌单管理',
    subtitle: '整理自定义歌单',
    icon: Icons.library_music_rounded,
    route: '/playlist',
    color: Color(0xFF7E57C2),
  ),
  HomeQuickFeature(
    id: 'settings',
    title: '应用设置',
    subtitle: '音质、下载与外观',
    icon: Icons.settings_rounded,
    route: '/settings',
    color: Color(0xFF607D8B),
  ),
  HomeQuickFeature(
    id: 'custom_source',
    title: '自定义源',
    subtitle: '管理音乐数据源',
    icon: Icons.extension_rounded,
    route: '/custom-source',
    color: Color(0xFFEF6C00),
  ),
  HomeQuickFeature(
    id: 'sync',
    title: '云同步',
    subtitle: '同步收藏和歌单',
    icon: Icons.cloud_sync_rounded,
    route: '/sync',
    color: Color(0xFF039BE5),
  ),
  HomeQuickFeature(
    id: 'local_scan',
    title: '本地扫描',
    subtitle: '扫描设备音乐',
    icon: Icons.folder_open_rounded,
    route: '/local-music',
    color: Color(0xFF8E24AA),
  ),
  HomeQuickFeature(
    id: 'duplicates',
    title: '重复歌曲',
    subtitle: '查找歌单重复项',
    icon: Icons.content_copy_rounded,
    route: '/duplicates',
    color: Color(0xFF43A047),
  ),
  HomeQuickFeature(
    id: 'leaderboard_settings',
    title: '榜单设置',
    subtitle: '调整榜单显示内容',
    icon: Icons.tune_rounded,
    route: '/leaderboard-settings',
    color: Color(0xFF6A1B9A),
  ),
  HomeQuickFeature(
    id: 'audio_quality',
    title: '播放音质',
    subtitle: '选择默认播放音质',
    icon: Icons.high_quality_rounded,
    route: '/settings?action=audio-quality',
    color: Color(0xFF00897B),
  ),
  HomeQuickFeature(
    id: 'download_quality',
    title: '下载音质',
    subtitle: '选择默认下载音质',
    icon: Icons.download_for_offline_rounded,
    route: '/settings?action=download-quality',
    color: Color(0xFF1E88E5),
  ),
  HomeQuickFeature(
    id: 'default_search',
    title: '默认搜索平台',
    subtitle: '调整搜索默认来源',
    icon: Icons.travel_explore_rounded,
    route: '/settings?action=default-search',
    color: Color(0xFF5E35B1),
  ),
  HomeQuickFeature(
    id: 'backup',
    title: '备份数据',
    subtitle: '导出歌单和设置',
    icon: Icons.save_alt_rounded,
    route: '/settings?action=backup',
    color: Color(0xFF43A047),
  ),
  HomeQuickFeature(
    id: 'restore',
    title: '恢复数据',
    subtitle: '从备份文件恢复',
    icon: Icons.restore_page_rounded,
    route: '/settings?action=restore',
    color: Color(0xFFF4511E),
  ),
  HomeQuickFeature(
    id: 'clear_cache',
    title: '清除缓存',
    subtitle: '释放播放与封面缓存',
    icon: Icons.cleaning_services_rounded,
    route: '/settings?action=clear-cache',
    color: Color(0xFF6D4C41),
  ),
  HomeQuickFeature(
    id: 'diagnostic_log',
    title: '诊断日志',
    subtitle: '查看实时运行日志',
    icon: Icons.monitor_heart_rounded,
    route: '/settings?action=diagnostic-log',
    color: Color(0xFF546E7A),
  ),
];

class HomeQuickSettings {
  const HomeQuickSettings({required this.order, required this.enabled});

  final List<String> order;
  final Set<String> enabled;
}

final homeQuickSettingsProvider =
    StateNotifierProvider<HomeQuickSettingsNotifier, HomeQuickSettings>(
      (ref) => HomeQuickSettingsNotifier(),
    );

class HomeQuickSettingsNotifier extends StateNotifier<HomeQuickSettings> {
  HomeQuickSettingsNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(
        HomeQuickSettings(
          order: _defaultOrder,
          enabled: {
            for (final feature in homeQuickFeatures)
              if (feature.enabledByDefault) feature.id,
          },
        ),
      ) {
    _load();
  }

  static const _key = 'home_quick_features_v1';
  static final _defaultOrder = [
    for (final feature in homeQuickFeatures) feature.id,
  ];
  final StorageLoader _storage;
  int _generation = 0;

  Future<void> _load() async {
    try {
      final raw = (await _storage()).getJson(_key);
      final order = raw?['order'];
      if (order is! List) return;
      final known = _defaultOrder.toSet();
      final loaded = <String>[
        for (final value in order)
          if (known.contains(value.toString())) value.toString(),
        for (final id in _defaultOrder)
          if (!order.map((value) => value.toString()).contains(id)) id,
      ];
      final enabled = raw?['enabled'];
      final enabledIds = enabled is List
          ? enabled.map((value) => value.toString()).toSet()
          : {
              for (final feature in homeQuickFeatures)
                if (feature.enabledByDefault) feature.id,
            };
      state = HomeQuickSettings(order: loaded, enabled: enabledIds);
    } catch (_) {}
  }

  void setEnabled(String id, bool enabled) {
    final next = {...state.enabled};
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    // 开关只改变显隐，不改变完整顺序；重新启用时回到用户之前排好的位置。
    state = HomeQuickSettings(order: state.order, enabled: next);
    _persist();
  }

  /// [ReorderableListView.onReorderItem]：newIndex 已按"移除旧项后"
  /// 修正，直接使用（旧 onReorder 需手动 -1，双重修正会插错位置）。
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final next = [...state.order];
    if (newIndex < 0 || newIndex > next.length) return;
    if (oldIndex < 0 || oldIndex >= next.length) return;
    next.insert(newIndex, next.removeAt(oldIndex));
    state = HomeQuickSettings(order: next, enabled: state.enabled);
    _persist();
  }

  List<String> get _completeOrder => [
    ...state.order,
    for (final feature in homeQuickFeatures)
      if (!state.order.contains(feature.id)) feature.id,
  ];

  Future<void> _persist() async {
    final generation = ++_generation;
    try {
      final storage = await _storage();
      if (generation != _generation) return;
      await storage.setJson(_key, {
        'order': _completeOrder,
        'enabled': state.enabled.toList(growable: false),
      });
    } catch (_) {}
  }
}
