// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get home => '首页';

  @override
  String get charts => '榜单';

  @override
  String get playlists => '歌单';

  @override
  String get settings => '设置';

  @override
  String get sync => '同步';

  @override
  String get cloudAccount => '云端账号 / 歌单';

  @override
  String get cloudAccountSubtitle => '同步收藏、歌单、设置与自定义音源';

  @override
  String get advanced => '高级功能';

  @override
  String get localLibrary => '本地音乐目录';

  @override
  String get localLibrarySubtitle => '设置扫描目录、刷新本地歌曲与在线刮削';

  @override
  String get customSources => '自定义源';

  @override
  String get customSourcesSubtitle => '管理自定义音乐源';

  @override
  String get nasServer => 'NAS 音乐服务器';

  @override
  String get sourcesAndLibrary => '音源与本地库';

  @override
  String get playback => '播放';

  @override
  String get audioQuality => '音质选择';

  @override
  String get chooseQuality => '选择音质';

  @override
  String get equalizer => '均衡器';

  @override
  String get sleepTimer => '睡眠定时';

  @override
  String get cancel => '取消';

  @override
  String get sleepTimerCancelled => '已取消睡眠定时';

  @override
  String get autoResume => '自动恢复播放';

  @override
  String get autoResumeSubtitle => '打开 App 时自动继续播放上次的歌曲';

  @override
  String get floatingPlayer => '悬浮窗';

  @override
  String get floatingPlayerSubtitle => '离开应用后显示封面、歌词、进度和播放控制';

  @override
  String get floatingPlayerPermission => '请允许显示在其他应用上层，然后返回 Koyze';

  @override
  String get forceLandscape => '强制横屏';

  @override
  String get forceLandscapeSubtitle => '使用横屏布局。手机还会锁定为横屏方向';

  @override
  String get simplifyEffects => '关闭特效';

  @override
  String get simplifyEffectsSubtitle => '关闭磨砂玻璃、透明和动效。内存不超过 4GB 时默认开启';

  @override
  String get defaultSearchPlatform => '默认搜索平台';

  @override
  String get listeningStats => '听歌统计';

  @override
  String get listeningStatsSubtitle => '播放历史 · Top 排行 · 热力图';

  @override
  String get appearance => '外观';

  @override
  String get language => '语言';

  @override
  String get darkMode => '深色模式';

  @override
  String get darkModeSubtitle => '使用深色主题';

  @override
  String get followSystem => '跟随系统';

  @override
  String get followSystemThemeSubtitle => '自动切换亮色/深色主题';

  @override
  String get followSystemLanguageSubtitle => '设备为中文或英文时自动跟随';

  @override
  String get themeColor => '主题色';

  @override
  String get themeColorSubtitle => '由一个强调色生成整套浅色/深色色板';

  @override
  String get playerBackdrop => '全屏播放器背景';

  @override
  String get playerBackdropSubtitle => '封面的虚化与压暗程度';

  @override
  String get playerBackdropBlur => '背景模糊';

  @override
  String get playerBackdropScrim => '遮罩透明度';

  @override
  String get playerBackdropPreviewEmpty => '没有正在播放的歌曲';

  @override
  String get resetToDefault => '恢复默认';

  @override
  String get general => '通用';

  @override
  String get downloads => '下载';

  @override
  String get downloadManager => '下载管理';

  @override
  String get downloadManagerSubtitle => '查看和管理下载任务';

  @override
  String get wifiOnly => '仅 WiFi 下载';

  @override
  String get wifiOnlySubtitle => '仅在 WiFi 环境下下载歌曲';

  @override
  String get downloadQuality => '下载音质';

  @override
  String get chooseDownloadQuality => '选择下载音质';

  @override
  String get data => '数据';

  @override
  String get dataAndSync => '数据与同步';

  @override
  String get backup => '备份数据';

  @override
  String get backupSubtitle => '导出歌单、设置等数据到文件';

  @override
  String get restore => '恢复数据';

  @override
  String get restoreSubtitle => '从备份文件恢复数据';

  @override
  String get clearCache => '清除缓存';

  @override
  String get clearCacheSubtitle => '清除歌曲播放缓存、封面缓存和临时文件';

  @override
  String get about => '关于';

  @override
  String get version => '版本';

  @override
  String get deviceUuid => '设备 UUID';

  @override
  String get loading => '读取中…';

  @override
  String get deviceUuidCopied => '完整设备 UUID 已复制';

  @override
  String get diagnostics => '实时诊断日志';

  @override
  String get diagnosticsSubtitle => '点开开始记录，最小化后继续记录（不保存）';

  @override
  String get volume => '音量';

  @override
  String get mute => '静音';

  @override
  String get unmute => '取消静音';

  @override
  String get download => '下载';

  @override
  String get addedToDownloads => '已添加到下载队列';

  @override
  String get downloadFailed => '添加下载失败';

  @override
  String get exportBackupTitle => '导出 Koyze 备份';

  @override
  String get restoreSucceeded => '数据恢复成功';

  @override
  String get chooseCache => '选择要清除的内容';

  @override
  String get selectAll => '全选';

  @override
  String get playbackCache => '歌曲播放缓存';

  @override
  String get playbackCacheSubtitle => '自动缓存的歌曲文件，不包含手动下载的歌曲';

  @override
  String get artworkCache => '封面缓存';

  @override
  String get artworkCacheSubtitle => '专辑封面的磁盘和内存缓存';

  @override
  String get tempFiles => '临时文件';

  @override
  String get tempFilesSubtitle => '系统临时目录中的中间文件';

  @override
  String get cacheKeepNote => '手动下载的歌曲不会被删除；正在播放的歌曲缓存会安全保留。';

  @override
  String get clear => '清除';

  @override
  String get cacheCleared => '所选缓存已清除';

  @override
  String get cancelSleepTimer => '取消睡眠定时';

  @override
  String get chineseInterface => '中文界面';

  @override
  String get englishInterface => '英文界面';

  @override
  String get shortcuts => '快捷功能';

  @override
  String get shortcutSettings => '快捷功能设置';

  @override
  String get closeShortcutSettings => '关闭快捷功能设置';

  @override
  String get searchSongsHint => '搜索歌曲、歌手、歌单...';

  @override
  String get heroCardSettings => '首页大卡片设置';

  @override
  String get heroCardSettingsAction => '设置首页大卡片';

  @override
  String get closeHeroCardSettings => '关闭首页大卡片设置';

  @override
  String get heroCardHint => '对应歌单页顶部五张卡片，只能启用其中一张';

  @override
  String get heroPlayMode => '右侧按钮播放模式';

  @override
  String get heroPlayModeHint => '只影响首页大卡片右侧按钮，和播放页模式互不影响';

  @override
  String get favorites => '收藏列表';

  @override
  String get forYou => '猜你喜欢';

  @override
  String get localMusic => '本地音乐';

  @override
  String get nasLibrary => 'NAS 乐库';

  @override
  String get recentPlays => '最近播放';

  @override
  String get playInOrder => '顺序播放';

  @override
  String get shufflePlay => '随机播放';

  @override
  String get repeatOne => '单曲循环';

  @override
  String get playInOrderHint => '按列表顺序播放，播完回到第一首';

  @override
  String get shufflePlayHint => '打乱顺序，播完继续随机下一首';

  @override
  String get repeatOneHint => '只循环当前第一首';

  @override
  String get noFavoritesYet => '还没有收藏歌曲';

  @override
  String get recommendAfterFavorites => '收藏歌曲后为你推荐';

  @override
  String get heroRecentEmpty => '还没有播放记录';

  @override
  String get chooseFolderToScan => '选择文件夹扫描设备歌曲';

  @override
  String get nasHosts => 'Navidrome / Emby / Plex / 群晖';

  @override
  String get loadSongsFailed => '加载歌曲失败';

  @override
  String get playFailed => '播放失败';

  @override
  String get noSongsOnServer => '服务器上还没有歌曲';

  @override
  String get retry => '重试';

  @override
  String get otherPlatform => '其他';

  @override
  String get featured => '精选';

  @override
  String get noChartData => '暂无排行榜数据';

  @override
  String get chartsHidden => '已隐藏全部榜单\\n点击右上角设置恢复';

  @override
  String get chartSettings => '榜单设置';

  @override
  String get refreshCharts => '刷新榜单';

  @override
  String get noSongData => '暂无歌曲数据';

  @override
  String get showAll => '全部显示';

  @override
  String get back => '返回';

  @override
  String get defaultFirst => '默认优先';

  @override
  String get importPlaylist => '导入歌单';

  @override
  String get newPlaylist => '新建歌单';

  @override
  String get searchLibraryHint => '在库中搜索歌曲/歌单';

  @override
  String get clearSearch => '清除搜索内容';

  @override
  String get clearResults => '清空';

  @override
  String get customPlaylists => '自定义歌单';

  @override
  String get sortPlaylists => '排序歌单';

  @override
  String get nothingMatched => '未找到匹配的歌曲或歌单';

  @override
  String get createPlaylist => '创建歌单';

  @override
  String get playlistName => '歌单名称';

  @override
  String get descriptionOptional => '描述（可选）';

  @override
  String get create => '创建';

  @override
  String get editPlaylist => '编辑歌单';

  @override
  String get save => '保存';

  @override
  String get sortBy => '排序方式';

  @override
  String get recentlyAdded => '最近添加';

  @override
  String get sortByName => '名称排序';

  @override
  String get sortByCount => '歌曲数量';

  @override
  String get pastePlaylistLink => '粘贴分享链接或输入歌单 ID';

  @override
  String get closeImport => '关闭导入歌单';

  @override
  String get sourcePlatform => '来源平台';

  @override
  String get kuwoShort => '酷我';

  @override
  String get kugouShort => '酷狗';

  @override
  String get neteaseShort => '网易';

  @override
  String get playlistLinkOrId => '歌单链接或 ID';

  @override
  String get enterLinkOrId => '请输入链接或 ID';

  @override
  String get importAction => '导入';

  @override
  String get parsingPlaylist => '正在解析歌单…';

  @override
  String get parsePlaylist => '解析歌单';

  @override
  String get addAllToFavorites => '全部添加到收藏列表';

  @override
  String get addFailed => '添加失败';

  @override
  String get alreadyInFavorites => '所有歌曲已在收藏列表中';

  @override
  String get deletePlaylist => '删除歌单';

  @override
  String get deleteFailed => '删除失败';

  @override
  String get createFailed => '创建失败';

  @override
  String get saveFailed => '保存失败';

  @override
  String get choosePlatform => '选择平台';

  @override
  String get platform => '平台';

  @override
  String get searchFieldHint => '搜索歌曲、歌单...';

  @override
  String get searchAction => '搜索';

  @override
  String get noResults => '无结果';

  @override
  String get searchEmptyHint => '换个关键词，或切换到其他平台再试';

  @override
  String get searchErrorTitle => '搜索暂时不可用';

  @override
  String get searchAllSources => '搜索全部平台';

  @override
  String get onlineMusic => '网络音乐';

  @override
  String get slideForMore => '滑动加载更多';

  @override
  String get moreActions => '更多操作';

  @override
  String get searchHistory => '搜索历史';

  @override
  String get clearHistory => '清空';

  @override
  String get hotSearch => '热搜榜';

  @override
  String get loadingEllipsis => '加载中...';

  @override
  String get playNow => '立即播放';

  @override
  String get addToPlaylist => '添加到歌单';

  @override
  String get favorite => '收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get favoriteFailed => '收藏失败';

  @override
  String get playbackProgress => '播放进度';

  @override
  String get nothingPlaying => '暂无播放内容';

  @override
  String get unknownQuality => '未知音质';

  @override
  String get resolvingQuality => '解析中…';

  @override
  String get collapsePlayer => '收起播放器';

  @override
  String get backToArtwork => '返回封面';

  @override
  String get nowPlaying => '正在播放';

  @override
  String get lyrics => '歌词';

  @override
  String get more => '更多';

  @override
  String get openLyrics => '打开歌词';

  @override
  String get playMode => '播放模式';

  @override
  String get previous => '上一首';

  @override
  String get next => '下一首';

  @override
  String get queue => '播放队列';

  @override
  String get dislikeAndSkip => '不喜欢并跳过';

  @override
  String get dislikedNote => '已标记不喜欢，后续播放会自动跳过';

  @override
  String get dislikeFailed => '标记不喜欢失败';

  @override
  String get queueLoadFailed => '完整列表加载失败，显示当前队列';

  @override
  String get queueEmpty => '播放列表为空';

  @override
  String get playlistMissing => '歌单不存在';

  @override
  String get exitMultiSelect => '退出多选';

  @override
  String get cancelEdit => '取消编辑';

  @override
  String get deselectAll => '取消全选';

  @override
  String get downloadSelected => '下载已选歌曲';

  @override
  String get unfavoriteSelected => '取消收藏已选歌曲';

  @override
  String get playAll => '播放全部';

  @override
  String get alreadyFavorited => '歌曲已在收藏中';

  @override
  String get actionFailedShort => '操作失败';

  @override
  String get favoriteAll => '收藏所有';

  @override
  String get editInfo => '编辑信息';

  @override
  String get manualSort => '手动排序';

  @override
  String get sortByTitle => '按歌名排序';

  @override
  String get sortByArtist => '按歌手排序';

  @override
  String get sortByDuration => '按时长排序';

  @override
  String get duplicateSongs => '重复歌曲';

  @override
  String get clearFavorites => '清空收藏';

  @override
  String get noSongs => '暂无歌曲';

  @override
  String get locateFailed => '定位歌曲失败';

  @override
  String get play => '播放';

  @override
  String get removeFromPlaylist => '从歌单移除';

  @override
  String get removeFailed => '移除失败';

  @override
  String get nothingSelectedToDownload => '没有可下载的已选歌曲';

  @override
  String get nothingSelectedToUnfavorite => '没有可取消收藏的已选歌曲';

  @override
  String get unfavoriteFailed => '取消收藏失败';

  @override
  String get descriptionLabel => '描述';

  @override
  String get clearFavoritesTitle => '清空收藏？';

  @override
  String get confirmClear => '确认清空';

  @override
  String get favoritesAlreadyEmpty => '收藏列表已为空';

  @override
  String get delete => '删除';

  @override
  String get close => '关闭';

  @override
  String get pause => '暂停';

  @override
  String get refresh => '刷新';

  @override
  String get connect => '连接';

  @override
  String get reset => '重置';

  @override
  String get remove => '移除';

  @override
  String get start => '开始';

  @override
  String get log => '日志';

  @override
  String get edit => '编辑';

  @override
  String get export => '导出';

  @override
  String get customPreset => '自定义';

  @override
  String get presets => '预设';

  @override
  String get pauseAll => '暂停全部';

  @override
  String get waiting => '等待中';

  @override
  String get done => '已完成';

  @override
  String get all => '全部';

  @override
  String get username => '用户名';

  @override
  String get password => '密码';

  @override
  String get login => '登录';

  @override
  String get register => '注册';

  @override
  String get pleaseWait => '请稍候…';

  @override
  String get notice => '提示';

  @override
  String get success => '成功';

  @override
  String get warning => '警告';

  @override
  String get error => '错误';

  @override
  String get dismissNotification => '关闭通知';

  @override
  String get somethingWentWrong => '出错了';

  @override
  String get notPlaying => '未在播放';

  @override
  String get noLyrics => '无歌词';

  @override
  String get openNowPlaying => '打开正在播放';

  @override
  String get previousPage => '上一页';

  @override
  String get nextPage => '下一页';

  @override
  String get choosePage => '选择页码';

  @override
  String get preparingApp => '正在准备 Koyze';

  @override
  String get startupFailed => '应用初始化失败';

  @override
  String get startupLoading => '正在加载本地数据和播放服务…';

  @override
  String get retryStartup => '重试启动';

  @override
  String get lyricsLoading => '正在加载歌词';

  @override
  String get fetchingLyrics => '正在获取歌词内容';

  @override
  String get lyricsFailed => '歌词加载失败';

  @override
  String get checkNetwork => '请检查网络连接后重试';

  @override
  String get lyricsEmpty => '暂无歌词';

  @override
  String get lyricsUnavailable => '该歌曲暂时没有可用的歌词文件';

  @override
  String get searchLyrics => '搜索歌词';

  @override
  String get equalizerUnavailable => '当前平台不支持均衡器';

  @override
  String get equalizerUnavailableBody =>
      '均衡器需要播放引擎开放音频特效通道。iOS / macOS 的 AVPlayer 与 Windows 的 Media Foundation 都没有暴露这一层，因此暂时只在 Android 上生效。';

  @override
  String get equalizerHint => '按频段调整播放音色，对所有音源生效';

  @override
  String get unavailableOnPlatform => '当前平台不可用';

  @override
  String get gainDb => '增益（dB）';

  @override
  String get enableEqualizerToAdjust => '开启均衡器后可调节';

  @override
  String get bandsPending => '播放器尚未连接，暂按常见 5 段展示；开始播放后会自动读取设备频段';

  @override
  String get localMusicSettings => '本地音乐设置';

  @override
  String get rescan => '重新扫描';

  @override
  String get noLocalSongs => '还没有本地歌曲\\n添加文件夹或等待下载完成后自动扫描';

  @override
  String get localLibraryTitle => '本地音乐库';

  @override
  String get folderPickerHint => '添加会打开系统文件夹选择器并授权访问';

  @override
  String get androidMediaStore => 'Android MediaStore · 默认优先扫描';

  @override
  String get writeTags => '注入tag（实验性）';

  @override
  String get writeTagsHint => '将歌名，歌手，专辑，封面等信息写入歌曲文件，需要读写权限';

  @override
  String get pickFolderFailed => '选择音乐文件夹失败';

  @override
  String get chooseMusicFolder => '选择音乐文件夹';

  @override
  String get chooseFolderFailed => '选择文件夹失败';

  @override
  String get safImporting => 'SAF 正在导入音乐文件夹…';

  @override
  String get scanAndroidFailed => '扫描 Android 音乐文件夹失败';

  @override
  String get mediaStoreScanning => '正在通过 Android MediaStore 扫描本地音乐…';

  @override
  String get mediaStoreEmpty => 'MediaStore 未返回音频';

  @override
  String get tryingAllFiles => 'MediaStore 不可用，正在尝试全部文件访问权限…';

  @override
  String get openingSaf => '全部文件访问不可用，正在打开 SAF 目录授权…';

  @override
  String get androidAccessDenied => '未获得可用的 Android 本地音乐访问权限';

  @override
  String get androidAuthFailed => 'Android 本地音乐授权失败';

  @override
  String get matchingOnline => '正在匹配在线歌曲（刮削）…';

  @override
  String get scanFailed => '扫描失败';

  @override
  String get noLocalSources => '还没有配置本地音乐来源';

  @override
  String get rescanning => '正在重新扫描本地音乐来源…';

  @override
  String get rescanFailed => '重新扫描失败';

  @override
  String get noWritableSongs => '没有可写入的本地歌曲';

  @override
  String get writingTags => '正在尝试写回原文件标签…';

  @override
  String get noTagsToWrite => '没有可写回的刮削标签';

  @override
  String get writeTagsFailed => '写回标签失败';

  @override
  String get folderRemoved => '已移除文件夹';

  @override
  String get downloadsTitle => '下载管理';

  @override
  String get deleteFinishedDownloads => '删除已完成下载';

  @override
  String get clearFailedTasks => '清理失败任务';

  @override
  String get noDownloadTasks => '暂无下载任务';

  @override
  String get noTasks => '暂无任务';

  @override
  String get downloadSpeed => '下载速度';

  @override
  String get downloaded => '已下载';

  @override
  String get linkExpired => '链接失效，下载失败';

  @override
  String get deleteFiles => '删除文件';

  @override
  String get clearFailedAction => '清理';

  @override
  String get listeningStatsEmpty => '暂无播放数据';

  @override
  String get listeningStatsEmptyHint => '多听几首歌，这里会生成你的听歌报告';

  @override
  String get playCount => '播放次数';

  @override
  String get listenTime => '听歌时长';

  @override
  String get activeDays => '活跃天数';

  @override
  String get trackCount => '单曲数';

  @override
  String get dailyPlays => '每日播放';

  @override
  String get songs => '歌曲';

  @override
  String get artists => '艺术家';

  @override
  String get albums => '专辑';

  @override
  String get noData => '暂无数据';

  @override
  String get loadFailed => '加载失败';

  @override
  String get noDuplicateFavorites => '收藏列表没有重复歌曲';

  @override
  String get selectRecommended => '按推荐勾选';

  @override
  String get working => '处理中…';

  @override
  String get removeSelected => '移除已选';

  @override
  String get removeGroupSelected => '移除本组已选';

  @override
  String get keepSuggested => '推荐保留';

  @override
  String get hasLyricsMark => ' · 有歌词';

  @override
  String get addedToPlaylist => '已添加到歌单';

  @override
  String get playlistCreatedAndAdded => '已创建歌单并添加';

  @override
  String get collapseNewPlaylist => '收起新建歌单';

  @override
  String get newPlaylistName => '新歌单名称';

  @override
  String get basedOnFavorites => '根据你喜欢的音乐推荐';

  @override
  String get noRecommendations => '还没有推荐';

  @override
  String get recommendationsNeedFavorites => '“收藏列表”满 100 首后，将随机取样推荐 30 首歌曲';

  @override
  String get playlistEmpty => '歌单为空';

  @override
  String get playlistEmptyNas => '歌单是空的';

  @override
  String get connectionSettings => '连接设置';

  @override
  String get scraping => '正在刮削';

  @override
  String get scrapeArtworkLyrics => '刮削封面和歌词';

  @override
  String get goConnect => '去连接';

  @override
  String get noOnlineMatch => '没有匹配到在线封面或歌词';

  @override
  String get welcome => '欢迎使用 Koyze';

  @override
  String get welcomeBody => '登录云端账号后，可跨设备同步收藏、歌单、设置和自定义音源。';

  @override
  String get serverAddress => '服务器地址';

  @override
  String get syncUsernameHint => '同步账号用户名';

  @override
  String get syncPasswordHint => '同步账号密码';

  @override
  String get registerAndSync => '注册并开始同步';

  @override
  String get loginAndSync => '登录并开始同步';

  @override
  String get backToLogin => '已有账号，返回登录';

  @override
  String get needAccount => '还没有账号？注册一个';

  @override
  String get skipStep => '跳过这一步';

  @override
  String get skipStepHint => '跳过后不会影响本地播放；你之后可以随时在“设置 → 同步”添加账号。';

  @override
  String get fillServerLogin => '请填写服务器、用户名和密码';

  @override
  String get loginFailed => '登录失败';

  @override
  String get syncTitle => '同步 / 云端账号';

  @override
  String get syncAccount => '同步账号';

  @override
  String get workersServer => 'Workers 服务器';

  @override
  String get workersUnset => '未配置（例如 https://xxx.workers.dev）';

  @override
  String get notLoggedIn => '未登录';

  @override
  String get loginToSync => '登录后可同步云端歌单';

  @override
  String get syncing => '同步中…';

  @override
  String get syncExplainer =>
      '说明：在此配置并登录 workers 后端。搜歌/播放仍在本机完成，云端负责账号、歌单、设置与音源。';

  @override
  String get eventSync => '事件同步';

  @override
  String get syncNow => '立即同步';

  @override
  String get mergingEvents => '正在安全合并本地与云端事件…';

  @override
  String get syncDoesNotOverwrite => '只上传本地变更并拉取其他设备变更，不覆盖数据';

  @override
  String get offlineUntilNetwork => '数据保存在本地，网络恢复后自动同步';

  @override
  String get logOut => '退出登录';

  @override
  String get logOutHint => '退出后保留收藏、歌单、评分、播放历史、下载与缓存，仅清除登录状态';

  @override
  String get loggedOut => '已退出登录';

  @override
  String get userAdmin => '用户管理（管理员）';

  @override
  String get userAdminHint => '创建 / 删除 / 重置密码';

  @override
  String get workersAddress => 'Workers 地址';

  @override
  String get serverReachable => '服务器可达';

  @override
  String get savedHealthFailed => '保存成功，但健康检查失败（部署后重试）';

  @override
  String get httpsRequired => '服务器地址必须使用 HTTPS';

  @override
  String get enterServerFirst => '请先填写服务器地址';

  @override
  String get loginSucceeded => '登录成功';

  @override
  String get failed => '失败';

  @override
  String get syncFinished => '同步完成';

  @override
  String get userList => '用户列表';

  @override
  String get newUser => '新建用户';

  @override
  String get userCreated => '已创建用户';

  @override
  String get customSourcesTitle => '自定义源';

  @override
  String get importLocalScript => '导入本地脚本';

  @override
  String get importFromLink => '通过链接导入';

  @override
  String get addManually => '手动添加';

  @override
  String get pasteScript => '粘贴脚本';

  @override
  String get noCustomSources => '暂无自定义源';

  @override
  String get addCustomSourceHint =>
      'Koyze 不内置任何音源。请点击右上角 + 导入并启用音源，否则在线歌曲无法播放。';

  @override
  String get importScriptOk => '导入脚本成功';

  @override
  String get importScriptBad => '导入失败，脚本格式错误';

  @override
  String get addCustomSource => '添加自定义源';

  @override
  String get sourceName => '源名称';

  @override
  String get author => '作者';

  @override
  String get script => '脚本';

  @override
  String get editCustomSource => '编辑自定义源';

  @override
  String get httpsLinkRequired => '请输入有效的 HTTPS 链接';

  @override
  String get importOk => '导入成功';

  @override
  String get importLinkBad => '导入失败，请检查链接或脚本格式';

  @override
  String get directDownloadHint => '请输入脚本文件的直接下载链接';

  @override
  String get clipboardEmpty => '剪切板中没有链接';

  @override
  String get clipboard => '剪切板';

  @override
  String get importCustomSource => '导入自定义源';

  @override
  String get lxScriptHint => '支持 LX Music 格式脚本';

  @override
  String get pasteScriptHint => '粘贴 LX Music 脚本或 JSON 配置...';

  @override
  String get importFormatBad => '导入失败，请检查脚本格式';

  @override
  String get exportCustomSource => '导出自定义源';

  @override
  String get deleteCustomSource => '删除自定义源';

  @override
  String get logCopied => '日志已复制';

  @override
  String get noLog => '暂无日志';

  @override
  String get copyLog => '复制日志';

  @override
  String get enterUsername => '请输入用户名';

  @override
  String get enterPassword => '请输入密码';

  @override
  String get enterPasswordOrToken => '请输入密码或 X-Plex-Token';

  @override
  String get connectFailed => '连接失败';

  @override
  String get nasServerTitle => 'NAS 音乐服务器';

  @override
  String get usernameOptional => '用户名（可留空）';

  @override
  String get plexAccountHint => 'plex.tv 账号，留空则使用 Token';

  @override
  String get serverLoginName => '服务器登录名';

  @override
  String get passwordOrToken => '密码 / Token';

  @override
  String get passwordSaved => '已保存，重新连接时再输入';

  @override
  String get passwordOrPlexToken => '密码或 X-Plex-Token';

  @override
  String get serverPassword => '服务器密码';

  @override
  String get webDavRootPath => '根目录';

  @override
  String get webDavRootPathHint => '/music';

  @override
  String get webDavAuthMethod => '认证方式';

  @override
  String get webDavBasicAuth => '用户名 / 密码';

  @override
  String get webDavBearerAuth => 'Bearer Token';

  @override
  String get webDavTokenHint => '粘贴访问 Token';

  @override
  String get webDavRootPathInvalid => '根目录只需填写路径，例如 /music';

  @override
  String get webDavScanFailed => 'WebDAV 曲库扫描失败';

  @override
  String get showPassword => '显示密码';

  @override
  String get hidePassword => '隐藏密码';

  @override
  String get legacyAuth => '旧版鉴权';

  @override
  String get legacyAuthHint => '仅当 token 鉴权失败时开启，密码会以明文参数发送';

  @override
  String get reconnect => '重新连接';

  @override
  String get disconnect => '断开连接';

  @override
  String get diagnosticsTitle => '实时诊断日志';

  @override
  String get minimize => '最小化';

  @override
  String get copyAll => '复制全部';

  @override
  String get closeDiagnostics => '关闭诊断日志';

  @override
  String get clearMemoryLog => '清空内存日志';

  @override
  String get diagnosticsRecording => '记录中';

  @override
  String get diagnosticsFilterAll => '全部';

  @override
  String get diagnosticsFilterWarnings => '警告';

  @override
  String get diagnosticsFilterErrors => '错误';

  @override
  String get diagnosticsJumpLatest => '回到最新';

  @override
  String get diagnosticsEmptyHint => '面板已打开，有新的运行事件会实时出现在这里。';

  @override
  String get diagnosticsHint => '只在打开这个面板时记录；仅存于内存，重启后清空。';

  @override
  String get stoppedAfterRepeatedFailures => '连续 5 首歌曲播放失败，已停止自动播放';

  @override
  String get autoplayNextFailed => '自动播放下一首失败，请返回应用重试';

  @override
  String get reloadingSong => '播放歌曲失败，正在重新加载';

  @override
  String get tryingNextSong => '播放歌曲失败，正在尝试下一首';

  @override
  String backupExported(String path) {
    return '备份已导出到 $path';
  }

  @override
  String backupFailed(String error) {
    return '备份失败: $error';
  }

  @override
  String restoreFailed(String error) {
    return '恢复失败: $error';
  }

  @override
  String cacheClearedRetained(int count) {
    return '缓存已清除，$count 个正在使用的歌曲缓存已安全保留';
  }

  @override
  String clearFailed(String error) {
    return '清除失败: $error';
  }

  @override
  String minutes(int count) {
    return '$count 分钟';
  }

  @override
  String stopsInMinutes(int count) {
    return '$count 分钟后停止播放';
  }

  @override
  String playAction(String mode, String target) {
    return '$mode$target';
  }

  @override
  String recommendedSongs(int count) {
    return '为你推荐 $count 首歌曲';
  }

  @override
  String songCount(int count) {
    return '$count 首歌曲';
  }

  @override
  String loadingHost(String host) {
    return '正在加载 $host';
  }

  @override
  String actionFailed(String action, String error) {
    return '$action失败: $error';
  }

  @override
  String failedWith(String label, String error) {
    return '$label: $error';
  }

  @override
  String nowPlayingNamed(String name) {
    return '正在播放 $name';
  }

  @override
  String playNamed(String name) {
    return '播放 $name';
  }

  @override
  String chartCount(int count) {
    return '$count 个榜单';
  }

  @override
  String hiddenUntil(String name) {
    return '已隐藏，勾选「$name」后显示';
  }

  @override
  String songsHeader(int count) {
    return '歌曲 ($count)';
  }

  @override
  String playlistsHeader(int count) {
    return '歌单 ($count)';
  }

  @override
  String importProgress(int loaded, int total) {
    return '$loaded/$total 首';
  }

  @override
  String confirmImport(int count) {
    return '共 $count 首，确认导入到本地歌单？';
  }

  @override
  String importedFrom(String source) {
    return '导入自$source';
  }

  @override
  String importedResult(String name, int count) {
    return '已导入「$name」$count 首';
  }

  @override
  String parsingProgress(String progress) {
    return '正在解析 $progress';
  }

  @override
  String addedToFavorites(int count) {
    return '已添加 $count 首到收藏列表';
  }

  @override
  String searchFailed(String error) {
    return '搜索出错: $error';
  }

  @override
  String searchEmptyTitle(String query) {
    return '没有找到「$query」';
  }

  @override
  String localArtist(String singer) {
    return '$singer · 本地';
  }

  @override
  String queueTitle(int count) {
    return '播放列表 ($count)';
  }

  @override
  String selectedCount(int count) {
    return '已选 $count 首';
  }

  @override
  String playlistTitleCount(String name, int count) {
    return '$name（$count首）';
  }

  @override
  String favoritedSongs(int count) {
    return '已收藏 $count 首歌曲';
  }

  @override
  String queuedDownloads(int count) {
    return '已添加 $count 首到下载队列';
  }

  @override
  String unfavoritedSongs(int count) {
    return '已取消收藏 $count 首歌曲';
  }

  @override
  String clearFavoritesBody(int count) {
    return '将从收藏列表移除 $count 首歌曲，此操作不可撤销，但不会删除本地或歌单中的原歌曲。';
  }

  @override
  String deletePlaylistConfirm(String name) {
    return '确定删除「$name」？';
  }

  @override
  String pagePosition(int page, int count) {
    return '第 $page / $count 页';
  }

  @override
  String startupFailedHint(String error) {
    return '请重新打开应用；如果问题持续，请查看设置中的诊断日志。\\n$error';
  }

  @override
  String bandsReady(int count, String range) {
    return '已读取设备频段：$count 段（$range）';
  }

  @override
  String localSongCount(int count) {
    return '已收录 $count 首本地歌曲\\n前往「我的歌单 > 本地音乐」播放';
  }

  @override
  String mediaStoreHint(int count) {
    return 'MediaStore 可重扫，已配置 $count 个目录';
  }

  @override
  String downloadFolder(String path) {
    return '下载目录 · 自动收录\\n$path';
  }

  @override
  String importingCount(int done, int total) {
    return 'SAF 正在导入 $done / $total';
  }

  @override
  String mediaStoreImporting(int done, int total) {
    return 'MediaStore 正在导入 $done / $total';
  }

  @override
  String allFilesScanning(int done, int total) {
    return '全部文件访问正在扫描 $done / $total';
  }

  @override
  String scanningPath(String path) {
    return '正在扫描 $path …';
  }

  @override
  String readingMetadata(int done, int total) {
    return '正在解析元数据 $done / $total';
  }

  @override
  String scrapingCount(int done, int total) {
    return '正在刮削 $done / $total';
  }

  @override
  String localUpdated(int count) {
    return '本地音乐已更新（$count 首）';
  }

  @override
  String writingTagsCount(int done, int total) {
    return '正在写回原文件标签 $done / $total';
  }

  @override
  String tagsWritten(int written, int attempted) {
    return '标签写回完成：成功 $written / $attempted';
  }

  @override
  String activeHeader(int count) {
    return '进行中 ($count)';
  }

  @override
  String finishedHeader(int count) {
    return '已完成 ($count)';
  }

  @override
  String downloadingPercent(String percent) {
    return '下载中 $percent%';
  }

  @override
  String pausedPercent(String singer, String percent) {
    return '$singer · 已暂停 $percent%';
  }

  @override
  String deleteFinishedBody(int count) {
    return '确定要删除 $count 个已完成记录及其音频文件吗？此操作不可撤销。';
  }

  @override
  String clearFailedBody(int count) {
    return '确定要删除 $count 个失败任务及其残留文件吗？';
  }

  @override
  String dailyPeak(int days, int maxCount) {
    return '$days 天 · 峰值 $maxCount 次';
  }

  @override
  String statSubtitle(String subtitle, int count) {
    return '$subtitle · $count次';
  }

  @override
  String duplicateGroup(String artist, int count) {
    return '$artist · $count 个版本 · 勾选要移除的';
  }

  @override
  String removedDuplicates(int count) {
    return '已移除 $count 处重复项';
  }

  @override
  String playlistSongCount(int count) {
    return '$count 首';
  }

  @override
  String recommendUpdated(int count) {
    return '推荐 $count 首 · 持续更新';
  }

  @override
  String scrapingProgress(int done, int total) {
    return '正在刮削 $done / $total';
  }

  @override
  String notConnected(String name) {
    return '尚未连接 $name';
  }

  @override
  String connectedHost(String host) {
    return '当前已连接 $host';
  }

  @override
  String matchedSongs(int matched, int total) {
    return '已为 $matched / $total 首匹配封面和歌词';
  }

  @override
  String scrapeFailed(String error) {
    return '刮削失败: $error';
  }

  @override
  String nasPlaylistTitle(String name) {
    return '$name 歌单';
  }

  @override
  String loggedInAs(String name) {
    return '已登录：$name';
  }

  @override
  String roleLine(String role) {
    return '角色：$role';
  }

  @override
  String deviceLine(String id) {
    return '设备：$id';
  }

  @override
  String timeLine(String time) {
    return '时间：$time';
  }

  @override
  String syncFailed(String error) {
    return '同步失败：$error';
  }

  @override
  String adminUser(String id) {
    return '管理员 · id=$id';
  }

  @override
  String normalUser(String id) {
    return '普通用户 · id=$id';
  }

  @override
  String deleteUser(String name) {
    return '删除 $name';
  }

  @override
  String deletedUser(String name) {
    return '已删除 $name';
  }

  @override
  String usersLoadFailed(String error) {
    return '加载用户失败: $error';
  }

  @override
  String sourceInitFailed(String name) {
    return '$name 初始化失败，请检查脚本';
  }

  @override
  String importScriptFailed(String reason) {
    return '脚本导入失败：$reason';
  }

  @override
  String readFileFailed(String error) {
    return '读取文件失败: $error';
  }

  @override
  String deleteSourceConfirm(String name) {
    return '确定要删除“$name”吗？';
  }

  @override
  String sourceLogTitle(String name) {
    return '$name 日志';
  }

  @override
  String disconnected(String name) {
    return '已断开 $name';
  }

  @override
  String diagnosticsCount(int count) {
    return '诊断 $count';
  }

  @override
  String playingQuoted(String name) {
    return '播放“$name”';
  }

  @override
  String unresolvedUrl(String title) {
    return '无法解析歌曲 “$title” 的播放地址（源无效地址或本地缓存失败，已尝试降级音质）';
  }

  @override
  String playSongFailed(String title, String error) {
    return '播放歌曲 “$title” 失败: $error';
  }

  @override
  String get quickTitle_theme => '切换主题';

  @override
  String get quickTitle_search => '搜索歌曲';

  @override
  String get quickTitle_playlists => '歌单管理';

  @override
  String get quickTitle_settings => '应用设置';

  @override
  String get quickTitle_sync => '云同步';

  @override
  String get quickTitle_local_scan => '本地扫描';

  @override
  String get quickTitle_leaderboard_settings => '榜单设置';

  @override
  String get quickSubtitle_recommend => '根据历史推荐';

  @override
  String get quickSubtitle_local => '设备上的歌曲';

  @override
  String get quickSubtitle_downloads => '任务与进度';

  @override
  String get quickSubtitle_stats => '周月年排行';

  @override
  String get quickSubtitle_sleep_timer => '定时停止播放';

  @override
  String get quickSubtitle_theme => '深色 / 浅色';

  @override
  String get quickSubtitle_favorites => '查看收藏歌曲';

  @override
  String get quickSubtitle_recent => '继续最近听过的歌';

  @override
  String get quickSubtitle_leaderboard => '热门歌曲排行';

  @override
  String get quickSubtitle_search => '快速查找音乐';

  @override
  String get quickSubtitle_playlists => '整理自定义歌单';

  @override
  String get quickSubtitle_settings => '音质、下载与外观';

  @override
  String get quickSubtitle_custom_source => '管理音乐数据源';

  @override
  String get quickSubtitle_sync => '同步收藏和歌单';

  @override
  String get quickSubtitle_local_scan => '扫描设备音乐';

  @override
  String get quickSubtitle_leaderboard_settings => '调整榜单显示内容';

  @override
  String get quickSubtitle_audio_quality => '选择默认播放音质';

  @override
  String get quickSubtitle_download_quality => '选择默认下载音质';

  @override
  String get quickSubtitle_default_search => '调整搜索默认来源';

  @override
  String get quickSubtitle_backup => '导出歌单和设置';

  @override
  String get quickSubtitle_restore => '从备份文件恢复';

  @override
  String get quickSubtitle_clear_cache => '释放播放与封面缓存';

  @override
  String get quickSubtitle_diagnostic_log => '查看实时运行日志';

  @override
  String get platformName_qq => 'QQ音乐';

  @override
  String get platformName_tx => 'QQ音乐';

  @override
  String get platformName_kw => '酷我音乐';

  @override
  String get platformName_wy => '网易云';

  @override
  String get platformName_kg => '酷狗音乐';

  @override
  String get qualityText_flac24bit => '臻品母带';

  @override
  String get qualityText_flac => '无损';

  @override
  String get platformText_tx => 'QQ音乐';

  @override
  String get platformText_kw => '酷我音乐';

  @override
  String get platformText_wy => '网易云音乐';

  @override
  String get platformText_kg => '酷狗音乐';

  @override
  String get platformText_mg => '咪咕音乐';

  @override
  String get platformText_audiostation => '未知';

  @override
  String get presetName_flat => '原声';

  @override
  String get presetName_pop => '流行';

  @override
  String get presetName_rock => '摇滚';

  @override
  String get presetName_jazz => '爵士';

  @override
  String get presetName_classical => '古典';

  @override
  String get presetName_electronic => '电子';

  @override
  String get presetName_folk => '民谣';

  @override
  String get presetName_vocal => '人声';

  @override
  String get presetName_bass => '低音增强';

  @override
  String get presetName_treble => '高音增强';

  @override
  String get connectedType_default => '已连接 \$type';

  @override
  String get connectedType_default_2 => '已连接 \$type \$version';

  @override
  String get currentConnection_default => '当前：\$title · \$host';

  @override
  String get currentConnection_default_2 => '当前：\$title · \$host · \$username';

  @override
  String get playlistLinkExample =>
      '示例：https://y.qq.com/n/ryqq/playlist/123\n酷狗：https://www.kugou.com/yy/special/single/547134.html\n或直接输入数字 ID';

  @override
  String get sourceCheckTitle => '音源检测';

  @override
  String get sourceCheckStart => '开始检测';

  @override
  String get sourceCheckNeverRun => '未检测';

  @override
  String get sourceCheckTesting => '检测中…';

  @override
  String get sourceCheckRerun => '重新检测';

  @override
  String sourceCheckSummary(int ok, int total, String time) {
    return '$ok/$total 个平台可用 · $time';
  }

  @override
  String get aiSettingsTitle => 'AI 设置';

  @override
  String get aiSettingsIntro =>
      '兼容任何 OpenAI 格式的接口。密钥存在系统安全存储里，只会在请求时发给你填的这个地址。';

  @override
  String get aiBaseUrl => 'API 地址';

  @override
  String get aiBaseUrlHint => 'https://api.deepseek.com/v1';

  @override
  String get aiModel => '模型';

  @override
  String get aiModelHint => 'deepseek-chat';

  @override
  String get aiApiKey => 'API Key';

  @override
  String get aiApiKeyHint => 'sk-...';

  @override
  String get aiApiKeyStoredHint => '已保存，留空保持不变';

  @override
  String get aiTestConnection => '测试连接';

  @override
  String get aiTesting => '测试中…';

  @override
  String get aiTestOk => '连接正常';

  @override
  String get aiTestingVoice => '正在测语音…';

  @override
  String get aiConfigSaved => 'AI 设置已保存';

  @override
  String get aiConfigInvalid => '请先填写有效的 http(s) 地址、模型和密钥';

  @override
  String get aiErrorNotConfigured => '还没有配置 AI';

  @override
  String get aiErrorUnauthorized => '密钥被拒绝，请检查 API Key';

  @override
  String get aiErrorNotFound => '地址或模型不存在';

  @override
  String get aiErrorRateLimited => '请求过于频繁，稍后再试';

  @override
  String get aiErrorServer => 'AI 服务返回错误';

  @override
  String get aiErrorTimeout => '请求超时';

  @override
  String get aiErrorNetwork => '网络不可用';

  @override
  String get aiErrorEmpty => '模型没有返回内容';

  @override
  String get aiErrorBadResponse => '返回内容无法解析';

  @override
  String get aiErrorContextTooLong =>
      '超出模型的上下文长度。先清空对话再试；如果第一句话就这样，说明工具清单本身就装不下——在设置里关掉「允许 AI 直接操作应用」，或换一个上下文更大的模型';

  @override
  String get aiErrorToolsUnsupported => '这个接口不支持工具调用。可以在设置里关掉「允许 AI 直接操作应用」再试';

  @override
  String get aiErrorRejected => '接口拒绝了这次请求';

  @override
  String get aiErrorToolLoop => '连着操作了太多步还没得出结论。把要求说得更具体一点再试一次';

  @override
  String get aiErrorGatewayTimeout =>
      '接口网关超时，模型没在限定时间内回话。已经自动重试过一次，稍后再试；连着几次都这样，就在设置里关掉「允许 AI 直接操作应用」——工具清单越小，模型回得越快';

  @override
  String get aiNotConfigured => '请先在「AI 设置」里填写地址、密钥和模型';

  @override
  String get aiToolsTitle => '工具调用';

  @override
  String get aiToolsSubtitle => '让模型自己查曲库、歌单、音源和下载，而不是凭记忆编歌名';

  @override
  String get aiActionsTitle => '允许 AI 直接操作应用';

  @override
  String get aiActionsSubtitle => '关闭后只保留查询类操作，动手的事交回给你';

  @override
  String aiToolRunning(String tool) {
    return '正在调用 $tool…';
  }

  @override
  String get aiToolSearchLibrary => '搜索曲库';

  @override
  String get aiToolListPlaylists => '读取歌单';

  @override
  String get aiToolGetPlaylist => '查看歌单';

  @override
  String get aiToolSourceStatus => '检查音源';

  @override
  String get aiToolCreatePlaylist => '创建歌单';

  @override
  String get aiAssistantTitle => 'AI 助手';

  @override
  String get aiAssistantSubtitle => '一句话让它播歌、排队、建歌单、改设置';

  @override
  String get aiAssistantPlaceholder => '说你想听的、想做的…';

  @override
  String get aiAssistantEmptyTitle => '直接说要做什么';

  @override
  String get aiAssistantEmptyHint => '助手在后台调用应用自己的接口完成操作，你不用自己去找按钮。';

  @override
  String get aiAssistantExample1 => '播放周杰伦的晴天';

  @override
  String get aiAssistantExample2 => '把这首歌收藏，再下到本地';

  @override
  String get aiAssistantExample3 => '建个深夜写代码的歌单，20 首安静的曲子';

  @override
  String get aiAssistantExample4 => '我今年听得最多的是哪几首？';

  @override
  String get aiAssistantExample5 => '低音再重一点，人声清楚些';

  @override
  String get aiAssistantExample6 => '把这首的歌手改成周杰伦';

  @override
  String get aiAssistantThinking => '思考中…';

  @override
  String aiAssistantWorking(String tool) {
    return '正在执行 $tool…';
  }

  @override
  String get aiAssistantNewChat => '新对话';

  @override
  String get aiAssistantReadOnly => '执行权限已关闭，助手只会给建议';

  @override
  String aiAssistantToolCount(int count) {
    return '$count 次';
  }

  @override
  String get aiCategoryLibrary => '查询曲库';

  @override
  String get aiCategoryPlayback => '播放控制';

  @override
  String get aiCategoryPlaylist => '歌单';

  @override
  String get aiCategoryDownload => '下载';

  @override
  String get aiCategorySource => '音源';

  @override
  String get aiCategorySettings => '设置';

  @override
  String get carMode => '车机模式';

  @override
  String get carModeSubtitle => '连上车机时使用宽屏布局';

  @override
  String get carModeAuto => '跟随 HiCar';

  @override
  String get carModeAutoSubtitle => '连上车机时自动切换';

  @override
  String get carModeAlways => '始终开启';

  @override
  String get carModeAlwaysSubtitle => '方便在手机上预览宽屏效果';

  @override
  String get carModeOff => '关闭';

  @override
  String get carModeStatusConnected => '已连接 HiCar';

  @override
  String get carModeStatusDisconnected => '未连接车机';

  @override
  String get carModeStatusUnsupported => '此设备不支持 Car Kit';

  @override
  String get settingsSearch => '搜索设置';

  @override
  String get settingsSearchHint => '搜索设置项，试试「音质」「深色模式」';

  @override
  String get settingsSearchEmpty => '没有匹配的设置项';

  @override
  String get aiSectionTitle => 'AI';

  @override
  String get aiSettingsSubtitle => '接口地址、密钥与模型';

  @override
  String get aiSchedulesTitle => 'AI 定时任务';

  @override
  String get aiSchedulesSubtitle => '到点让助手自己动手';

  @override
  String get aiSchedulesIntro => '到点自动执行你写的那句话。应用运行时触发；关掉期间错过的，6 小时内会补跑一次。';

  @override
  String get aiSchedulesEmpty => '还没有定时任务';

  @override
  String get aiSchedulesEmptyHint => '比如每天早上挑几首歌建成歌单，或者每周日把上周常听的整理成一份回顾。';

  @override
  String get aiSchedulesNew => '新建任务';

  @override
  String get aiSchedulesEdit => '编辑任务';

  @override
  String get aiScheduleName => '任务名称';

  @override
  String get aiScheduleNameHint => '早安推荐';

  @override
  String get aiSchedulePrompt => '到点要做什么';

  @override
  String get aiSchedulePromptHint => '挑 8 首适合早上听的歌，建成歌单「早安」';

  @override
  String get aiScheduleTime => '执行时间';

  @override
  String get aiScheduleRepeat => '重复';

  @override
  String get aiScheduleDaily => '每天';

  @override
  String get aiScheduleWeekdays => '工作日';

  @override
  String get aiScheduleWeekly => '每周';

  @override
  String get aiScheduleDelete => '删除任务';

  @override
  String aiScheduleDeleteConfirm(String name) {
    return '删除后不再执行，确定删掉「$name」？';
  }

  @override
  String get aiScheduleDeleted => '已删除';

  @override
  String get aiScheduleSaved => '定时任务已保存';

  @override
  String get aiScheduleNameRequired => '先给它起个名字';

  @override
  String get aiSchedulePromptRequired => '写一句到点要做的事';

  @override
  String get aiScheduleRunNow => '立即执行';

  @override
  String get aiScheduleRunning => '执行中…';

  @override
  String get aiScheduleNeverRun => '还没执行过';

  @override
  String aiScheduleLastRun(String time) {
    return '上次执行 $time';
  }

  @override
  String aiScheduleNextRun(String time) {
    return '下次 $time';
  }

  @override
  String get aiSchedulePaused => '已暂停';

  @override
  String aiScheduleRunFailed(String reason) {
    return '执行失败：$reason';
  }

  @override
  String aiScheduleRunDone(String name) {
    return '「$name」执行完成';
  }

  @override
  String aiScheduleRunFailedToast(String name) {
    return '「$name」执行失败';
  }

  @override
  String aiSchedulePill(String name) {
    return '定时 · $name';
  }

  @override
  String get aiDayToday => '今天';

  @override
  String get aiDayTomorrow => '明天';

  @override
  String get aiWeekdayMon => '周一';

  @override
  String get aiWeekdayTue => '周二';

  @override
  String get aiWeekdayWed => '周三';

  @override
  String get aiWeekdayThu => '周四';

  @override
  String get aiWeekdayFri => '周五';

  @override
  String get aiWeekdaySat => '周六';

  @override
  String get aiWeekdaySun => '周日';

  @override
  String get aiCategoryRecommendation => '猜你喜欢';

  @override
  String get recommendTunedByAi => 'AI 调整过这份推荐';

  @override
  String get recommendTuningReset => '重置';

  @override
  String get recommendTuningCleared => '已恢复默认推荐';

  @override
  String get playbackSpeed => '播放速度';

  @override
  String get untilTrackEnd => '播完当前歌曲';

  @override
  String get untilTrackEndNote => '播完这首就暂停';

  @override
  String get fadeOutBeforeStop => '结束前渐弱';

  @override
  String get fadeOutBeforeStopHint => '最后 10 秒慢慢变小，不会突然静音';

  @override
  String get queueEditTitle => '编辑播放队列';

  @override
  String get playNext => '下一首播放';

  @override
  String get removeFromQueue => '从播放队列移除';

  @override
  String get scanRules => '扫描规则';

  @override
  String get scanRulesSubtitle => '过滤时长、体积与重复曲目';

  @override
  String get scanRulesHint => '只影响之后的扫描，不会删除已入库的歌';

  @override
  String get scanRuleNoLimit => '不限';

  @override
  String get scanRuleMinDuration => '最小时长';

  @override
  String get scanRuleMinSize => '最小体积';

  @override
  String get scanRuleSkipDuplicates => '跳过重复曲目';

  @override
  String get scanRuleSkipDuplicatesHint => '同标题、歌手、时长只保留体积最大的一份';

  @override
  String get scanRuleExcludedFolders => '排除的文件夹';

  @override
  String get scanRuleAddFolder => '添加排除文件夹';

  @override
  String get scanRuleFolderHint => '输入完整路径';

  @override
  String get scanRuleNoExcludedFolders => '还没有排除任何文件夹';

  @override
  String get scanRuleRescanHint => '改动会在下次扫描时生效';

  @override
  String get savingNow => '正在保存…';

  @override
  String secondsShort(int n) {
    return '$n 秒';
  }

  @override
  String get resetSettings => '恢复默认设置';

  @override
  String get resetSettingsSubtitle => '清空偏好项，保留账号与本地库';

  @override
  String get resetSettingsConfirm => '将把所有偏好设置恢复为默认值。账号、NAS、歌单、播放历史与本地库索引会保留。';

  @override
  String get resetSettingsAction => '恢复默认';

  @override
  String resetSettingsDone(int count) {
    return '已恢复 $count 项设置';
  }

  @override
  String resetSettingsFailed(String error) {
    return '恢复失败：$error';
  }

  @override
  String get autoEqImport => '导入 AutoEQ';

  @override
  String autoEqImported(String name) {
    return '已导入 $name';
  }

  @override
  String get autoEqImportFailed => '这个文件里没有可识别的 AutoEQ 曲线';

  @override
  String get replayGain => '响度均衡';

  @override
  String get replayGainSubtitle => '按 ReplayGain 标签拉平不同专辑的音量';

  @override
  String get lockScreenLyric => '锁屏歌词';

  @override
  String get lockScreenLyricSubtitle => '在锁屏与通知栏显示当前歌词行';

  @override
  String get lyricShare => '分享歌词卡片';

  @override
  String get lyricShareNoLine => '这首歌还没有歌词';

  @override
  String get lyricShareSave => '保存图片';

  @override
  String get lyricShareSaved => '歌词卡片已保存';

  @override
  String lyricShareFailed(String error) {
    return '保存失败：$error';
  }

  @override
  String get smartPlaylists => '智能歌单';

  @override
  String get smartPlaylistsSubtitle => '按规则自动整理，不需要手动维护';

  @override
  String get smartRecentlyAdded => '最近添加';

  @override
  String get smartRecentlyAddedHint => '最新入库的歌曲';

  @override
  String get smartMostPlayed => '最常播放';

  @override
  String get smartMostPlayedHint => '按播放次数排序';

  @override
  String get smartNeverPlayed => '从未播放';

  @override
  String get smartNeverPlayedHint => '入库后一直没听过的歌曲';

  @override
  String get smartFavoritesHint => '我喜欢的音乐';

  @override
  String get smartEmpty => '这个规则暂时没有歌曲';

  @override
  String smartSongCount(int n) {
    return '$n 首';
  }

  @override
  String get radio => '网络电台';

  @override
  String get radioSubtitle => 'Radio Browser 上的公开电台';

  @override
  String get radioSearchHint => '搜索电台或风格';

  @override
  String get radioPopular => '热门';

  @override
  String get radioLive => '直播';

  @override
  String get radioEmpty => '没有找到电台';

  @override
  String get radioFailed => '电台列表加载失败';

  @override
  String get precacheRecent => '常听预缓存';

  @override
  String get precacheRecentSubtitle => '在 Wi-Fi 下提前取回常听歌曲，点开即播';

  @override
  String get precacheCount => '预缓存数量';

  @override
  String precacheCountValue(int n) {
    return '$n 首';
  }

  @override
  String get add => '添加';
}
