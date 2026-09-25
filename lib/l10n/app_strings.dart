import 'package:flutter/widgets.dart';

import '../features/settings/presentation/settings_provider.dart';

/// User-facing copy for the shell and settings.
///
/// Screens that have not been migrated yet stay in Chinese.
class S {
  const S(this.locale);

  final Locale locale;

  bool get en => locale.languageCode == 'en';

  static S of(BuildContext context) => S(Localizations.localeOf(context));

  String get home => en ? 'Home' : '首页';
  String get charts => en ? 'Charts' : '榜单';
  String get playlists => en ? 'Playlists' : '歌单';
  String get settings => en ? 'Settings' : '设置';

  String get sync => en ? 'Sync' : '同步';
  String get cloudAccount => en ? 'Cloud account' : '云端账号 / 歌单';
  String get cloudAccountSubtitle => en
      ? 'Sync favorites, playlists, settings, and custom sources'
      : '同步收藏、歌单、设置与自定义音源';

  String get advanced => en ? 'Advanced' : '高级功能';
  String get localLibrary => en ? 'Local music folders' : '本地音乐目录';
  String get localLibrarySubtitle => en
      ? 'Choose folders, rescan, and match songs online'
      : '设置扫描目录、刷新本地歌曲与在线刮削';
  String get customSources => en ? 'Custom sources' : '自定义源';
  String get customSourcesSubtitle =>
      en ? 'Manage custom music sources' : '管理自定义音乐源';
  String get nasServer => en ? 'NAS music server' : 'NAS 音乐服务器';

  String get playback => en ? 'Playback' : '播放';
  String get audioQuality => en ? 'Audio quality' : '音质选择';
  String get chooseQuality => en ? 'Choose quality' : '选择音质';
  String get equalizer => en ? 'Equalizer' : '均衡器';
  String get sleepTimer => en ? 'Sleep timer' : '睡眠定时';
  String get cancel => en ? 'Cancel' : '取消';
  String get sleepTimerCancelled => en ? 'Sleep timer cancelled' : '已取消睡眠定时';
  String get autoResume => en ? 'Resume on launch' : '自动恢复播放';
  String get autoResumeSubtitle =>
      en ? 'Continue the last song when the app opens' : '打开 App 时自动继续播放上次的歌曲';
  String get defaultSearchPlatform => en ? 'Default search source' : '默认搜索平台';
  String get listeningStats => en ? 'Listening stats' : '听歌统计';
  String get listeningStatsSubtitle =>
      en ? 'History, rankings, and activity' : '播放历史 · Top 排行 · 热力图';

  String get appearance => en ? 'Appearance' : '外观';
  String get language => en ? 'Language' : '语言';
  String get darkMode => en ? 'Dark mode' : '深色模式';
  String get darkModeSubtitle => en ? 'Use the dark theme' : '使用深色主题';
  String get followSystem => en ? 'Follow system' : '跟随系统';
  String get followSystemThemeSubtitle =>
      en ? 'Match the system light or dark theme' : '自动切换亮色/深色主题';
  String get followSystemLanguageSubtitle => en
      ? 'Use the device language when it is Chinese or English'
      : '设备为中文或英文时自动跟随';

  String get downloads => en ? 'Downloads' : '下载';
  String get downloadManager => en ? 'Download manager' : '下载管理';
  String get downloadManagerSubtitle =>
      en ? 'View and manage download tasks' : '查看和管理下载任务';
  String get wifiOnly => en ? 'Wi-Fi only' : '仅 WiFi 下载';
  String get wifiOnlySubtitle =>
      en ? 'Download songs only on Wi-Fi' : '仅在 WiFi 环境下下载歌曲';
  String get downloadQuality => en ? 'Download quality' : '下载音质';
  String get chooseDownloadQuality => en ? 'Choose download quality' : '选择下载音质';

  String get data => en ? 'Data' : '数据';
  String get backup => en ? 'Back up' : '备份数据';
  String get backupSubtitle =>
      en ? 'Export playlists and settings to a file' : '导出歌单、设置等数据到文件';
  String get restore => en ? 'Restore' : '恢复数据';
  String get restoreSubtitle => en ? 'Restore from a backup file' : '从备份文件恢复数据';
  String get clearCache => en ? 'Clear cache' : '清除缓存';
  String get clearCacheSubtitle => en
      ? 'Clear playback cache, artwork, and temporary files'
      : '清除歌曲播放缓存、封面缓存和临时文件';

  String get about => en ? 'About' : '关于';
  String get version => en ? 'Version' : '版本';
  String get deviceUuid => en ? 'Device UUID' : '设备 UUID';
  String get loading => en ? 'Loading…' : '读取中…';
  String get deviceUuidCopied => en ? 'Device UUID copied' : '完整设备 UUID 已复制';
  String get diagnostics => en ? 'Live diagnostics' : '实时诊断日志';
  String get diagnosticsSubtitle => en
      ? 'Start recording when opened. Keeps recording while minimized.'
      : '点开开始记录，最小化后继续记录（不保存）';

  String get volume => en ? 'Volume' : '音量';
  String get mute => en ? 'Mute' : '静音';
  String get unmute => en ? 'Unmute' : '取消静音';
  String get download => en ? 'Download' : '下载';
  String get addedToDownloads =>
      en ? 'Added to the download queue' : '已添加到下载队列';
  String get downloadFailed => en ? 'Could not add download' : '添加下载失败';

  String get exportBackupTitle => en ? 'Export Koyze backup' : '导出 Koyze 备份';
  String backupExported(String path) =>
      en ? 'Backup saved to $path' : '备份已导出到 $path';
  String backupFailed(Object error) =>
      en ? 'Backup failed: $error' : '备份失败: $error';
  String get restoreSucceeded => en ? 'Restore complete' : '数据恢复成功';
  String restoreFailed(Object error) =>
      en ? 'Restore failed: $error' : '恢复失败: $error';

  String get chooseCache => en ? 'Choose what to clear' : '选择要清除的内容';
  String get selectAll => en ? 'Select all' : '全选';
  String get playbackCache => en ? 'Playback cache' : '歌曲播放缓存';
  String get playbackCacheSubtitle => en
      ? 'Cached songs. Manual downloads are not included.'
      : '自动缓存的歌曲文件，不包含手动下载的歌曲';
  String get artworkCache => en ? 'Artwork cache' : '封面缓存';
  String get artworkCacheSubtitle =>
      en ? 'Album art stored on disk and in memory' : '专辑封面的磁盘和内存缓存';
  String get tempFiles => en ? 'Temporary files' : '临时文件';
  String get tempFilesSubtitle =>
      en ? 'Intermediate files in the system temp folder' : '系统临时目录中的中间文件';
  String get cacheKeepNote => en
      ? 'Manual downloads stay. A song that is playing keeps its cache.'
      : '手动下载的歌曲不会被删除；正在播放的歌曲缓存会安全保留。';
  String get clear => en ? 'Clear' : '清除';
  String get cacheCleared => en ? 'Selected cache cleared' : '所选缓存已清除';
  String cacheClearedRetained(int count) => en
      ? 'Cache cleared. $count songs still in use were kept.'
      : '缓存已清除，$count 个正在使用的歌曲缓存已安全保留';
  String clearFailed(Object error) =>
      en ? 'Could not clear cache: $error' : '清除失败: $error';

  String minutes(int count) => en ? '$count min' : '$count 分钟';
  String stopsInMinutes(int count) =>
      en ? 'Playback stops in $count min' : '$count 分钟后停止播放';
  String get cancelSleepTimer => en ? 'Cancel sleep timer' : '取消睡眠定时';

  String languageName(AppLanguage language) => switch (language) {
    AppLanguage.system => followSystem,
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };

  String get chineseInterface => en ? 'Chinese interface' : '中文界面';
  String get englishInterface => en ? 'English interface' : '英文界面';
}

bool localeIsEnglish(Locale? locale) => locale?.languageCode == 'en';
