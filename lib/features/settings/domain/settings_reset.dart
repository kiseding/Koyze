import '../../../core/storage/storage_service.dart';

/// 「恢复默认设置」要清掉的键。
///
/// 用白名单而不是「清空全部再恢复」：存储里还放着登录凭据、NAS 配置、
/// 本地库索引、歌单与播放历史，那些是用户的数据，不是设置。清空式重置
/// 会把它们一起抹掉，而用户点的是「把设置调回默认」。
const List<String> kResettablePreferenceKeys = <String>[
  // 外观
  'theme_mode',
  'app_accent_color',
  'player_backdrop_blur',
  'player_backdrop_scrim',
  // 通用
  'force_landscape',
  'simplify_effects',
  // 播放
  'audio_quality',
  'playback_volume',
  'playback_speed',
  'replay_gain_enabled',
  'lock_screen_lyric_enabled',
  'precache_recent_enabled',
  'precache_recent_count',
  'auto_resume_playback',
  'android_floating_player',
  'default_search_platform',
  'equalizer_settings_v1',
  // 下载
  'download_quality',
  'wifi_only_download',
  // 内容与布局
  'local_scan_rules_v1',
  'leaderboard_layout_v1',
  'leaderboard_layout_order_version',
];

/// 保留的键（仅用于注释与测试断言，不会被删除）。
///
/// 语言也在保留之列：把界面切回默认语言会让看不懂中文的用户彻底迷路，
/// 而它并不属于「听歌偏好」。
const List<String> kPreservedPreferenceKeys = <String>[
  'app_language',
  'custom_sources',
  'local_music_dirs_v1',
  'local_music_download_dir_v1',
  'local_music_index_v1',
  'search_history',
];

/// 清除所有可重置的偏好项。返回实际删除的键数量。
///
/// `SharedPreferences.remove` 在多数平台上无论键是否存在都返回 true，
/// 所以先取一次快照，只把「原本存在」的键计入返回值，否则提示里的
/// 「已恢复 N 项」会永远是白名单长度。
Future<int> resetPreferences(StorageService storage) async {
  final before = storage.snapshot(kResettablePreferenceKeys.toSet()).values;
  var removed = 0;
  for (final key in kResettablePreferenceKeys) {
    try {
      await storage.remove(key);
      if (before[key] != null) removed++;
    } catch (_) {
      // 单个键删除失败不影响其它键；最终以 UI 状态为准。
    }
  }
  return removed;
}
