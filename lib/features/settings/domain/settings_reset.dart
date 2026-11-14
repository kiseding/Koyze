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
  'accent_follows_cover',
  'glass_surface_opacity',
  'player_backdrop_blur',
  'player_backdrop_scrim',
  'player_flowing_backdrop',
  // 通用
  'force_landscape',
  'simplify_effects',
  'car_mode_preference',
  // 播放
  'audio_quality',
  'playback_volume',
  'playback_speed',
  'pitch_semitones',
  'skip_silence_enabled',
  'playback_fade_enabled',
  'replay_gain_enabled',
  'lock_screen_lyric_enabled',
  'desktop_lyric_enabled',
  'desktop_lyric_locked',
  'desktop_lyric_font_size',
  'precache_recent_enabled',
  'precache_recent_count',
  'auto_resume_playback',
  'android_floating_player',
  'default_search_platform',
  'equalizer_settings_v1',
  // 下载
  'download_quality',
  'wifi_only_download',
  // 歌词
  'lyric_offset_ms',
  'lyric_scale',
  'lyric_align',
  'lyric_show_translation',
  'lyric_blur',
  'lyric_single_line_animation',
  'lyric_font_family',
  'lyric_font_name',
  'lyric_font_path',
  'desktop_lyric_x',
  'desktop_lyric_y',
  // 内容与布局
  'local_scan_rules_v1',
  'leaderboard_layout_v1',
  'leaderboard_layout_order_version',
];

/// 保留的键（仅用于注释与测试断言，不会被删除）。
///
/// 语言也在保留之列：把界面切回默认语言会让看不懂中文的用户彻底迷路，
/// 而它并不属于「听歌偏好」。
///
/// 账号与内容数据同样保留：AI 的接口地址/密钥、定时任务、听歌历史、可播
/// 索引、推荐权重、源体检报告都是用户攒下来的东西，「恢复默认设置」不该
/// 顺手把它们抹掉。
const List<String> kPreservedPreferenceKeys = <String>[
  'app_language',
  'custom_sources',
  'custom_sources_quarantine',
  'local_music_dirs_v1',
  'local_music_download_dir_v1',
  'local_music_index_v1',
  'search_history',
  'ai_config',
  'ai_schedules_v1',
  'play_history_v1',
  'playable_songs_v1',
  'recommendation_tuning_v1',
  'source_check_report',
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
