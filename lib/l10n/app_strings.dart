import 'package:flutter/widgets.dart';

import '../features/settings/presentation/settings_provider.dart';
import 'generated/app_localizations.dart';

/// User-facing copy for the shell and settings.
///
/// ## Why this class still exists
///
/// Every string used to be an inline `en ? 'English' : '中文'` ternary in
/// this file — 555 of them, packed into 550+ getters. That made the copy
/// impossible to audit, impossible to hand to a translator, and impossible
/// to extend with a third language.
///
/// The strings now live in `lib/l10n/app_en.arb` and `app_zh.arb` and are
/// compiled into [AppLocalizations] by `flutter gen-l10n`. This class is a
/// thin, strongly-typed facade over that generated class so the ~700
/// existing `S.of(context).foo` call sites did not have to change.
///
/// Methods whose wording depends on runtime branching (switch over enums or
/// ids, optional suffixes) are still implemented here, because ARB cannot
/// express that logic. Every string they emit comes from the ARB files.
///
/// See `docs/adr/0007-i18n-arb-migration.md`.
class S {
  const S(this._l10n, this.locale);

  final AppLocalizations _l10n;
  final Locale locale;

  bool get en => locale.languageCode == 'en';

  static S of(BuildContext context) {
    // `AppLocalizations.of` hard-casts with `!` when no delegate is
    // registered — which happens in widget tests that build a bare
    // MaterialApp, and in any embedding that forgets the delegate. Look the
    // value up through `Localizations.of` so a missing delegate degrades to
    // locale-derived copy instead of crashing the whole subtree.
    final locale = Localizations.localeOf(context);
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        lookupAppLocalizations(locale);
    return S(l10n, locale);
  }

  /// For code paths without a [BuildContext] (isolates, error handlers).
  /// Mirrors the zh default of `MaterialApp.localeResolutionCallback`.
  static S fromLocale(Locale locale) =>
      S(lookupAppLocalizations(locale), locale);

  // ---- ARB-backed getters -------------------------------------------
  String get home => _l10n.home;
  String get charts => _l10n.charts;
  String get playlists => _l10n.playlists;
  String get settings => _l10n.settings;
  String get sync => _l10n.sync;
  String get cloudAccount => _l10n.cloudAccount;
  String get cloudAccountSubtitle => _l10n.cloudAccountSubtitle;
  String get advanced => _l10n.advanced;
  String get localLibrary => _l10n.localLibrary;
  String get localLibrarySubtitle => _l10n.localLibrarySubtitle;
  String get customSources => _l10n.customSources;
  String get customSourcesSubtitle => _l10n.customSourcesSubtitle;
  String get nasServer => _l10n.nasServer;
  String get playback => _l10n.playback;
  String get audioQuality => _l10n.audioQuality;
  String get chooseQuality => _l10n.chooseQuality;
  String get equalizer => _l10n.equalizer;
  String get sleepTimer => _l10n.sleepTimer;
  String get cancel => _l10n.cancel;
  String get sleepTimerCancelled => _l10n.sleepTimerCancelled;
  String get autoResume => _l10n.autoResume;
  String get autoResumeSubtitle => _l10n.autoResumeSubtitle;
  String get floatingPlayer => _l10n.floatingPlayer;
  String get floatingPlayerSubtitle => _l10n.floatingPlayerSubtitle;
  String get floatingPlayerPermission => _l10n.floatingPlayerPermission;
  String get forceLandscape => _l10n.forceLandscape;
  String get forceLandscapeSubtitle => _l10n.forceLandscapeSubtitle;
  String get simplifyEffects => _l10n.simplifyEffects;
  String get simplifyEffectsSubtitle => _l10n.simplifyEffectsSubtitle;
  String get defaultSearchPlatform => _l10n.defaultSearchPlatform;
  String get listeningStats => _l10n.listeningStats;
  String get listeningStatsSubtitle => _l10n.listeningStatsSubtitle;
  String get appearance => _l10n.appearance;
  String get language => _l10n.language;
  String get darkMode => _l10n.darkMode;
  String get darkModeSubtitle => _l10n.darkModeSubtitle;
  String get followSystem => _l10n.followSystem;
  String get followSystemThemeSubtitle => _l10n.followSystemThemeSubtitle;
  String get followSystemLanguageSubtitle => _l10n.followSystemLanguageSubtitle;
  String get themeColor => _l10n.themeColor;
  String get themeColorSubtitle => _l10n.themeColorSubtitle;
  String get downloads => _l10n.downloads;
  String get downloadManager => _l10n.downloadManager;
  String get downloadManagerSubtitle => _l10n.downloadManagerSubtitle;
  String get wifiOnly => _l10n.wifiOnly;
  String get wifiOnlySubtitle => _l10n.wifiOnlySubtitle;
  String get downloadQuality => _l10n.downloadQuality;
  String get chooseDownloadQuality => _l10n.chooseDownloadQuality;
  String get data => _l10n.data;
  String get backup => _l10n.backup;
  String get backupSubtitle => _l10n.backupSubtitle;
  String get restore => _l10n.restore;
  String get restoreSubtitle => _l10n.restoreSubtitle;
  String get clearCache => _l10n.clearCache;
  String get clearCacheSubtitle => _l10n.clearCacheSubtitle;
  String get about => _l10n.about;
  String get version => _l10n.version;
  String get deviceUuid => _l10n.deviceUuid;
  String get loading => _l10n.loading;
  String get deviceUuidCopied => _l10n.deviceUuidCopied;
  String get diagnostics => _l10n.diagnostics;
  String get diagnosticsSubtitle => _l10n.diagnosticsSubtitle;
  String get volume => _l10n.volume;
  String get mute => _l10n.mute;
  String get unmute => _l10n.unmute;
  String get download => _l10n.download;
  String get addedToDownloads => _l10n.addedToDownloads;
  String get downloadFailed => _l10n.downloadFailed;
  String get exportBackupTitle => _l10n.exportBackupTitle;
  String get restoreSucceeded => _l10n.restoreSucceeded;
  String get chooseCache => _l10n.chooseCache;
  String get selectAll => _l10n.selectAll;
  String get playbackCache => _l10n.playbackCache;
  String get playbackCacheSubtitle => _l10n.playbackCacheSubtitle;
  String get artworkCache => _l10n.artworkCache;
  String get artworkCacheSubtitle => _l10n.artworkCacheSubtitle;
  String get tempFiles => _l10n.tempFiles;
  String get tempFilesSubtitle => _l10n.tempFilesSubtitle;
  String get cacheKeepNote => _l10n.cacheKeepNote;
  String get clear => _l10n.clear;
  String get cacheCleared => _l10n.cacheCleared;
  String get cancelSleepTimer => _l10n.cancelSleepTimer;
  String get chineseInterface => _l10n.chineseInterface;
  String get englishInterface => _l10n.englishInterface;
  String get shortcuts => _l10n.shortcuts;
  String get shortcutSettings => _l10n.shortcutSettings;
  String get closeShortcutSettings => _l10n.closeShortcutSettings;
  String get searchSongsHint => _l10n.searchSongsHint;
  String get heroCardSettings => _l10n.heroCardSettings;
  String get heroCardSettingsAction => _l10n.heroCardSettingsAction;
  String get closeHeroCardSettings => _l10n.closeHeroCardSettings;
  String get heroCardHint => _l10n.heroCardHint;
  String get heroPlayMode => _l10n.heroPlayMode;
  String get heroPlayModeHint => _l10n.heroPlayModeHint;
  String get favorites => _l10n.favorites;
  String get forYou => _l10n.forYou;
  String get localMusic => _l10n.localMusic;
  String get nasLibrary => _l10n.nasLibrary;
  String get recentPlays => _l10n.recentPlays;
  String get playInOrder => _l10n.playInOrder;
  String get shufflePlay => _l10n.shufflePlay;
  String get repeatOne => _l10n.repeatOne;
  String get playInOrderHint => _l10n.playInOrderHint;
  String get shufflePlayHint => _l10n.shufflePlayHint;
  String get repeatOneHint => _l10n.repeatOneHint;
  String get noFavoritesYet => _l10n.noFavoritesYet;
  String get recommendAfterFavorites => _l10n.recommendAfterFavorites;
  String get heroRecentEmpty => _l10n.heroRecentEmpty;
  String get chooseFolderToScan => _l10n.chooseFolderToScan;
  String get nasHosts => _l10n.nasHosts;
  String get loadSongsFailed => _l10n.loadSongsFailed;
  String get playFailed => _l10n.playFailed;
  String get noSongsOnServer => _l10n.noSongsOnServer;
  String get retry => _l10n.retry;
  String get otherPlatform => _l10n.otherPlatform;
  String get featured => _l10n.featured;
  String get noChartData => _l10n.noChartData;
  String get chartsHidden => _l10n.chartsHidden;
  String get chartSettings => _l10n.chartSettings;
  String get refreshCharts => _l10n.refreshCharts;
  String get noSongData => _l10n.noSongData;
  String get showAll => _l10n.showAll;
  String get back => _l10n.back;
  String get defaultFirst => _l10n.defaultFirst;
  String get importPlaylist => _l10n.importPlaylist;
  String get newPlaylist => _l10n.newPlaylist;
  String get searchLibraryHint => _l10n.searchLibraryHint;
  String get clearSearch => _l10n.clearSearch;
  String get clearResults => _l10n.clearResults;
  String get customPlaylists => _l10n.customPlaylists;
  String get sortPlaylists => _l10n.sortPlaylists;
  String get nothingMatched => _l10n.nothingMatched;
  String get createPlaylist => _l10n.createPlaylist;
  String get playlistName => _l10n.playlistName;
  String get descriptionOptional => _l10n.descriptionOptional;
  String get create => _l10n.create;
  String get editPlaylist => _l10n.editPlaylist;
  String get save => _l10n.save;
  String get sortBy => _l10n.sortBy;
  String get recentlyAdded => _l10n.recentlyAdded;
  String get sortByName => _l10n.sortByName;
  String get sortByCount => _l10n.sortByCount;
  String get pastePlaylistLink => _l10n.pastePlaylistLink;
  String get closeImport => _l10n.closeImport;
  String get sourcePlatform => _l10n.sourcePlatform;
  String get kuwoShort => _l10n.kuwoShort;
  String get kugouShort => _l10n.kugouShort;
  String get neteaseShort => _l10n.neteaseShort;
  String get playlistLinkOrId => _l10n.playlistLinkOrId;
  String get enterLinkOrId => _l10n.enterLinkOrId;
  String get importAction => _l10n.importAction;
  String get parsingPlaylist => _l10n.parsingPlaylist;
  String get parsePlaylist => _l10n.parsePlaylist;
  String get addAllToFavorites => _l10n.addAllToFavorites;
  String get addFailed => _l10n.addFailed;
  String get alreadyInFavorites => _l10n.alreadyInFavorites;
  String get deletePlaylist => _l10n.deletePlaylist;
  String get deleteFailed => _l10n.deleteFailed;
  String get createFailed => _l10n.createFailed;
  String get saveFailed => _l10n.saveFailed;
  String get choosePlatform => _l10n.choosePlatform;
  String get platform => _l10n.platform;
  String get searchFieldHint => _l10n.searchFieldHint;
  String get searchAction => _l10n.searchAction;
  String get noResults => _l10n.noResults;
  String get searchEmptyHint => _l10n.searchEmptyHint;
  String get searchErrorTitle => _l10n.searchErrorTitle;
  String get searchAllSources => _l10n.searchAllSources;
  String get onlineMusic => _l10n.onlineMusic;
  String get slideForMore => _l10n.slideForMore;
  String get moreActions => _l10n.moreActions;
  String get searchHistory => _l10n.searchHistory;
  String get clearHistory => _l10n.clearHistory;
  String get hotSearch => _l10n.hotSearch;
  String get loadingEllipsis => _l10n.loadingEllipsis;
  String get playNow => _l10n.playNow;
  String get addToPlaylist => _l10n.addToPlaylist;
  String get favorite => _l10n.favorite;
  String get unfavorite => _l10n.unfavorite;
  String get favoriteFailed => _l10n.favoriteFailed;
  String get playbackProgress => _l10n.playbackProgress;
  String get nothingPlaying => _l10n.nothingPlaying;
  String get unknownQuality => _l10n.unknownQuality;
  String get resolvingQuality => _l10n.resolvingQuality;
  String get collapsePlayer => _l10n.collapsePlayer;
  String get backToArtwork => _l10n.backToArtwork;
  String get nowPlaying => _l10n.nowPlaying;
  String get lyrics => _l10n.lyrics;
  String get more => _l10n.more;
  String get openLyrics => _l10n.openLyrics;
  String get playMode => _l10n.playMode;
  String get previous => _l10n.previous;
  String get next => _l10n.next;
  String get queue => _l10n.queue;
  String get dislikeAndSkip => _l10n.dislikeAndSkip;
  String get dislikedNote => _l10n.dislikedNote;
  String get dislikeFailed => _l10n.dislikeFailed;
  String get queueLoadFailed => _l10n.queueLoadFailed;
  String get queueEmpty => _l10n.queueEmpty;
  String get playlistMissing => _l10n.playlistMissing;
  String get exitMultiSelect => _l10n.exitMultiSelect;
  String get cancelEdit => _l10n.cancelEdit;
  String get deselectAll => _l10n.deselectAll;
  String get downloadSelected => _l10n.downloadSelected;
  String get unfavoriteSelected => _l10n.unfavoriteSelected;
  String get playAll => _l10n.playAll;
  String get alreadyFavorited => _l10n.alreadyFavorited;
  String get actionFailedShort => _l10n.actionFailedShort;
  String get favoriteAll => _l10n.favoriteAll;
  String get editInfo => _l10n.editInfo;
  String get manualSort => _l10n.manualSort;
  String get sortByTitle => _l10n.sortByTitle;
  String get sortByArtist => _l10n.sortByArtist;
  String get sortByDuration => _l10n.sortByDuration;
  String get duplicateSongs => _l10n.duplicateSongs;
  String get clearFavorites => _l10n.clearFavorites;
  String get noSongs => _l10n.noSongs;
  String get locateFailed => _l10n.locateFailed;
  String get play => _l10n.play;
  String get removeFromPlaylist => _l10n.removeFromPlaylist;
  String get removeFailed => _l10n.removeFailed;
  String get nothingSelectedToDownload => _l10n.nothingSelectedToDownload;
  String get nothingSelectedToUnfavorite => _l10n.nothingSelectedToUnfavorite;
  String get unfavoriteFailed => _l10n.unfavoriteFailed;
  String get descriptionLabel => _l10n.descriptionLabel;
  String get clearFavoritesTitle => _l10n.clearFavoritesTitle;
  String get confirmClear => _l10n.confirmClear;
  String get favoritesAlreadyEmpty => _l10n.favoritesAlreadyEmpty;
  String get delete => _l10n.delete;
  String get close => _l10n.close;
  String get add => _l10n.add;
  String get pause => _l10n.pause;
  String get refresh => _l10n.refresh;
  String get connect => _l10n.connect;
  String get reset => _l10n.reset;
  String get remove => _l10n.remove;
  String get start => _l10n.start;
  String get log => _l10n.log;
  String get edit => _l10n.edit;
  String get export => _l10n.export;
  String get customPreset => _l10n.customPreset;
  String get presets => _l10n.presets;
  String get pauseAll => _l10n.pauseAll;
  String get waiting => _l10n.waiting;
  String get done => _l10n.done;
  String get all => _l10n.all;
  String get username => _l10n.username;
  String get password => _l10n.password;
  String get login => _l10n.login;
  String get register => _l10n.register;
  String get pleaseWait => _l10n.pleaseWait;
  String get notice => _l10n.notice;
  String get success => _l10n.success;
  String get warning => _l10n.warning;
  String get error => _l10n.error;
  String get dismissNotification => _l10n.dismissNotification;
  String get somethingWentWrong => _l10n.somethingWentWrong;
  String get notPlaying => _l10n.notPlaying;
  String get noLyrics => _l10n.noLyrics;
  String get openNowPlaying => _l10n.openNowPlaying;
  String get previousPage => _l10n.previousPage;
  String get nextPage => _l10n.nextPage;
  String get choosePage => _l10n.choosePage;
  String get preparingApp => _l10n.preparingApp;
  String get startupFailed => _l10n.startupFailed;
  String get startupLoading => _l10n.startupLoading;
  String get retryStartup => _l10n.retryStartup;
  String get lyricsLoading => _l10n.lyricsLoading;
  String get fetchingLyrics => _l10n.fetchingLyrics;
  String get lyricsFailed => _l10n.lyricsFailed;
  String get checkNetwork => _l10n.checkNetwork;
  String get lyricsEmpty => _l10n.lyricsEmpty;
  String get lyricsUnavailable => _l10n.lyricsUnavailable;
  String get searchLyrics => _l10n.searchLyrics;
  String get equalizerUnavailable => _l10n.equalizerUnavailable;
  String get equalizerUnavailableBody => _l10n.equalizerUnavailableBody;
  String get equalizerHint => _l10n.equalizerHint;
  String get unavailableOnPlatform => _l10n.unavailableOnPlatform;
  String get gainDb => _l10n.gainDb;
  String get enableEqualizerToAdjust => _l10n.enableEqualizerToAdjust;
  String get bandsPending => _l10n.bandsPending;
  String get localMusicSettings => _l10n.localMusicSettings;
  String get rescan => _l10n.rescan;
  String get noLocalSongs => _l10n.noLocalSongs;
  String get localLibraryTitle => _l10n.localLibraryTitle;
  String get folderPickerHint => _l10n.folderPickerHint;
  String get androidMediaStore => _l10n.androidMediaStore;
  String get writeTags => _l10n.writeTags;
  String get writeTagsHint => _l10n.writeTagsHint;
  String get pickFolderFailed => _l10n.pickFolderFailed;
  String get chooseMusicFolder => _l10n.chooseMusicFolder;
  String get chooseFolderFailed => _l10n.chooseFolderFailed;
  String get safImporting => _l10n.safImporting;
  String get scanAndroidFailed => _l10n.scanAndroidFailed;
  String get mediaStoreScanning => _l10n.mediaStoreScanning;
  String get mediaStoreEmpty => _l10n.mediaStoreEmpty;
  String get tryingAllFiles => _l10n.tryingAllFiles;
  String get openingSaf => _l10n.openingSaf;
  String get androidAccessDenied => _l10n.androidAccessDenied;
  String get androidAuthFailed => _l10n.androidAuthFailed;
  String get matchingOnline => _l10n.matchingOnline;
  String get scanFailed => _l10n.scanFailed;
  String get noLocalSources => _l10n.noLocalSources;
  String get rescanning => _l10n.rescanning;
  String get rescanFailed => _l10n.rescanFailed;
  String get noWritableSongs => _l10n.noWritableSongs;
  String get writingTags => _l10n.writingTags;
  String get noTagsToWrite => _l10n.noTagsToWrite;
  String get writeTagsFailed => _l10n.writeTagsFailed;
  String get folderRemoved => _l10n.folderRemoved;
  String get downloadsTitle => _l10n.downloadsTitle;
  String get deleteFinishedDownloads => _l10n.deleteFinishedDownloads;
  String get clearFailedTasks => _l10n.clearFailedTasks;
  String get noDownloadTasks => _l10n.noDownloadTasks;
  String get noTasks => _l10n.noTasks;
  String get downloadSpeed => _l10n.downloadSpeed;
  String get downloaded => _l10n.downloaded;
  String get linkExpired => _l10n.linkExpired;
  String get deleteFiles => _l10n.deleteFiles;
  String get clearFailedAction => _l10n.clearFailedAction;
  String get listeningStatsEmpty => _l10n.listeningStatsEmpty;
  String get listeningStatsEmptyHint => _l10n.listeningStatsEmptyHint;
  String get playCount => _l10n.playCount;
  String get listenTime => _l10n.listenTime;
  String get activeDays => _l10n.activeDays;
  String get trackCount => _l10n.trackCount;
  String get dailyPlays => _l10n.dailyPlays;
  String get songs => _l10n.songs;
  String get artists => _l10n.artists;
  String get albums => _l10n.albums;
  String get noData => _l10n.noData;
  String get loadFailed => _l10n.loadFailed;
  String get noDuplicateFavorites => _l10n.noDuplicateFavorites;
  String get selectRecommended => _l10n.selectRecommended;
  String get working => _l10n.working;
  String get removeSelected => _l10n.removeSelected;
  String get removeGroupSelected => _l10n.removeGroupSelected;
  String get keepSuggested => _l10n.keepSuggested;
  String get hasLyricsMark => _l10n.hasLyricsMark;
  String get addedToPlaylist => _l10n.addedToPlaylist;
  String get playlistCreatedAndAdded => _l10n.playlistCreatedAndAdded;
  String get collapseNewPlaylist => _l10n.collapseNewPlaylist;
  String get newPlaylistName => _l10n.newPlaylistName;
  String get basedOnFavorites => _l10n.basedOnFavorites;
  String get noRecommendations => _l10n.noRecommendations;
  String get recommendationsNeedFavorites => _l10n.recommendationsNeedFavorites;
  String get playlistEmpty => _l10n.playlistEmpty;
  String get playlistEmptyNas => _l10n.playlistEmptyNas;
  String get connectionSettings => _l10n.connectionSettings;
  String get scraping => _l10n.scraping;
  String get scrapeArtworkLyrics => _l10n.scrapeArtworkLyrics;
  String get goConnect => _l10n.goConnect;
  String get noOnlineMatch => _l10n.noOnlineMatch;
  String get welcome => _l10n.welcome;
  String get welcomeBody => _l10n.welcomeBody;
  String get serverAddress => _l10n.serverAddress;
  String get syncUsernameHint => _l10n.syncUsernameHint;
  String get syncPasswordHint => _l10n.syncPasswordHint;
  String get registerAndSync => _l10n.registerAndSync;
  String get loginAndSync => _l10n.loginAndSync;
  String get backToLogin => _l10n.backToLogin;
  String get needAccount => _l10n.needAccount;
  String get skipStep => _l10n.skipStep;
  String get skipStepHint => _l10n.skipStepHint;
  String get fillServerLogin => _l10n.fillServerLogin;
  String get loginFailed => _l10n.loginFailed;
  String get syncTitle => _l10n.syncTitle;
  String get syncAccount => _l10n.syncAccount;
  String get workersServer => _l10n.workersServer;
  String get workersUnset => _l10n.workersUnset;
  String get notLoggedIn => _l10n.notLoggedIn;
  String get loginToSync => _l10n.loginToSync;
  String get syncing => _l10n.syncing;
  String get syncExplainer => _l10n.syncExplainer;
  String get eventSync => _l10n.eventSync;
  String get syncNow => _l10n.syncNow;
  String get mergingEvents => _l10n.mergingEvents;
  String get syncDoesNotOverwrite => _l10n.syncDoesNotOverwrite;
  String get offlineUntilNetwork => _l10n.offlineUntilNetwork;
  String get logOut => _l10n.logOut;
  String get logOutHint => _l10n.logOutHint;
  String get loggedOut => _l10n.loggedOut;
  String get userAdmin => _l10n.userAdmin;
  String get userAdminHint => _l10n.userAdminHint;
  String get workersAddress => _l10n.workersAddress;
  String get serverReachable => _l10n.serverReachable;
  String get savedHealthFailed => _l10n.savedHealthFailed;
  String get httpsRequired => _l10n.httpsRequired;
  String get enterServerFirst => _l10n.enterServerFirst;
  String get loginSucceeded => _l10n.loginSucceeded;
  String get failed => _l10n.failed;
  String get syncFinished => _l10n.syncFinished;
  String get userList => _l10n.userList;
  String get newUser => _l10n.newUser;
  String get userCreated => _l10n.userCreated;
  String get customSourcesTitle => _l10n.customSourcesTitle;
  String get importLocalScript => _l10n.importLocalScript;
  String get importFromLink => _l10n.importFromLink;
  String get addManually => _l10n.addManually;
  String get pasteScript => _l10n.pasteScript;
  String get noCustomSources => _l10n.noCustomSources;
  String get addCustomSourceHint => _l10n.addCustomSourceHint;
  String get importScriptOk => _l10n.importScriptOk;
  String get importScriptBad => _l10n.importScriptBad;
  String get addCustomSource => _l10n.addCustomSource;
  String get sourceName => _l10n.sourceName;
  String get author => _l10n.author;
  String get script => _l10n.script;
  String get editCustomSource => _l10n.editCustomSource;
  String get httpsLinkRequired => _l10n.httpsLinkRequired;
  String get importOk => _l10n.importOk;
  String get importLinkBad => _l10n.importLinkBad;
  String get directDownloadHint => _l10n.directDownloadHint;
  String get clipboardEmpty => _l10n.clipboardEmpty;
  String get clipboard => _l10n.clipboard;
  String get importCustomSource => _l10n.importCustomSource;
  String get lxScriptHint => _l10n.lxScriptHint;
  String get pasteScriptHint => _l10n.pasteScriptHint;
  String get importFormatBad => _l10n.importFormatBad;
  String get exportCustomSource => _l10n.exportCustomSource;
  String get deleteCustomSource => _l10n.deleteCustomSource;
  String get logCopied => _l10n.logCopied;
  String get noLog => _l10n.noLog;
  String get copyLog => _l10n.copyLog;
  String get enterUsername => _l10n.enterUsername;
  String get enterPassword => _l10n.enterPassword;
  String get enterPasswordOrToken => _l10n.enterPasswordOrToken;
  String get connectFailed => _l10n.connectFailed;
  String get nasServerTitle => _l10n.nasServerTitle;
  String get usernameOptional => _l10n.usernameOptional;
  String get plexAccountHint => _l10n.plexAccountHint;
  String get serverLoginName => _l10n.serverLoginName;
  String get passwordOrToken => _l10n.passwordOrToken;
  String get passwordSaved => _l10n.passwordSaved;
  String get passwordOrPlexToken => _l10n.passwordOrPlexToken;
  String get serverPassword => _l10n.serverPassword;
  String get webDavRootPath => _l10n.webDavRootPath;
  String get webDavRootPathHint => _l10n.webDavRootPathHint;
  String get webDavAuthMethod => _l10n.webDavAuthMethod;
  String get webDavBasicAuth => _l10n.webDavBasicAuth;
  String get webDavBearerAuth => _l10n.webDavBearerAuth;
  String get webDavTokenHint => _l10n.webDavTokenHint;
  String get webDavRootPathInvalid => _l10n.webDavRootPathInvalid;
  String get webDavScanFailed => _l10n.webDavScanFailed;
  String get showPassword => _l10n.showPassword;
  String get hidePassword => _l10n.hidePassword;
  String get legacyAuth => _l10n.legacyAuth;
  String get legacyAuthHint => _l10n.legacyAuthHint;
  String get reconnect => _l10n.reconnect;
  String get disconnect => _l10n.disconnect;
  String get diagnosticsTitle => _l10n.diagnosticsTitle;
  String get minimize => _l10n.minimize;
  String get copyAll => _l10n.copyAll;
  String get closeDiagnostics => _l10n.closeDiagnostics;
  String get clearMemoryLog => _l10n.clearMemoryLog;
  String get diagnosticsHint => _l10n.diagnosticsHint;
  String get stoppedAfterRepeatedFailures => _l10n.stoppedAfterRepeatedFailures;
  String get autoplayNextFailed => _l10n.autoplayNextFailed;
  String get reloadingSong => _l10n.reloadingSong;
  String get tryingNextSong => _l10n.tryingNextSong;

  String get playlistLinkExample => _l10n.playlistLinkExample;

  // ---- ARB-backed parameterised copy --------------------------------
  String backupExported(String path) => _l10n.backupExported(path);
  String backupFailed(Object error) => _l10n.backupFailed('$error');
  String restoreFailed(Object error) => _l10n.restoreFailed('$error');
  String cacheClearedRetained(int count) => _l10n.cacheClearedRetained(count);
  String clearFailed(Object error) => _l10n.clearFailed('$error');
  String minutes(int count) => _l10n.minutes(count);
  String stopsInMinutes(int count) => _l10n.stopsInMinutes(count);
  String playAction(String mode, String target) => _l10n.playAction(mode, target);
  String recommendedSongs(int count) => _l10n.recommendedSongs(count);
  String songCount(int count) => _l10n.songCount(count);
  String loadingHost(String host) => _l10n.loadingHost(host);
  String actionFailed(String action, Object error) => _l10n.actionFailed(action, '$error');
  String failedWith(String label, Object error) => _l10n.failedWith(label, '$error');
  String nowPlayingNamed(String name) => _l10n.nowPlayingNamed(name);
  String playNamed(String name) => _l10n.playNamed(name);
  String chartCount(int count) => _l10n.chartCount(count);
  String hiddenUntil(String name) => _l10n.hiddenUntil(name);
  String songsHeader(int count) => _l10n.songsHeader(count);
  String playlistsHeader(int count) => _l10n.playlistsHeader(count);
  String importProgress(int loaded, int total) => _l10n.importProgress(loaded, total);
  String confirmImport(int count) => _l10n.confirmImport(count);
  String importedFrom(String source) => _l10n.importedFrom(source);
  String importedResult(String name, int count) => _l10n.importedResult(name, count);
  String parsingProgress(String progress) => _l10n.parsingProgress(progress);
  String addedToFavorites(int count) => _l10n.addedToFavorites(count);
  String searchFailed(Object error) => _l10n.searchFailed('$error');
  String searchEmptyTitle(String query) => _l10n.searchEmptyTitle(query);
  String localArtist(String singer) => _l10n.localArtist(singer);
  String queueTitle(int count) => _l10n.queueTitle(count);
  String selectedCount(int count) => _l10n.selectedCount(count);
  String playlistTitleCount(String name, int count) => _l10n.playlistTitleCount(name, count);
  String favoritedSongs(int count) => _l10n.favoritedSongs(count);
  String queuedDownloads(int count) => _l10n.queuedDownloads(count);
  String unfavoritedSongs(int count) => _l10n.unfavoritedSongs(count);
  String clearFavoritesBody(int count) => _l10n.clearFavoritesBody(count);
  String deletePlaylistConfirm(String name) => _l10n.deletePlaylistConfirm(name);
  String pagePosition(int page, int count) => _l10n.pagePosition(page, count);
  String startupFailedHint(String error) => _l10n.startupFailedHint(error);
  String bandsReady(int count, String range) => _l10n.bandsReady(count, range);
  String localSongCount(int count) => _l10n.localSongCount(count);
  String mediaStoreHint(int count) => _l10n.mediaStoreHint(count);
  String downloadFolder(String path) => _l10n.downloadFolder(path);
  String importingCount(int done, int total) => _l10n.importingCount(done, total);
  String mediaStoreImporting(int done, int total) => _l10n.mediaStoreImporting(done, total);
  String allFilesScanning(int done, int total) => _l10n.allFilesScanning(done, total);
  String scanningPath(String path) => _l10n.scanningPath(path);
  String readingMetadata(int done, int total) => _l10n.readingMetadata(done, total);
  String scrapingCount(int done, int total) => _l10n.scrapingCount(done, total);
  String localUpdated(int count) => _l10n.localUpdated(count);
  String writingTagsCount(int done, int total) => _l10n.writingTagsCount(done, total);
  String tagsWritten(int written, int attempted) => _l10n.tagsWritten(written, attempted);
  String activeHeader(int count) => _l10n.activeHeader(count);
  String finishedHeader(int count) => _l10n.finishedHeader(count);
  String downloadingPercent(String percent) => _l10n.downloadingPercent(percent);
  String pausedPercent(String singer, String percent) => _l10n.pausedPercent(singer, percent);
  String deleteFinishedBody(int count) => _l10n.deleteFinishedBody(count);
  String clearFailedBody(int count) => _l10n.clearFailedBody(count);
  String dailyPeak(int days, int maxCount) => _l10n.dailyPeak(days, maxCount);
  String statSubtitle(String subtitle, int count) => _l10n.statSubtitle(subtitle, count);
  String duplicateGroup(String artist, int count) => _l10n.duplicateGroup(artist, count);
  String removedDuplicates(int count) => _l10n.removedDuplicates(count);
  String playlistSongCount(int count) => _l10n.playlistSongCount(count);
  String recommendUpdated(int count) => _l10n.recommendUpdated(count);
  String scrapingProgress(int done, int total) => _l10n.scrapingProgress(done, total);
  String notConnected(String name) => _l10n.notConnected(name);
  String connectedHost(String host) => _l10n.connectedHost(host);
  String matchedSongs(int matched, int total) => _l10n.matchedSongs(matched, total);
  String scrapeFailed(Object error) => _l10n.scrapeFailed('$error');
  String nasPlaylistTitle(String name) => _l10n.nasPlaylistTitle(name);
  String loggedInAs(String name) => _l10n.loggedInAs(name);
  String roleLine(String role) => _l10n.roleLine(role);
  String deviceLine(String id) => _l10n.deviceLine(id);
  String timeLine(String time) => _l10n.timeLine(time);
  String syncFailed(Object error) => _l10n.syncFailed('$error');
  String adminUser(String id) => _l10n.adminUser(id);
  String normalUser(String id) => _l10n.normalUser(id);
  String deleteUser(String name) => _l10n.deleteUser(name);
  String deletedUser(String name) => _l10n.deletedUser(name);
  String usersLoadFailed(Object error) => _l10n.usersLoadFailed('$error');
  String sourceInitFailed(String name) => _l10n.sourceInitFailed(name);
  String importScriptFailed(Object reason) => _l10n.importScriptFailed('$reason');
  String readFileFailed(Object error) => _l10n.readFileFailed('$error');
  String deleteSourceConfirm(String name) => _l10n.deleteSourceConfirm(name);
  String sourceLogTitle(String name) => _l10n.sourceLogTitle(name);
  String disconnected(String name) => _l10n.disconnected(name);
  String diagnosticsCount(int count) => _l10n.diagnosticsCount(count);
  String playingQuoted(String name) => _l10n.playingQuoted(name);
  String unresolvedUrl(String title) => _l10n.unresolvedUrl(title);
  String playSongFailed(String title, Object error) => _l10n.playSongFailed(title, '$error');

  // ---- branching copy that ARB cannot express -----------------------
  String builtinPlaylistName(String id, String storedName) => switch (id) {
    'favorites' => favorites,
    'recent' => recentPlays,
    'local' => localMusic,
    _ => storedName,
  };

  String connectedType(String type, String? version) => version == null
      ? (en ? 'Connected to $type' : '已连接 $type')
      : (en ? 'Connected to $type $version' : '已连接 $type $version');

  String currentConnection(String title, String host, String? username) =>
      username == null
      ? (en ? 'Current: $title · $host' : '当前：$title · $host')
      : (en
            ? 'Current: $title · $host · $username'
            : '当前：$title · $host · $username');

  String languageName(AppLanguage language) => switch (language) {
    AppLanguage.system => followSystem,
    AppLanguage.zh => '简体中文',
    AppLanguage.en => 'English',
  };


  String platformName(String id) => switch (id) {
    'qq' => en ? 'QQ Music' : 'QQ音乐',
    'tx' => en ? 'QQ Music' : 'QQ音乐',
    'kw' => en ? 'Kuwo' : '酷我音乐',
    'wy' => en ? 'NetEase' : '网易云',
    'kg' => en ? 'Kugou' : '酷狗音乐',
    _ => otherPlatform,
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

  String playlistMeta(int count, String? description) => en
      ? '$count songs · ${description ?? 'Private'}'
      : '$count 首歌曲 · ${description ?? '私人'}';

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

  String qualityText(String q) => switch (q) {
    'flac24bit' => en ? 'Master' : '臻品母带',
    'flac' => en ? 'Lossless' : '无损',
    'hires' => 'Hi-Res',
    '320k' => '320kbps',
    '192k' => '192kbps',
    '128k' => '128kbps',
    _ => q,
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


  String quickTitle(String id) => switch (id) {
    'recommend' => forYou,
    'local' => localMusic,
    'subsonic' => nasLibrary,
    // 快捷卡只有两列宽（约 106pt 文字列），"Download manager" 这个
    // 页面标题在这里会把单词截断，换成更短的同义标签。
    'downloads' => en ? 'Downloads' : downloadManager,
    'stats' => listeningStats,
    'sleep_timer' => sleepTimer,
    'theme' => en ? 'Theme' : '切换主题',
    'favorites' => favorites,
    'recent' => recentPlays,
    'leaderboard' => charts,
    'search' => en ? 'Search' : '搜索歌曲',
    'playlists' => en ? 'Playlists' : '歌单管理',
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


}

/// Maps a runtime message produced by the audio layer (currently Chinese,
/// generated deep inside the player) back onto localised copy.
///
/// This is a compatibility shim: the proper fix is for the player to emit
/// typed error codes instead of prose. Until then this keeps the user-visible
/// strings translated without a risky refactor of the playback error path.
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

bool localeIsEnglish(Locale? locale) =>
    locale?.languageCode == 'en';
