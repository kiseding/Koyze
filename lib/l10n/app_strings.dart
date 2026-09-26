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
  String get floatingPlayer => en ? 'Floating player' : '悬浮窗';
  String get floatingPlayerSubtitle => en
      ? 'Show cover, lyrics, progress, and playback controls over other apps'
      : '离开应用后显示封面、歌词、进度和播放控制';
  String get floatingPlayerPermission => en
      ? 'Allow display over other apps, then return to Koyze'
      : '请允许显示在其他应用上层，然后返回 Koyze';
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

  String get shortcuts => en ? 'Shortcuts' : '快捷功能';
  String get shortcutSettings => en ? 'Shortcut settings' : '快捷功能设置';
  String get closeShortcutSettings =>
      en ? 'Close shortcut settings' : '关闭快捷功能设置';
  String get searchSongsHint =>
      en ? 'Songs, artists, playlists...' : '搜索歌曲、歌手、歌单...';
  String get heroCardSettings => en ? 'Home card' : '首页大卡片设置';
  String get heroCardSettingsAction => en ? 'Home card settings' : '设置首页大卡片';
  String get closeHeroCardSettings =>
      en ? 'Close home card settings' : '关闭首页大卡片设置';
  String get heroCardHint => en
      ? 'Same five cards as Playlists. Only one can be on.'
      : '对应歌单页顶部五张卡片，只能启用其中一张';
  String get heroPlayMode => en ? 'Play button mode' : '右侧按钮播放模式';
  String get heroPlayModeHint => en
      ? 'Only this card\'s button. The player mode stays separate.'
      : '只影响首页大卡片右侧按钮，和播放页模式互不影响';
  String get favorites => en ? 'Favorites' : '收藏列表';
  String get forYou => en ? 'For You' : '猜你喜欢';
  String get localMusic => en ? 'Local music' : '本地音乐';
  String get nasLibrary => en ? 'NAS library' : 'NAS 乐库';
  String get recentPlays => en ? 'Recently played' : '最近播放';
  String get playInOrder => en ? 'In order' : '顺序播放';
  String get shufflePlay => en ? 'Shuffle' : '随机播放';
  String get repeatOne => en ? 'Repeat one' : '单曲循环';
  String get playInOrderHint =>
      en ? 'Play the list in order, then start over' : '按列表顺序播放，播完回到第一首';
  String get shufflePlayHint =>
      en ? 'Shuffle, then keep picking at random' : '打乱顺序，播完继续随机下一首';
  String get repeatOneHint => en ? 'Repeat the current song' : '只循环当前第一首';
  String get noFavoritesYet => en ? 'No favorites yet' : '还没有收藏歌曲';
  String heroFavoritesHint(String mode) =>
      en ? 'Open the list. Button: $mode' : '点击查看，右侧$mode';
  String playAction(String mode, String target) =>
      en ? '$mode $target' : '$mode$target';
  String get recommendAfterFavorites =>
      en ? 'Favorite songs to get recommendations' : '收藏歌曲后为你推荐';
  String recommendedSongs(int count) =>
      en ? '$count songs for you' : '为你推荐 $count 首歌曲';
  String songCount(int count) => en ? '$count songs' : '$count 首歌曲';
  String get chooseFolderToScan =>
      en ? 'Choose a folder to scan this device' : '选择文件夹扫描设备歌曲';
  String get nasHosts => en
      ? 'Navidrome / Emby / Plex / Synology'
      : 'Navidrome / Emby / Plex / 群晖';
  String loadingHost(String host) => en ? 'Loading $host' : '正在加载 $host';
  String actionFailed(String action, Object error) =>
      en ? '$action failed: $error' : '$action失败: $error';
  String get loadSongsFailed => en ? 'Could not load songs' : '加载歌曲失败';
  String get playFailed => en ? 'Playback failed' : '播放失败';
  String get noSongsOnServer => en ? 'No songs on the server yet' : '服务器上还没有歌曲';
  String failedWith(String label, Object error) =>
      en ? '$label: $error' : '$label: $error';

  String quickTitle(String id) => switch (id) {
    'recommend' => forYou,
    'local' => localMusic,
    'subsonic' => nasLibrary,
    'downloads' => downloadManager,
    'stats' => listeningStats,
    'sleep_timer' => sleepTimer,
    'theme' => en ? 'Theme' : '切换主题',
    'favorites' => favorites,
    'recent' => recentPlays,
    'leaderboard' => charts,
    'search' => en ? 'Search' : '搜索歌曲',
    'playlists' => en ? 'Manage playlists' : '歌单管理',
    'settings' => en ? 'App settings' : '应用设置',
    'custom_source' => customSources,
    'sync' => en ? 'Cloud sync' : '云同步',
    'local_scan' => en ? 'Scan device' : '本地扫描',
    'leaderboard_settings' => en ? 'Chart settings' : '榜单设置',
    'audio_quality' => audioQuality,
    'download_quality' => downloadQuality,
    'default_search' => defaultSearchPlatform,
    'backup' => backup,
    'restore' => restore,
    'clear_cache' => clearCache,
    'diagnostic_log' => diagnostics,
    _ => id,
  };

  String quickSubtitle(String id) => switch (id) {
    'recommend' => en ? 'Based on what you play' : '根据历史推荐',
    'local' => en ? 'Songs on this device' : '设备上的歌曲',
    'subsonic' => nasHosts,
    'downloads' => en ? 'Tasks and progress' : '任务与进度',
    'stats' => en ? 'Week, month, and year' : '周月年排行',
    'sleep_timer' => en ? 'Stop playback on a timer' : '定时停止播放',
    'theme' => en ? 'Dark or light' : '深色 / 浅色',
    'favorites' => en ? 'Songs you saved' : '查看收藏歌曲',
    'recent' => en ? 'Pick up where you left off' : '继续最近听过的歌',
    'leaderboard' => en ? 'Popular songs' : '热门歌曲排行',
    'search' => en ? 'Find music quickly' : '快速查找音乐',
    'playlists' => en ? 'Organize your playlists' : '整理自定义歌单',
    'settings' => en ? 'Quality, downloads, appearance' : '音质、下载与外观',
    'custom_source' => en ? 'Manage music sources' : '管理音乐数据源',
    'sync' => en ? 'Sync favorites and playlists' : '同步收藏和歌单',
    'local_scan' => en ? 'Scan music on this device' : '扫描设备音乐',
    'leaderboard_settings' => en ? 'Choose which charts show' : '调整榜单显示内容',
    'audio_quality' => en ? 'Default playback quality' : '选择默认播放音质',
    'download_quality' => en ? 'Default download quality' : '选择默认下载音质',
    'default_search' => en ? 'Where search starts' : '调整搜索默认来源',
    'backup' => en ? 'Export playlists and settings' : '导出歌单和设置',
    'restore' => en ? 'Restore from a backup file' : '从备份文件恢复',
    'clear_cache' => en ? 'Free playback and artwork cache' : '释放播放与封面缓存',
    'diagnostic_log' => en ? 'Live runtime log' : '查看实时运行日志',
    _ => id,
  };

  String get retry => en ? 'Retry' : '重试';
  String get otherPlatform => en ? 'Other' : '其他';
  String get featured => en ? 'Picks' : '精选';
  String get noChartData => en ? 'No chart data' : '暂无排行榜数据';
  String get chartsHidden => en
      ? 'Every chart is hidden\nTurn them back on from the top right'
      : '已隐藏全部榜单\n点击右上角设置恢复';
  String get chartSettings => en ? 'Chart settings' : '榜单设置';
  String get refreshCharts => en ? 'Refresh charts' : '刷新榜单';
  String get noSongData => en ? 'No songs' : '暂无歌曲数据';
  String nowPlayingNamed(String name) => en ? 'Playing $name' : '正在播放 $name';
  String playNamed(String name) => en ? 'Play $name' : '播放 $name';
  String platformName(String id) => switch (id) {
    'qq' => en ? 'QQ Music' : 'QQ音乐',
    'tx' => en ? 'QQ Music' : 'QQ音乐',
    'kw' => en ? 'Kuwo' : '酷我音乐',
    'wy' => en ? 'NetEase' : '网易云',
    _ => otherPlatform,
  };

  String get showAll => en ? 'Show all' : '全部显示';
  String get back => en ? 'Back' : '返回';
  String chartCount(int count) => en ? '$count charts' : '$count 个榜单';
  String get defaultFirst => en ? 'Shown first' : '默认优先';
  String hiddenUntil(String name) =>
      en ? 'Hidden until you turn on “$name”' : '已隐藏，勾选「$name」后显示';

  String get importPlaylist => en ? 'Import playlist' : '导入歌单';
  String get newPlaylist => en ? 'New playlist' : '新建歌单';
  String get searchLibraryHint =>
      en ? 'Search songs or playlists' : '在库中搜索歌曲/歌单';
  String get clearSearch => en ? 'Clear search' : '清除搜索内容';
  String get customPlaylists => en ? 'Custom playlists' : '自定义歌单';
  String songsHeader(int count) => en ? 'Songs ($count)' : '歌曲 ($count)';
  String playlistsHeader(int count) =>
      en ? 'Playlists ($count)' : '歌单 ($count)';
  String get sortPlaylists => en ? 'Sort playlists' : '排序歌单';
  String get nothingMatched =>
      en ? 'No matching songs or playlists' : '未找到匹配的歌曲或歌单';
  String playlistMeta(int count, String? description) => en
      ? '$count songs · ${description ?? 'Private'}'
      : '$count 首歌曲 · ${description ?? '私人'}';
  String get createPlaylist => en ? 'Create playlist' : '创建歌单';
  String get playlistName => en ? 'Playlist name' : '歌单名称';
  String get descriptionOptional => en ? 'Description (optional)' : '描述（可选）';
  String get create => en ? 'Create' : '创建';
  String get editPlaylist => en ? 'Edit playlist' : '编辑歌单';
  String get save => en ? 'Save' : '保存';
  String get sortBy => en ? 'Sort by' : '排序方式';
  String get recentlyAdded => en ? 'Recently added' : '最近添加';
  String get sortByName => en ? 'Name' : '名称排序';
  String get sortByCount => en ? 'Song count' : '歌曲数量';
  String get pastePlaylistLink =>
      en ? 'Paste a share link or playlist ID' : '粘贴分享链接或输入歌单 ID';
  String get closeImport => en ? 'Close import' : '关闭导入歌单';
  String get sourcePlatform => en ? 'Source' : '来源平台';
  String get kuwoShort => en ? 'Kuwo' : '酷我';
  String get neteaseShort => en ? 'NetEase' : '网易';
  String get playlistLinkOrId => en ? 'Link or ID' : '歌单链接或 ID';
  String get playlistLinkExample => en
      ? 'Example: https://y.qq.com/n/ryqq/playlist/123\nor a numeric ID'
      : '例如：https://y.qq.com/n/ryqq/playlist/123\n或直接输入数字 ID';
  String get enterLinkOrId => en ? 'Enter a link or ID' : '请输入链接或 ID';
  String importProgress(int loaded, int total) =>
      en ? '$loaded/$total' : '$loaded/$total 首';
  String confirmImport(int count) => en
      ? 'Import all $count songs into a local playlist?'
      : '共 $count 首，确认导入到本地歌单？';
  String get importAction => en ? 'Import' : '导入';
  String importedFrom(String source) =>
      en ? 'Imported from $source' : '导入自$source';
  String importedResult(String name, int count) =>
      en ? 'Imported “$name”, $count songs' : '已导入「$name」$count 首';
  String get parsingPlaylist => en ? 'Reading playlist…' : '正在解析歌单…';
  String parsingProgress(String progress) =>
      en ? 'Reading $progress' : '正在解析 $progress';
  String get parsePlaylist => en ? 'Read playlist' : '解析歌单';
  String get addAllToFavorites => en ? 'Add all to Favorites' : '全部添加到收藏列表';
  String get addFailed => en ? 'Could not add' : '添加失败';
  String get alreadyInFavorites =>
      en ? 'Those songs are already in Favorites' : '所有歌曲已在收藏列表中';
  String addedToFavorites(int count) =>
      en ? 'Added $count to Favorites' : '已添加 $count 首到收藏列表';
  String get deletePlaylist => en ? 'Delete playlist' : '删除歌单';
  String get deleteFailed => en ? 'Could not delete' : '删除失败';
  String get createFailed => en ? 'Could not create' : '创建失败';
  String get saveFailed => en ? 'Could not save' : '保存失败';

  String get choosePlatform => en ? 'Choose a source' : '选择平台';
  String get platform => en ? 'Source' : '平台';
  String get searchFieldHint => en ? 'Songs, playlists...' : '搜索歌曲、歌单...';
  String get searchAction => en ? 'Search' : '搜索';
  String searchFailed(Object error) =>
      en ? 'Search failed: $error' : '搜索出错: $error';
  String get noResults => en ? 'No results' : '无结果';
  String get onlineMusic => en ? 'Online' : '网络音乐';
  String localArtist(String singer) => en ? '$singer · Local' : '$singer · 本地';
  String get slideForMore => en ? 'Scroll for more' : '滑动加载更多';
  String get moreActions => en ? 'More' : '更多操作';
  String get searchHistory => en ? 'Recent searches' : '搜索历史';
  String get clearHistory => en ? 'Clear' : '清空';
  String get hotSearch => en ? 'Trending' : '热搜榜';
  String get loadingEllipsis => en ? 'Loading...' : '加载中...';
  String get playNow => en ? 'Play now' : '立即播放';
  String get addToPlaylist => en ? 'Add to playlist' : '添加到歌单';
  String get favorite => en ? 'Favorite' : '收藏';
  String get unfavorite => en ? 'Unfavorite' : '取消收藏';
  String get favoriteFailed => en ? 'Could not favorite' : '收藏失败';

  String get playbackProgress => en ? 'Playback progress' : '播放进度';
  String get nothingPlaying => en ? 'Nothing playing' : '暂无播放内容';
  String get unknownQuality => en ? 'Unknown quality' : '未知音质';
  String get resolvingQuality => en ? 'Resolving…' : '解析中…';
  String get collapsePlayer => en ? 'Close player' : '收起播放器';
  String get backToArtwork => en ? 'Back to artwork' : '返回封面';
  String get nowPlaying => en ? 'Now playing' : '正在播放';
  String get lyrics => en ? 'Lyrics' : '歌词';
  String get more => en ? 'More' : '更多';
  String get openLyrics => en ? 'Open lyrics' : '打开歌词';
  String get playMode => en ? 'Play mode' : '播放模式';
  String get previous => en ? 'Previous' : '上一首';
  String get next => en ? 'Next' : '下一首';
  String get queue => en ? 'Queue' : '播放队列';
  String get dislikeAndSkip => en ? 'Dislike and skip' : '不喜欢并跳过';
  String get dislikedNote => en
      ? 'Marked as disliked. It will be skipped next time.'
      : '已标记不喜欢，后续播放会自动跳过';
  String get dislikeFailed => en ? 'Could not mark dislike' : '标记不喜欢失败';
  String queueTitle(int count) => en ? 'Queue ($count)' : '播放列表 ($count)';
  String get queueLoadFailed =>
      en ? 'Full list failed. Showing the current queue.' : '完整列表加载失败，显示当前队列';
  String get queueEmpty => en ? 'Queue is empty' : '播放列表为空';

  String get playlistMissing => en ? 'Playlist not found' : '歌单不存在';
  String get exitMultiSelect => en ? 'Done' : '退出多选';
  String get cancelEdit => en ? 'Cancel edit' : '取消编辑';
  String get deselectAll => en ? 'Deselect all' : '取消全选';
  String selectedCount(int count) => en ? '$count selected' : '已选 $count 首';
  String playlistTitleCount(String name, int count) =>
      en ? '$name ($count)' : '$name（$count首）';

  /// Built-in playlists keep a Chinese name in storage. Show the localized one.
  String builtinPlaylistName(String id, String storedName) => switch (id) {
    'favorites' => favorites,
    'recent' => recentPlays,
    'local' => localMusic,
    _ => storedName,
  };
  String get downloadSelected => en ? 'Download selected' : '下载已选歌曲';
  String get unfavoriteSelected =>
      en ? 'Remove selected from Favorites' : '取消收藏已选歌曲';
  String get playAll => en ? 'Play all' : '播放全部';
  String favoritedSongs(int count) =>
      en ? 'Added $count songs to Favorites' : '已收藏 $count 首歌曲';
  String get alreadyFavorited => en ? 'Already in Favorites' : '歌曲已在收藏中';
  String get actionFailedShort => en ? 'Action failed' : '操作失败';
  String get favoriteAll => en ? 'Favorite all' : '收藏所有';
  String get editInfo => en ? 'Edit details' : '编辑信息';
  String get manualSort => en ? 'Manual order' : '手动排序';
  String get sortByTitle => en ? 'Sort by title' : '按歌名排序';
  String get sortByArtist => en ? 'Sort by artist' : '按歌手排序';
  String get sortByDuration => en ? 'Sort by duration' : '按时长排序';
  String get duplicateSongs => en ? 'Duplicate songs' : '重复歌曲';
  String get clearFavorites => en ? 'Clear favorites' : '清空收藏';
  String get noSongs => en ? 'No songs' : '暂无歌曲';
  String get locateFailed => en ? 'Could not find the song' : '定位歌曲失败';
  String get play => en ? 'Play' : '播放';
  String get removeFromPlaylist => en ? 'Remove from playlist' : '从歌单移除';
  String get removeFailed => en ? 'Could not remove' : '移除失败';
  String get nothingSelectedToDownload =>
      en ? 'No selected songs to download' : '没有可下载的已选歌曲';
  String queuedDownloads(int count) =>
      en ? 'Added $count songs to downloads' : '已添加 $count 首到下载队列';
  String unfavoritedSongs(int count) =>
      en ? 'Removed $count songs from Favorites' : '已取消收藏 $count 首歌曲';
  String get nothingSelectedToUnfavorite =>
      en ? 'No selected songs to remove from Favorites' : '没有可取消收藏的已选歌曲';
  String get unfavoriteFailed =>
      en ? 'Could not remove from Favorites' : '取消收藏失败';
  String get descriptionLabel => en ? 'Description' : '描述';
  String get clearFavoritesTitle => en ? 'Clear favorites?' : '清空收藏？';
  String clearFavoritesBody(int count) => en
      ? 'Remove $count songs from Favorites. This cannot be undone, and it does not delete the original files or playlist songs.'
      : '将从收藏列表移除 $count 首歌曲，此操作不可撤销，但不会删除本地或歌单中的原歌曲。';
  String get confirmClear => en ? 'Clear' : '确认清空';
  String get favoritesAlreadyEmpty =>
      en ? 'Favorites is already empty' : '收藏列表已为空';
  String deletePlaylistConfirm(String name) =>
      en ? 'Delete “$name”?' : '确定删除「$name」？';
  String get delete => en ? 'Delete' : '删除';

  String get close => en ? 'Close' : '关闭';
  String get add => en ? 'Add' : '添加';
  String get pause => en ? 'Pause' : '暂停';
  String get refresh => en ? 'Refresh' : '刷新';
  String get connect => en ? 'Connect' : '连接';
  String get reset => en ? 'Reset' : '重置';
  String get remove => en ? 'Remove' : '移除';
  String get start => en ? 'Start' : '开始';
  String get log => en ? 'Log' : '日志';
  String get edit => en ? 'Edit' : '编辑';
  String get export => en ? 'Export' : '导出';
  String get customPreset => en ? 'Custom' : '自定义';
  String get presets => en ? 'Presets' : '预设';
  String get pauseAll => en ? 'Pause all' : '暂停全部';
  String get waiting => en ? 'Waiting' : '等待中';
  String get done => en ? 'Done' : '已完成';
  String get all => en ? 'All' : '全部';
  String get username => en ? 'Username' : '用户名';
  String get password => en ? 'Password' : '密码';
  String get login => en ? 'Log in' : '登录';
  String get register => en ? 'Register' : '注册';
  String get pleaseWait => en ? 'Please wait…' : '请稍候…';
  String get notice => en ? 'Notice' : '提示';
  String get success => en ? 'Success' : '成功';
  String get warning => en ? 'Warning' : '警告';
  String get error => en ? 'Error' : '错误';
  String get dismissNotification => en ? 'Dismiss' : '关闭通知';
  String get somethingWentWrong => en ? 'Something went wrong' : '出错了';
  String get notPlaying => en ? 'Not playing' : '未在播放';
  String get noLyrics => en ? 'No lyrics' : '无歌词';
  String get openNowPlaying => en ? 'Open Now Playing' : '打开正在播放';
  String get previousPage => en ? 'Previous page' : '上一页';
  String get nextPage => en ? 'Next page' : '下一页';
  String get choosePage => en ? 'Choose page' : '选择页码';
  String pagePosition(int page, int count) =>
      en ? 'Page $page / $count' : '第 $page / $count 页';
  String get preparingApp => en ? 'Preparing Koyze' : '正在准备 Koyze';
  String get startupFailed => en ? 'Koyze could not start' : '应用初始化失败';
  String get startupLoading =>
      en ? 'Loading your library and player…' : '正在加载本地数据和播放服务…';
  String startupFailedHint(String error) => en
      ? 'Open Koyze again. If this keeps happening, check Diagnostics in Settings.\n$error'
      : '请重新打开应用；如果问题持续，请查看设置中的诊断日志。\n$error';
  String get retryStartup => en ? 'Try again' : '重试启动';
  String get lyricsLoading => en ? 'Loading lyrics' : '正在加载歌词';
  String get fetchingLyrics => en ? 'Fetching lyrics' : '正在获取歌词内容';
  String get lyricsFailed => en ? 'Could not load lyrics' : '歌词加载失败';
  String get checkNetwork =>
      en ? 'Check the connection and try again' : '请检查网络连接后重试';
  String get lyricsEmpty => en ? 'No lyrics' : '暂无歌词';
  String get lyricsUnavailable =>
      en ? 'No lyric file for this song' : '该歌曲暂时没有可用的歌词文件';
  String get searchLyrics => en ? 'Search lyrics' : '搜索歌词';
  String qualityText(String q) => switch (q) {
    'flac24bit' => en ? 'Master' : '臻品母带',
    'flac' => en ? 'Lossless' : '无损',
    'hires' => 'Hi-Res',
    '320k' => '320kbps',
    '192k' => '192kbps',
    '128k' => '128kbps',
    _ => q,
  };
  String platformText(String p) => switch (p) {
    'tx' => en ? 'QQ Music' : 'QQ音乐',
    'kw' => en ? 'Kuwo' : '酷我音乐',
    'wy' => en ? 'NetEase' : '网易云音乐',
    'kg' => en ? 'Kugou' : '酷狗音乐',
    'mg' => en ? 'Migu' : '咪咕音乐',
    'local' => localMusic,
    'subsonic' || 'emby' || 'jellyfin' || 'plex' || 'audiostation' => 'NAS',
    _ => p.isEmpty ? (en ? 'Unknown' : '未知') : p,
  };
  String presetName(String id) => switch (id) {
    'flat' => en ? 'Flat' : '原声',
    'pop' => en ? 'Pop' : '流行',
    'rock' => en ? 'Rock' : '摇滚',
    'jazz' => en ? 'Jazz' : '爵士',
    'classical' => en ? 'Classical' : '古典',
    'electronic' => en ? 'Electronic' : '电子',
    'folk' => en ? 'Folk' : '民谣',
    'vocal' => en ? 'Vocal' : '人声',
    'bass' => en ? 'Bass boost' : '低音增强',
    'treble' => en ? 'Treble boost' : '高音增强',
    _ => customPreset,
  };
  String get equalizerUnavailable =>
      en ? 'Equalizer is not available here' : '当前平台不支持均衡器';
  String get equalizerUnavailableBody => en
      ? 'The equalizer needs an audio-effects channel. AVPlayer on iOS and macOS, and Media Foundation on Windows, do not expose one, so it currently works on Android only.'
      : '均衡器需要播放引擎开放音频特效通道。iOS / macOS 的 AVPlayer 与 Windows 的 Media Foundation 都没有暴露这一层，因此暂时只在 Android 上生效。';
  String get equalizerHint =>
      en ? 'Adjust the tone for every source' : '按频段调整播放音色，对所有音源生效';
  String get unavailableOnPlatform =>
      en ? 'Not available on this platform' : '当前平台不可用';
  String get gainDb => en ? 'Gain (dB)' : '增益（dB）';
  String get enableEqualizerToAdjust =>
      en ? 'Turn the equalizer on to adjust' : '开启均衡器后可调节';
  String bandsReady(int count, String range) =>
      en ? 'Device bands: $count ($range)' : '已读取设备频段：$count 段（$range）';
  String get bandsPending => en
      ? 'Player not connected. Showing a typical 5-band layout until playback starts.'
      : '播放器尚未连接，暂按常见 5 段展示；开始播放后会自动读取设备频段';
  String get localMusicSettings => en ? 'Local music' : '本地音乐设置';
  String get rescan => en ? 'Scan again' : '重新扫描';
  String get noLocalSongs => en
      ? 'No local songs yet\nAdd a folder, or wait for downloads to be scanned'
      : '还没有本地歌曲\n添加文件夹或等待下载完成后自动扫描';
  String localSongCount(int count) => en
      ? '$count local songs\nPlay them from Playlists > Local music'
      : '已收录 $count 首本地歌曲\n前往「我的歌单 > 本地音乐」播放';
  String get localLibraryTitle => en ? 'On this device' : '本地音乐库';
  String mediaStoreHint(int count) => en
      ? 'MediaStore can rescan. $count folders saved'
      : 'MediaStore 可重扫，已配置 $count 个目录';
  String get folderPickerHint =>
      en ? 'Add opens the system folder picker' : '添加会打开系统文件夹选择器并授权访问';
  String get androidMediaStore =>
      en ? 'Android MediaStore · scanned first' : 'Android MediaStore · 默认优先扫描';
  String downloadFolder(String path) =>
      en ? 'Downloads · added automatically\n$path' : '下载目录 · 自动收录\n$path';
  String get writeTags => en ? 'Write tags (experimental)' : '注入tag（实验性）';
  String get writeTagsHint => en
      ? 'Write title, artist, album, and artwork into the file. Needs file access.'
      : '将歌名，歌手，专辑，封面等信息写入歌曲文件，需要读写权限';
  String get pickFolderFailed =>
      en ? 'Could not choose a music folder' : '选择音乐文件夹失败';
  String get chooseMusicFolder => en ? 'Choose a music folder' : '选择音乐文件夹';
  String get chooseFolderFailed => en ? 'Could not choose a folder' : '选择文件夹失败';
  String get safImporting =>
      en ? 'Importing the music folder…' : 'SAF 正在导入音乐文件夹…';
  String importingCount(int done, int total) =>
      en ? 'Importing $done / $total' : 'SAF 正在导入 $done / $total';
  String get scanAndroidFailed =>
      en ? 'Could not scan the Android music folder' : '扫描 Android 音乐文件夹失败';
  String get mediaStoreScanning => en
      ? 'Scanning local music with Android MediaStore…'
      : '正在通过 Android MediaStore 扫描本地音乐…';
  String mediaStoreImporting(int done, int total) =>
      en ? 'MediaStore $done / $total' : 'MediaStore 正在导入 $done / $total';
  String get mediaStoreEmpty =>
      en ? 'MediaStore returned no audio' : 'MediaStore 未返回音频';
  String get tryingAllFiles => en
      ? 'MediaStore is unavailable. Trying all-files access…'
      : 'MediaStore 不可用，正在尝试全部文件访问权限…';
  String allFilesScanning(int done, int total) =>
      en ? 'Scanning $done / $total' : '全部文件访问正在扫描 $done / $total';
  String get openingSaf => en
      ? 'All-files access is unavailable. Opening folder access…'
      : '全部文件访问不可用，正在打开 SAF 目录授权…';
  String get androidAccessDenied =>
      en ? 'Android music access was not granted' : '未获得可用的 Android 本地音乐访问权限';
  String get androidAuthFailed =>
      en ? 'Android music access failed' : 'Android 本地音乐授权失败';
  String get matchingOnline => en ? 'Matching online songs…' : '正在匹配在线歌曲（刮削）…';
  String scanningPath(String path) => en ? 'Scanning $path…' : '正在扫描 $path …';
  String readingMetadata(int done, int total) =>
      en ? 'Reading tags $done / $total' : '正在解析元数据 $done / $total';
  String get scanFailed => en ? 'Scan failed' : '扫描失败';
  String get noLocalSources =>
      en ? 'No local music folders yet' : '还没有配置本地音乐来源';
  String get rescanning => en ? 'Scanning local music again…' : '正在重新扫描本地音乐来源…';
  String get rescanFailed => en ? 'Could not scan again' : '重新扫描失败';
  String scrapingCount(int done, int total) =>
      en ? 'Matching $done / $total' : '正在刮削 $done / $total';
  String localUpdated(int count) =>
      en ? 'Local music updated ($count songs)' : '本地音乐已更新（$count 首）';
  String get noWritableSongs => en ? 'No local songs to write' : '没有可写入的本地歌曲';
  String get writingTags =>
      en ? 'Writing tags back to the files…' : '正在尝试写回原文件标签…';
  String writingTagsCount(int done, int total) =>
      en ? 'Writing tags $done / $total' : '正在写回原文件标签 $done / $total';
  String get noTagsToWrite => en ? 'No tags to write back' : '没有可写回的刮削标签';
  String tagsWritten(int written, int attempted) => en
      ? 'Tags written: $written / $attempted'
      : '标签写回完成：成功 $written / $attempted';
  String get writeTagsFailed => en ? 'Could not write tags' : '写回标签失败';
  String get folderRemoved => en ? 'Folder removed' : '已移除文件夹';
  String get downloadsTitle => en ? 'Downloads' : '下载管理';
  String get deleteFinishedDownloads =>
      en ? 'Delete finished downloads' : '删除已完成下载';
  String get clearFailedTasks => en ? 'Clear failed downloads' : '清理失败任务';
  String get noDownloadTasks => en ? 'No downloads' : '暂无下载任务';
  String get noTasks => en ? 'Nothing here' : '暂无任务';
  String get downloadSpeed => en ? 'Speed' : '下载速度';
  String get downloaded => en ? 'Downloaded' : '已下载';
  String activeHeader(int count) => en ? 'Active ($count)' : '进行中 ($count)';
  String finishedHeader(int count) => en ? 'Finished ($count)' : '已完成 ($count)';
  String downloadingPercent(String percent) =>
      en ? 'Downloading $percent%' : '下载中 $percent%';
  String pausedPercent(String singer, String percent) =>
      en ? '$singer · Paused $percent%' : '$singer · 已暂停 $percent%';
  String get linkExpired => en ? 'Link expired. Download failed.' : '链接失效，下载失败';
  String deleteFinishedBody(int count) => en
      ? 'Delete $count finished downloads and their audio files? This cannot be undone.'
      : '确定要删除 $count 个已完成记录及其音频文件吗？此操作不可撤销。';
  String get deleteFiles => en ? 'Delete files' : '删除文件';
  String clearFailedBody(int count) => en
      ? 'Delete $count failed downloads and leftover files?'
      : '确定要删除 $count 个失败任务及其残留文件吗？';
  String get clearFailedAction => en ? 'Clear' : '清理';
  String get listeningStatsEmpty => en ? 'No listening data yet' : '暂无播放数据';
  String get listeningStatsEmptyHint => en
      ? 'Play a few songs and a report will show up here'
      : '多听几首歌，这里会生成你的听歌报告';
  String get playCount => en ? 'Plays' : '播放次数';
  String get listenTime => en ? 'Time' : '听歌时长';
  String get activeDays => en ? 'Active days' : '活跃天数';
  String get trackCount => en ? 'Tracks' : '单曲数';
  String get dailyPlays => en ? 'Daily plays' : '每日播放';
  String dailyPeak(int days, int maxCount) =>
      en ? '$days days · peak $maxCount' : '$days 天 · 峰值 $maxCount 次';
  String get songs => en ? 'Songs' : '歌曲';
  String get artists => en ? 'Artists' : '艺术家';
  String get albums => en ? 'Albums' : '专辑';
  String get noData => en ? 'No data' : '暂无数据';
  String statSubtitle(String subtitle, int count) =>
      en ? '$subtitle · $count plays' : '$subtitle · $count次';
  String get loadFailed => en ? 'Could not load' : '加载失败';
  String get noDuplicateFavorites =>
      en ? 'No duplicate songs in Favorites' : '收藏列表没有重复歌曲';
  String get selectRecommended => en ? 'Select suggested' : '按推荐勾选';
  String get working => en ? 'Working…' : '处理中…';
  String get removeSelected => en ? 'Remove selected' : '移除已选';
  String duplicateGroup(String artist, int count) => en
      ? '$artist · $count versions · select the ones to remove'
      : '$artist · $count 个版本 · 勾选要移除的';
  String get removeGroupSelected =>
      en ? 'Remove selected in this group' : '移除本组已选';
  String get keepSuggested => en ? 'Keep' : '推荐保留';
  String get hasLyricsMark => en ? ' · Lyrics' : ' · 有歌词';
  String removedDuplicates(int count) =>
      en ? 'Removed $count duplicates' : '已移除 $count 处重复项';
  String get addedToPlaylist => en ? 'Added to playlist' : '已添加到歌单';
  String get playlistCreatedAndAdded => en ? 'Playlist created' : '已创建歌单并添加';
  String get collapseNewPlaylist => en ? 'Hide new playlist' : '收起新建歌单';
  String get newPlaylistName => en ? 'New playlist name' : '新歌单名称';
  String playlistSongCount(int count) => en ? '$count songs' : '$count 首';
  String get basedOnFavorites => en ? 'Based on music you like' : '根据你喜欢的音乐推荐';
  String recommendUpdated(int count) =>
      en ? '$count songs · keeps updating' : '推荐 $count 首 · 持续更新';
  String get noRecommendations => en ? 'No recommendations yet' : '还没有推荐';
  String get recommendationsNeedFavorites => en
      ? 'After Favorites reaches 100 songs, 30 are picked at random'
      : '“收藏列表”满 100 首后，将随机取样推荐 30 首歌曲';
  String get playlistEmpty => en ? 'This playlist is empty' : '歌单为空';
  String get playlistEmptyNas => en ? 'This playlist is empty' : '歌单是空的';
  String get connectionSettings => en ? 'Connection' : '连接设置';
  String get scraping => en ? 'Matching' : '正在刮削';
  String get scrapeArtworkLyrics => en ? 'Match artwork and lyrics' : '刮削封面和歌词';
  String scrapingProgress(int done, int total) =>
      en ? 'Matching $done / $total' : '正在刮削 $done / $total';
  String notConnected(String name) =>
      en ? '$name is not connected' : '尚未连接 $name';
  String get goConnect => en ? 'Connect' : '去连接';
  String connectedHost(String host) =>
      en ? 'Connected to $host' : '当前已连接 $host';
  String get noOnlineMatch =>
      en ? 'No online artwork or lyrics matched' : '没有匹配到在线封面或歌词';
  String matchedSongs(int matched, int total) => en
      ? 'Matched artwork and lyrics for $matched / $total songs'
      : '已为 $matched / $total 首匹配封面和歌词';
  String scrapeFailed(Object error) =>
      en ? 'Match failed: $error' : '刮削失败: $error';
  String nasPlaylistTitle(String name) => en ? '$name playlist' : '$name 歌单';
  String get welcome => en ? 'Welcome to Koyze' : '欢迎使用 Koyze';
  String get welcomeBody => en
      ? 'Sign in to sync favorites, playlists, settings, and custom sources across devices.'
      : '登录云端账号后，可跨设备同步收藏、歌单、设置和自定义音源。';
  String get serverAddress => en ? 'Server address' : '服务器地址';
  String get syncUsernameHint => en ? 'Account name' : '同步账号用户名';
  String get syncPasswordHint => en ? 'Account password' : '同步账号密码';
  String get registerAndSync => en ? 'Create account and sync' : '注册并开始同步';
  String get loginAndSync => en ? 'Log in and sync' : '登录并开始同步';
  String get backToLogin => en ? 'I already have an account' : '已有账号，返回登录';
  String get needAccount => en ? 'Need an account? Register' : '还没有账号？注册一个';
  String get skipStep => en ? 'Skip for now' : '跳过这一步';
  String get skipStepHint => en
      ? 'You can still play locally. Add an account later in Settings → Sync.'
      : '跳过后不会影响本地播放；你之后可以随时在“设置 → 同步”添加账号。';
  String get fillServerLogin =>
      en ? 'Enter the server, username, and password' : '请填写服务器、用户名和密码';
  String get loginFailed => en ? 'Could not log in' : '登录失败';
  String get syncTitle => en ? 'Sync' : '同步 / 云端账号';
  String get workersServer => en ? 'Workers server' : 'Workers 服务器';
  String get workersUnset => en
      ? 'Not set (for example https://xxx.workers.dev)'
      : '未配置（例如 https://xxx.workers.dev）';
  String loggedInAs(String name) => en ? 'Signed in: $name' : '已登录：$name';
  String get notLoggedIn => en ? 'Not signed in' : '未登录';
  String roleLine(String role) => en ? 'Role: $role' : '角色：$role';
  String get loginToSync =>
      en ? 'Sign in to sync cloud playlists' : '登录后可同步云端歌单';
  String get syncing => en ? 'Syncing…' : '同步中…';
  String get syncExplainer => en
      ? 'Search and playback stay on this device. The cloud keeps your account, playlists, settings, and sources.'
      : '说明：在此配置并登录 workers 后端。搜歌/播放仍在本机完成，云端负责账号、歌单、设置与音源。';
  String get eventSync => en ? 'Sync changes' : '事件同步';
  String get syncNow => en ? 'Sync now' : '立即同步';
  String get mergingEvents =>
      en ? 'Merging changes from this device and the cloud…' : '正在安全合并本地与云端事件…';
  String get syncDoesNotOverwrite => en
      ? 'Uploads local changes and downloads other devices. Nothing is overwritten.'
      : '只上传本地变更并拉取其他设备变更，不覆盖数据';
  String get offlineUntilNetwork => en
      ? 'Saved on this device. Syncs when the network returns.'
      : '数据保存在本地，网络恢复后自动同步';
  String deviceLine(String id) => en ? 'Device: $id' : '设备：$id';
  String timeLine(String time) => en ? 'Time: $time' : '时间：$time';
  String get logOut => en ? 'Log out' : '退出登录';
  String get logOutHint => en
      ? 'Favorites, playlists, ratings, history, downloads, and cache stay. Only the login is cleared.'
      : '退出后保留收藏、歌单、评分、播放历史、下载与缓存，仅清除登录状态';
  String get loggedOut => en ? 'Logged out' : '已退出登录';
  String get userAdmin => en ? 'Users (admin)' : '用户管理（管理员）';
  String get userAdminHint =>
      en ? 'Create, delete, or reset passwords' : '创建 / 删除 / 重置密码';
  String get workersAddress => en ? 'Workers address' : 'Workers 地址';
  String get serverReachable => en ? 'Server is reachable' : '服务器可达';
  String get savedHealthFailed => en
      ? 'Saved, but the health check failed. Try again after deploy.'
      : '保存成功，但健康检查失败（部署后重试）';
  String get httpsRequired =>
      en ? 'The server address must use HTTPS' : '服务器地址必须使用 HTTPS';
  String get enterServerFirst =>
      en ? 'Enter the server address first' : '请先填写服务器地址';
  String get loginSucceeded => en ? 'Signed in' : '登录成功';
  String get failed => en ? 'Failed' : '失败';
  String get syncFinished => en ? 'Sync finished' : '同步完成';
  String syncFailed(Object error) => en ? 'Sync failed: $error' : '同步失败：$error';
  String get userList => en ? 'Users' : '用户列表';
  String adminUser(String id) => en ? 'Admin · id=$id' : '管理员 · id=$id';
  String normalUser(String id) => en ? 'User · id=$id' : '普通用户 · id=$id';
  String deleteUser(String name) => en ? 'Delete $name' : '删除 $name';
  String deletedUser(String name) => en ? 'Deleted $name' : '已删除 $name';
  String get newUser => en ? 'New user' : '新建用户';
  String get userCreated => en ? 'User created' : '已创建用户';
  String usersLoadFailed(Object error) =>
      en ? 'Could not load users: $error' : '加载用户失败: $error';
  String get customSourcesTitle => en ? 'Custom sources' : '自定义源';
  String get importLocalScript => en ? 'Import a script file' : '导入本地脚本';
  String get importFromLink => en ? 'Import from a link' : '通过链接导入';
  String get addManually => en ? 'Add manually' : '手动添加';
  String get pasteScript => en ? 'Paste a script' : '粘贴脚本';
  String get noCustomSources => en ? 'No custom sources' : '暂无自定义源';
  String get addCustomSourceHint =>
      en ? 'Use + to add a custom source' : '点击右上角 + 添加自定义源';
  String sourceInitFailed(String name) =>
      en ? '$name failed to start. Check the script.' : '$name 初始化失败，请检查脚本';
  String get importScriptOk => en ? 'Script imported' : '导入脚本成功';
  String get importScriptBad =>
      en ? 'Import failed. The script format is wrong.' : '导入失败，脚本格式错误';
  String readFileFailed(Object error) =>
      en ? 'Could not read the file: $error' : '读取文件失败: $error';
  String get addCustomSource => en ? 'Add a custom source' : '添加自定义源';
  String get sourceName => en ? 'Name' : '源名称';
  String get author => en ? 'Author' : '作者';
  String get script => en ? 'Script' : '脚本';
  String get editCustomSource => en ? 'Edit custom source' : '编辑自定义源';
  String get httpsLinkRequired =>
      en ? 'Enter a valid HTTPS link' : '请输入有效的 HTTPS 链接';
  String get importOk => en ? 'Imported' : '导入成功';
  String get importLinkBad =>
      en ? 'Import failed. Check the link or the script.' : '导入失败，请检查链接或脚本格式';
  String get directDownloadHint =>
      en ? 'Paste a direct link to the script file' : '请输入脚本文件的直接下载链接';
  String get clipboardEmpty => en ? 'The clipboard has no link' : '剪切板中没有链接';
  String get clipboard => en ? 'Clipboard' : '剪切板';
  String get importCustomSource => en ? 'Import a custom source' : '导入自定义源';
  String get lxScriptHint =>
      en ? 'LX Music scripts are supported' : '支持 LX Music 格式脚本';
  String get pasteScriptHint =>
      en ? 'Paste an LX Music script or JSON…' : '粘贴 LX Music 脚本或 JSON 配置...';
  String get importFormatBad =>
      en ? 'Import failed. Check the script format.' : '导入失败，请检查脚本格式';
  String get exportCustomSource => en ? 'Export custom source' : '导出自定义源';
  String get deleteCustomSource => en ? 'Delete custom source' : '删除自定义源';
  String deleteSourceConfirm(String name) =>
      en ? 'Delete “$name”?' : '确定要删除“$name”吗？';
  String get logCopied => en ? 'Log copied' : '日志已复制';
  String sourceLogTitle(String name) => en ? '$name log' : '$name 日志';
  String get noLog => en ? 'No log yet' : '暂无日志';
  String get copyLog => en ? 'Copy log' : '复制日志';
  String get enterUsername => en ? 'Enter a username' : '请输入用户名';
  String get enterPassword => en ? 'Enter a password' : '请输入密码';
  String get enterPasswordOrToken =>
      en ? 'Enter a password or X-Plex-Token' : '请输入密码或 X-Plex-Token';
  String connectedType(String type, String? version) => version == null
      ? (en ? 'Connected to $type' : '已连接 $type')
      : (en ? 'Connected to $type $version' : '已连接 $type $version');
  String get connectFailed => en ? 'Could not connect' : '连接失败';
  String disconnected(String name) =>
      en ? 'Disconnected from $name' : '已断开 $name';
  String get nasServerTitle => en ? 'NAS music server' : 'NAS 音乐服务器';
  String get usernameOptional => en ? 'Username (optional)' : '用户名（可留空）';
  String get plexAccountHint => en
      ? 'plex.tv account. Leave empty to use a token.'
      : 'plex.tv 账号，留空则使用 Token';
  String get serverLoginName => en ? 'Server username' : '服务器登录名';
  String get passwordOrToken => en ? 'Password / token' : '密码 / Token';
  String get passwordSaved =>
      en ? 'Saved. Enter it again only when reconnecting.' : '已保存，重新连接时再输入';
  String get passwordOrPlexToken =>
      en ? 'Password or X-Plex-Token' : '密码或 X-Plex-Token';
  String get serverPassword => en ? 'Server password' : '服务器密码';
  String get showPassword => en ? 'Show password' : '显示密码';
  String get hidePassword => en ? 'Hide password' : '隐藏密码';
  String get legacyAuth => en ? 'Legacy sign-in' : '旧版鉴权';
  String get legacyAuthHint => en
      ? 'Only if token sign-in fails. The password is sent as plain text.'
      : '仅当 token 鉴权失败时开启，密码会以明文参数发送';
  String get reconnect => en ? 'Reconnect' : '重新连接';
  String get disconnect => en ? 'Disconnect' : '断开连接';
  String currentConnection(String title, String host, String? username) =>
      username == null
      ? (en ? 'Current: $title · $host' : '当前：$title · $host')
      : (en
            ? 'Current: $title · $host · $username'
            : '当前：$title · $host · $username');
  String get diagnosticsTitle => en ? 'Diagnostics' : '实时诊断日志';
  String diagnosticsCount(int count) => en ? 'Log $count' : '诊断 $count';
  String get minimize => en ? 'Minimize' : '最小化';
  String get copyAll => en ? 'Copy all' : '复制全部';
  String get closeDiagnostics => en ? 'Close diagnostics' : '关闭诊断日志';
  String get clearMemoryLog => en ? 'Clear log' : '清空内存日志';
  String get diagnosticsHint => en
      ? 'Kept in memory for this run only. Closing or restarting the app clears it.'
      : '仅保存在当前运行内存；关闭或重启应用后自动清空。';
  String playingQuoted(String name) => en ? 'Playing “$name”' : '播放“$name”';
  String get stoppedAfterRepeatedFailures => en
      ? 'Five songs failed in a row. Autoplay stopped.'
      : '连续 5 首歌曲播放失败，已停止自动播放';
  String get autoplayNextFailed => en
      ? 'Could not play the next song. Open Koyze and try again.'
      : '自动播放下一首失败，请返回应用重试';
  String get reloadingSong =>
      en ? 'Playback failed. Reloading.' : '播放歌曲失败，正在重新加载';
  String get tryingNextSong =>
      en ? 'Playback failed. Trying the next song.' : '播放歌曲失败，正在尝试下一首';
  String unresolvedUrl(String title) => en
      ? 'Could not resolve “$title”. The source had no playable address, or the local cache failed.'
      : '无法解析歌曲 “$title” 的播放地址（源无效地址或本地缓存失败，已尝试降级音质）';
  String playSongFailed(String title, Object error) =>
      en ? 'Could not play “$title”: $error' : '播放歌曲 “$title” 失败: $error';
}

String localizeUserMessage(String message, S s) {
  switch (message) {
    case '连续 5 首歌曲播放失败，已停止自动播放':
      return s.stoppedAfterRepeatedFailures;
    case '自动播放下一首失败，请返回应用重试':
      return s.autoplayNextFailed;
    case '播放歌曲失败，正在重新加载':
      return s.reloadingSong;
    case '播放歌曲失败，正在尝试下一首':
      return s.tryingNextSong;
  }
  final playing = RegExp('^播放"(.*)"\$').firstMatch(message);
  if (playing != null) return s.playingQuoted(playing.group(1)!);
  final unresolved = RegExp('^无法解析歌曲 "(.*)" 的播放地址').firstMatch(message);
  if (unresolved != null) return s.unresolvedUrl(unresolved.group(1)!);
  final failed = RegExp('^播放歌曲 "(.*)" 失败: (.*)').firstMatch(message);
  if (failed != null) {
    return s.playSongFailed(failed.group(1)!, failed.group(2)!);
  }
  return message;
}

bool localeIsEnglish(Locale? locale) => locale?.languageCode == 'en';
