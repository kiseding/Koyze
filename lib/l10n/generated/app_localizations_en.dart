// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get home => 'Home';

  @override
  String get charts => 'Charts';

  @override
  String get playlists => 'Playlists';

  @override
  String get settings => 'Settings';

  @override
  String get sync => 'Sync';

  @override
  String get cloudAccount => 'Cloud account';

  @override
  String get cloudAccountSubtitle =>
      'Sync favorites, playlists, settings, and custom sources';

  @override
  String get advanced => 'Advanced';

  @override
  String get localLibrary => 'Local music folders';

  @override
  String get localLibrarySubtitle =>
      'Choose folders, rescan, and match songs online';

  @override
  String get customSources => 'Custom sources';

  @override
  String get customSourcesSubtitle => 'Manage custom music sources';

  @override
  String get nasServer => 'NAS music server';

  @override
  String get playback => 'Playback';

  @override
  String get audioQuality => 'Audio quality';

  @override
  String get chooseQuality => 'Choose quality';

  @override
  String get equalizer => 'Equalizer';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get cancel => 'Cancel';

  @override
  String get sleepTimerCancelled => 'Sleep timer cancelled';

  @override
  String get autoResume => 'Resume on launch';

  @override
  String get autoResumeSubtitle => 'Continue the last song when the app opens';

  @override
  String get floatingPlayer => 'Floating player';

  @override
  String get floatingPlayerSubtitle =>
      'Show cover, lyrics, progress, and playback controls over other apps';

  @override
  String get floatingPlayerPermission =>
      'Allow display over other apps, then return to Koyze';

  @override
  String get forceLandscape => 'Force landscape';

  @override
  String get forceLandscapeSubtitle =>
      'Use the landscape layout. Phones also stay in landscape';

  @override
  String get simplifyEffects => 'Reduce effects';

  @override
  String get simplifyEffectsSubtitle =>
      'Turn off frosted glass, transparency, and motion. On by default at 4GB or less';

  @override
  String get defaultSearchPlatform => 'Default search source';

  @override
  String get listeningStats => 'Listening stats';

  @override
  String get listeningStatsSubtitle => 'History, rankings, and activity';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get darkModeSubtitle => 'Use the dark theme';

  @override
  String get followSystem => 'Follow system';

  @override
  String get followSystemThemeSubtitle =>
      'Match the system light or dark theme';

  @override
  String get followSystemLanguageSubtitle =>
      'Use the device language when it is Chinese or English';

  @override
  String get themeColor => 'Theme colour';

  @override
  String get themeColorSubtitle =>
      'One accent builds the whole Material 3 palette';

  @override
  String get downloads => 'Downloads';

  @override
  String get downloadManager => 'Download manager';

  @override
  String get downloadManagerSubtitle => 'View and manage download tasks';

  @override
  String get wifiOnly => 'Wi-Fi only';

  @override
  String get wifiOnlySubtitle => 'Download songs only on Wi-Fi';

  @override
  String get downloadQuality => 'Download quality';

  @override
  String get chooseDownloadQuality => 'Choose download quality';

  @override
  String get data => 'Data';

  @override
  String get backup => 'Back up';

  @override
  String get backupSubtitle => 'Export playlists and settings to a file';

  @override
  String get restore => 'Restore';

  @override
  String get restoreSubtitle => 'Restore from a backup file';

  @override
  String get clearCache => 'Clear cache';

  @override
  String get clearCacheSubtitle =>
      'Clear playback cache, artwork, and temporary files';

  @override
  String get about => 'About';

  @override
  String get version => 'Version';

  @override
  String get deviceUuid => 'Device UUID';

  @override
  String get loading => 'Loading…';

  @override
  String get deviceUuidCopied => 'Device UUID copied';

  @override
  String get diagnostics => 'Live diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Start recording when opened. Keeps recording while minimized.';

  @override
  String get volume => 'Volume';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get download => 'Download';

  @override
  String get addedToDownloads => 'Added to the download queue';

  @override
  String get downloadFailed => 'Could not add download';

  @override
  String get exportBackupTitle => 'Export Koyze backup';

  @override
  String get restoreSucceeded => 'Restore complete';

  @override
  String get chooseCache => 'Choose what to clear';

  @override
  String get selectAll => 'Select all';

  @override
  String get playbackCache => 'Playback cache';

  @override
  String get playbackCacheSubtitle =>
      'Cached songs. Manual downloads are not included.';

  @override
  String get artworkCache => 'Artwork cache';

  @override
  String get artworkCacheSubtitle => 'Album art stored on disk and in memory';

  @override
  String get tempFiles => 'Temporary files';

  @override
  String get tempFilesSubtitle =>
      'Intermediate files in the system temp folder';

  @override
  String get cacheKeepNote =>
      'Manual downloads stay. A song that is playing keeps its cache.';

  @override
  String get clear => 'Clear';

  @override
  String get cacheCleared => 'Selected cache cleared';

  @override
  String get cancelSleepTimer => 'Cancel sleep timer';

  @override
  String get chineseInterface => 'Chinese interface';

  @override
  String get englishInterface => 'English interface';

  @override
  String get shortcuts => 'Shortcuts';

  @override
  String get shortcutSettings => 'Shortcut settings';

  @override
  String get closeShortcutSettings => 'Close shortcut settings';

  @override
  String get searchSongsHint => 'Songs, artists, playlists...';

  @override
  String get heroCardSettings => 'Home card';

  @override
  String get heroCardSettingsAction => 'Home card settings';

  @override
  String get closeHeroCardSettings => 'Close home card settings';

  @override
  String get heroCardHint =>
      'Same five cards as Playlists. Only one can be on.';

  @override
  String get heroPlayMode => 'Play button mode';

  @override
  String get heroPlayModeHint =>
      'Only this card\'s button. The player mode stays separate.';

  @override
  String get favorites => 'Favorites';

  @override
  String get forYou => 'For You';

  @override
  String get localMusic => 'Local music';

  @override
  String get nasLibrary => 'NAS library';

  @override
  String get recentPlays => 'Recently played';

  @override
  String get playInOrder => 'In order';

  @override
  String get shufflePlay => 'Shuffle';

  @override
  String get repeatOne => 'Repeat one';

  @override
  String get playInOrderHint => 'Play the list in order, then start over';

  @override
  String get shufflePlayHint => 'Shuffle, then keep picking at random';

  @override
  String get repeatOneHint => 'Repeat the current song';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get recommendAfterFavorites => 'Favorite songs to get recommendations';

  @override
  String get heroRecentEmpty => 'Nothing played yet';

  @override
  String get chooseFolderToScan => 'Choose a folder to scan this device';

  @override
  String get nasHosts => 'Navidrome / Emby / Plex / Synology';

  @override
  String get loadSongsFailed => 'Could not load songs';

  @override
  String get playFailed => 'Playback failed';

  @override
  String get noSongsOnServer => 'No songs on the server yet';

  @override
  String get retry => 'Retry';

  @override
  String get otherPlatform => 'Other';

  @override
  String get featured => 'Picks';

  @override
  String get noChartData => 'No chart data';

  @override
  String get chartsHidden =>
      'Every chart is hidden\\nTurn them back on from the top right';

  @override
  String get chartSettings => 'Chart settings';

  @override
  String get refreshCharts => 'Refresh charts';

  @override
  String get noSongData => 'No songs';

  @override
  String get showAll => 'Show all';

  @override
  String get back => 'Back';

  @override
  String get defaultFirst => 'Shown first';

  @override
  String get importPlaylist => 'Import playlist';

  @override
  String get newPlaylist => 'New playlist';

  @override
  String get searchLibraryHint => 'Search songs or playlists';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get clearResults => 'Clear';

  @override
  String get customPlaylists => 'Custom playlists';

  @override
  String get sortPlaylists => 'Sort playlists';

  @override
  String get nothingMatched => 'No matching songs or playlists';

  @override
  String get createPlaylist => 'Create playlist';

  @override
  String get playlistName => 'Playlist name';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get create => 'Create';

  @override
  String get editPlaylist => 'Edit playlist';

  @override
  String get save => 'Save';

  @override
  String get sortBy => 'Sort by';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get sortByName => 'Name';

  @override
  String get sortByCount => 'Song count';

  @override
  String get pastePlaylistLink => 'Paste a share link or playlist ID';

  @override
  String get closeImport => 'Close import';

  @override
  String get sourcePlatform => 'Source';

  @override
  String get kuwoShort => 'Kuwo';

  @override
  String get kugouShort => 'Kugou';

  @override
  String get neteaseShort => 'NetEase';

  @override
  String get playlistLinkOrId => 'Link or ID';

  @override
  String get enterLinkOrId => 'Enter a link or ID';

  @override
  String get importAction => 'Import';

  @override
  String get parsingPlaylist => 'Reading playlist…';

  @override
  String get parsePlaylist => 'Read playlist';

  @override
  String get addAllToFavorites => 'Add all to Favorites';

  @override
  String get addFailed => 'Could not add';

  @override
  String get alreadyInFavorites => 'Those songs are already in Favorites';

  @override
  String get deletePlaylist => 'Delete playlist';

  @override
  String get deleteFailed => 'Could not delete';

  @override
  String get createFailed => 'Could not create';

  @override
  String get saveFailed => 'Could not save';

  @override
  String get choosePlatform => 'Choose a source';

  @override
  String get platform => 'Source';

  @override
  String get searchFieldHint => 'Songs, playlists...';

  @override
  String get searchAction => 'Search';

  @override
  String get noResults => 'No results';

  @override
  String get searchEmptyHint => 'Try another keyword, or switch sources.';

  @override
  String get searchErrorTitle => 'Search unavailable';

  @override
  String get searchAllSources => 'Search all sources';

  @override
  String get onlineMusic => 'Online';

  @override
  String get slideForMore => 'Scroll for more';

  @override
  String get moreActions => 'More';

  @override
  String get searchHistory => 'Recent searches';

  @override
  String get clearHistory => 'Clear';

  @override
  String get hotSearch => 'Trending';

  @override
  String get loadingEllipsis => 'Loading...';

  @override
  String get playNow => 'Play now';

  @override
  String get addToPlaylist => 'Add to playlist';

  @override
  String get favorite => 'Favorite';

  @override
  String get unfavorite => 'Unfavorite';

  @override
  String get favoriteFailed => 'Could not favorite';

  @override
  String get playbackProgress => 'Playback progress';

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get unknownQuality => 'Unknown quality';

  @override
  String get resolvingQuality => 'Resolving…';

  @override
  String get collapsePlayer => 'Close player';

  @override
  String get backToArtwork => 'Back to artwork';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get lyrics => 'Lyrics';

  @override
  String get more => 'More';

  @override
  String get openLyrics => 'Open lyrics';

  @override
  String get playMode => 'Play mode';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get queue => 'Queue';

  @override
  String get dislikeAndSkip => 'Dislike and skip';

  @override
  String get dislikedNote =>
      'Marked as disliked. It will be skipped next time.';

  @override
  String get dislikeFailed => 'Could not mark dislike';

  @override
  String get queueLoadFailed => 'Full list failed. Showing the current queue.';

  @override
  String get queueEmpty => 'Queue is empty';

  @override
  String get playlistMissing => 'Playlist not found';

  @override
  String get exitMultiSelect => 'Done';

  @override
  String get cancelEdit => 'Cancel edit';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get downloadSelected => 'Download selected';

  @override
  String get unfavoriteSelected => 'Remove selected from Favorites';

  @override
  String get playAll => 'Play all';

  @override
  String get alreadyFavorited => 'Already in Favorites';

  @override
  String get actionFailedShort => 'Action failed';

  @override
  String get favoriteAll => 'Favorite all';

  @override
  String get editInfo => 'Edit details';

  @override
  String get manualSort => 'Manual order';

  @override
  String get sortByTitle => 'Sort by title';

  @override
  String get sortByArtist => 'Sort by artist';

  @override
  String get sortByDuration => 'Sort by duration';

  @override
  String get duplicateSongs => 'Duplicate songs';

  @override
  String get clearFavorites => 'Clear favorites';

  @override
  String get noSongs => 'No songs';

  @override
  String get locateFailed => 'Could not find the song';

  @override
  String get play => 'Play';

  @override
  String get removeFromPlaylist => 'Remove from playlist';

  @override
  String get removeFailed => 'Could not remove';

  @override
  String get nothingSelectedToDownload => 'No selected songs to download';

  @override
  String get nothingSelectedToUnfavorite =>
      'No selected songs to remove from Favorites';

  @override
  String get unfavoriteFailed => 'Could not remove from Favorites';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get clearFavoritesTitle => 'Clear favorites?';

  @override
  String get confirmClear => 'Clear';

  @override
  String get favoritesAlreadyEmpty => 'Favorites is already empty';

  @override
  String get delete => 'Delete';

  @override
  String get close => 'Close';

  @override
  String get add => 'Add';

  @override
  String get pause => 'Pause';

  @override
  String get refresh => 'Refresh';

  @override
  String get connect => 'Connect';

  @override
  String get reset => 'Reset';

  @override
  String get remove => 'Remove';

  @override
  String get start => 'Start';

  @override
  String get log => 'Log';

  @override
  String get edit => 'Edit';

  @override
  String get export => 'Export';

  @override
  String get customPreset => 'Custom';

  @override
  String get presets => 'Presets';

  @override
  String get pauseAll => 'Pause all';

  @override
  String get waiting => 'Waiting';

  @override
  String get done => 'Done';

  @override
  String get all => 'All';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get login => 'Log in';

  @override
  String get register => 'Register';

  @override
  String get pleaseWait => 'Please wait…';

  @override
  String get notice => 'Notice';

  @override
  String get success => 'Success';

  @override
  String get warning => 'Warning';

  @override
  String get error => 'Error';

  @override
  String get dismissNotification => 'Dismiss';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get notPlaying => 'Not playing';

  @override
  String get noLyrics => 'No lyrics';

  @override
  String get openNowPlaying => 'Open Now Playing';

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String get choosePage => 'Choose page';

  @override
  String get preparingApp => 'Preparing Koyze';

  @override
  String get startupFailed => 'Koyze could not start';

  @override
  String get startupLoading => 'Loading your library and player…';

  @override
  String get retryStartup => 'Try again';

  @override
  String get lyricsLoading => 'Loading lyrics';

  @override
  String get fetchingLyrics => 'Fetching lyrics';

  @override
  String get lyricsFailed => 'Could not load lyrics';

  @override
  String get checkNetwork => 'Check the connection and try again';

  @override
  String get lyricsEmpty => 'No lyrics';

  @override
  String get lyricsUnavailable => 'No lyric file for this song';

  @override
  String get searchLyrics => 'Search lyrics';

  @override
  String get equalizerUnavailable => 'Equalizer is not available here';

  @override
  String get equalizerUnavailableBody =>
      'The equalizer needs an audio-effects channel. AVPlayer on iOS and macOS, and Media Foundation on Windows, do not expose one, so it currently works on Android only.';

  @override
  String get equalizerHint => 'Adjust the tone for every source';

  @override
  String get unavailableOnPlatform => 'Not available on this platform';

  @override
  String get gainDb => 'Gain (dB)';

  @override
  String get enableEqualizerToAdjust => 'Turn the equalizer on to adjust';

  @override
  String get bandsPending =>
      'Player not connected. Showing a typical 5-band layout until playback starts.';

  @override
  String get localMusicSettings => 'Local music';

  @override
  String get rescan => 'Scan again';

  @override
  String get noLocalSongs =>
      'No local songs yet\\nAdd a folder, or wait for downloads to be scanned';

  @override
  String get localLibraryTitle => 'On this device';

  @override
  String get folderPickerHint => 'Add opens the system folder picker';

  @override
  String get androidMediaStore => 'Android MediaStore · scanned first';

  @override
  String get writeTags => 'Write tags (experimental)';

  @override
  String get writeTagsHint =>
      'Write title, artist, album, and artwork into the file. Needs file access.';

  @override
  String get pickFolderFailed => 'Could not choose a music folder';

  @override
  String get chooseMusicFolder => 'Choose a music folder';

  @override
  String get chooseFolderFailed => 'Could not choose a folder';

  @override
  String get safImporting => 'Importing the music folder…';

  @override
  String get scanAndroidFailed => 'Could not scan the Android music folder';

  @override
  String get mediaStoreScanning =>
      'Scanning local music with Android MediaStore…';

  @override
  String get mediaStoreEmpty => 'MediaStore returned no audio';

  @override
  String get tryingAllFiles =>
      'MediaStore is unavailable. Trying all-files access…';

  @override
  String get openingSaf =>
      'All-files access is unavailable. Opening folder access…';

  @override
  String get androidAccessDenied => 'Android music access was not granted';

  @override
  String get androidAuthFailed => 'Android music access failed';

  @override
  String get matchingOnline => 'Matching online songs…';

  @override
  String get scanFailed => 'Scan failed';

  @override
  String get noLocalSources => 'No local music folders yet';

  @override
  String get rescanning => 'Scanning local music again…';

  @override
  String get rescanFailed => 'Could not scan again';

  @override
  String get noWritableSongs => 'No local songs to write';

  @override
  String get writingTags => 'Writing tags back to the files…';

  @override
  String get noTagsToWrite => 'No tags to write back';

  @override
  String get writeTagsFailed => 'Could not write tags';

  @override
  String get folderRemoved => 'Folder removed';

  @override
  String get downloadsTitle => 'Downloads';

  @override
  String get deleteFinishedDownloads => 'Delete finished downloads';

  @override
  String get clearFailedTasks => 'Clear failed downloads';

  @override
  String get noDownloadTasks => 'No downloads';

  @override
  String get noTasks => 'Nothing here';

  @override
  String get downloadSpeed => 'Speed';

  @override
  String get downloaded => 'Downloaded';

  @override
  String get linkExpired => 'Link expired. Download failed.';

  @override
  String get deleteFiles => 'Delete files';

  @override
  String get clearFailedAction => 'Clear';

  @override
  String get listeningStatsEmpty => 'No listening data yet';

  @override
  String get listeningStatsEmptyHint =>
      'Play a few songs and a report will show up here';

  @override
  String get playCount => 'Plays';

  @override
  String get listenTime => 'Time';

  @override
  String get activeDays => 'Active days';

  @override
  String get trackCount => 'Tracks';

  @override
  String get dailyPlays => 'Daily plays';

  @override
  String get songs => 'Songs';

  @override
  String get artists => 'Artists';

  @override
  String get albums => 'Albums';

  @override
  String get noData => 'No data';

  @override
  String get loadFailed => 'Could not load';

  @override
  String get noDuplicateFavorites => 'No duplicate songs in Favorites';

  @override
  String get selectRecommended => 'Select suggested';

  @override
  String get working => 'Working…';

  @override
  String get removeSelected => 'Remove selected';

  @override
  String get removeGroupSelected => 'Remove selected in this group';

  @override
  String get keepSuggested => 'Keep';

  @override
  String get hasLyricsMark => ' · Lyrics';

  @override
  String get addedToPlaylist => 'Added to playlist';

  @override
  String get playlistCreatedAndAdded => 'Playlist created';

  @override
  String get collapseNewPlaylist => 'Hide new playlist';

  @override
  String get newPlaylistName => 'New playlist name';

  @override
  String get basedOnFavorites => 'Based on music you like';

  @override
  String get noRecommendations => 'No recommendations yet';

  @override
  String get recommendationsNeedFavorites =>
      'After Favorites reaches 100 songs, 30 are picked at random';

  @override
  String get playlistEmpty => 'This playlist is empty';

  @override
  String get playlistEmptyNas => 'This playlist is empty';

  @override
  String get connectionSettings => 'Connection';

  @override
  String get scraping => 'Matching';

  @override
  String get scrapeArtworkLyrics => 'Match artwork and lyrics';

  @override
  String get goConnect => 'Connect';

  @override
  String get noOnlineMatch => 'No online artwork or lyrics matched';

  @override
  String get welcome => 'Welcome to Koyze';

  @override
  String get welcomeBody =>
      'Sign in to sync favorites, playlists, settings, and custom sources across devices.';

  @override
  String get serverAddress => 'Server address';

  @override
  String get syncUsernameHint => 'Account name';

  @override
  String get syncPasswordHint => 'Account password';

  @override
  String get registerAndSync => 'Create account and sync';

  @override
  String get loginAndSync => 'Log in and sync';

  @override
  String get backToLogin => 'I already have an account';

  @override
  String get needAccount => 'Need an account? Register';

  @override
  String get skipStep => 'Skip for now';

  @override
  String get skipStepHint =>
      'You can still play locally. Add an account later in Settings → Sync.';

  @override
  String get fillServerLogin => 'Enter the server, username, and password';

  @override
  String get loginFailed => 'Could not log in';

  @override
  String get syncTitle => 'Sync';

  @override
  String get syncAccount => 'Sync account';

  @override
  String get workersServer => 'Workers server';

  @override
  String get workersUnset => 'Not set (for example https://xxx.workers.dev)';

  @override
  String get notLoggedIn => 'Not signed in';

  @override
  String get loginToSync => 'Sign in to sync cloud playlists';

  @override
  String get syncing => 'Syncing…';

  @override
  String get syncExplainer =>
      'Search and playback stay on this device. The cloud keeps your account, playlists, settings, and sources.';

  @override
  String get eventSync => 'Sync changes';

  @override
  String get syncNow => 'Sync now';

  @override
  String get mergingEvents => 'Merging changes from this device and the cloud…';

  @override
  String get syncDoesNotOverwrite =>
      'Uploads local changes and downloads other devices. Nothing is overwritten.';

  @override
  String get offlineUntilNetwork =>
      'Saved on this device. Syncs when the network returns.';

  @override
  String get logOut => 'Log out';

  @override
  String get logOutHint =>
      'Favorites, playlists, ratings, history, downloads, and cache stay. Only the login is cleared.';

  @override
  String get loggedOut => 'Logged out';

  @override
  String get userAdmin => 'Users (admin)';

  @override
  String get userAdminHint => 'Create, delete, or reset passwords';

  @override
  String get workersAddress => 'Workers address';

  @override
  String get serverReachable => 'Server is reachable';

  @override
  String get savedHealthFailed =>
      'Saved, but the health check failed. Try again after deploy.';

  @override
  String get httpsRequired => 'The server address must use HTTPS';

  @override
  String get enterServerFirst => 'Enter the server address first';

  @override
  String get loginSucceeded => 'Signed in';

  @override
  String get failed => 'Failed';

  @override
  String get syncFinished => 'Sync finished';

  @override
  String get userList => 'Users';

  @override
  String get newUser => 'New user';

  @override
  String get userCreated => 'User created';

  @override
  String get customSourcesTitle => 'Custom sources';

  @override
  String get importLocalScript => 'Import a script file';

  @override
  String get importFromLink => 'Import from a link';

  @override
  String get addManually => 'Add manually';

  @override
  String get pasteScript => 'Paste a script';

  @override
  String get noCustomSources => 'No custom sources';

  @override
  String get addCustomSourceHint =>
      'Koyze ships no audio source. Use + to import and enable one before playing online songs.';

  @override
  String get importScriptOk => 'Script imported';

  @override
  String get importScriptBad => 'Import failed. The script format is wrong.';

  @override
  String get addCustomSource => 'Add a custom source';

  @override
  String get sourceName => 'Name';

  @override
  String get author => 'Author';

  @override
  String get script => 'Script';

  @override
  String get editCustomSource => 'Edit custom source';

  @override
  String get httpsLinkRequired => 'Enter a valid HTTPS link';

  @override
  String get importOk => 'Imported';

  @override
  String get importLinkBad => 'Import failed. Check the link or the script.';

  @override
  String get directDownloadHint => 'Paste a direct link to the script file';

  @override
  String get clipboardEmpty => 'The clipboard has no link';

  @override
  String get clipboard => 'Clipboard';

  @override
  String get importCustomSource => 'Import a custom source';

  @override
  String get lxScriptHint => 'LX Music scripts are supported';

  @override
  String get pasteScriptHint => 'Paste an LX Music script or JSON…';

  @override
  String get importFormatBad => 'Import failed. Check the script format.';

  @override
  String get exportCustomSource => 'Export custom source';

  @override
  String get deleteCustomSource => 'Delete custom source';

  @override
  String get logCopied => 'Log copied';

  @override
  String get noLog => 'No log yet';

  @override
  String get copyLog => 'Copy log';

  @override
  String get enterUsername => 'Enter a username';

  @override
  String get enterPassword => 'Enter a password';

  @override
  String get enterPasswordOrToken => 'Enter a password or X-Plex-Token';

  @override
  String get connectFailed => 'Could not connect';

  @override
  String get nasServerTitle => 'NAS music server';

  @override
  String get usernameOptional => 'Username (optional)';

  @override
  String get plexAccountHint => 'plex.tv account. Leave empty to use a token.';

  @override
  String get serverLoginName => 'Server username';

  @override
  String get passwordOrToken => 'Password / token';

  @override
  String get passwordSaved => 'Saved. Enter it again only when reconnecting.';

  @override
  String get passwordOrPlexToken => 'Password or X-Plex-Token';

  @override
  String get serverPassword => 'Server password';

  @override
  String get webDavRootPath => 'Root folder';

  @override
  String get webDavRootPathHint => '/music';

  @override
  String get webDavAuthMethod => 'Authentication';

  @override
  String get webDavBasicAuth => 'Username / password';

  @override
  String get webDavBearerAuth => 'Bearer token';

  @override
  String get webDavTokenHint => 'Paste an access token';

  @override
  String get webDavRootPathInvalid =>
      'Root folder must be a path such as /music';

  @override
  String get webDavScanFailed => 'WebDAV library scan failed';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get legacyAuth => 'Legacy sign-in';

  @override
  String get legacyAuthHint =>
      'Only if token sign-in fails. The password is sent as plain text.';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get minimize => 'Minimize';

  @override
  String get copyAll => 'Copy all';

  @override
  String get closeDiagnostics => 'Close diagnostics';

  @override
  String get clearMemoryLog => 'Clear log';

  @override
  String get diagnosticsHint =>
      'Kept in memory for this run only. Closing or restarting the app clears it.';

  @override
  String get stoppedAfterRepeatedFailures =>
      'Five songs failed in a row. Autoplay stopped.';

  @override
  String get autoplayNextFailed =>
      'Could not play the next song. Open Koyze and try again.';

  @override
  String get reloadingSong => 'Playback failed. Reloading.';

  @override
  String get tryingNextSong => 'Playback failed. Trying the next song.';

  @override
  String backupExported(String path) {
    return 'Backup saved to $path';
  }

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String cacheClearedRetained(int count) {
    return 'Cache cleared. $count songs still in use were kept.';
  }

  @override
  String clearFailed(String error) {
    return 'Could not clear cache: $error';
  }

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String stopsInMinutes(int count) {
    return 'Playback stops in $count min';
  }

  @override
  String playAction(String mode, String target) {
    return '$mode $target';
  }

  @override
  String recommendedSongs(int count) {
    return '$count songs for you';
  }

  @override
  String songCount(int count) {
    return '$count songs';
  }

  @override
  String loadingHost(String host) {
    return 'Loading $host';
  }

  @override
  String actionFailed(String action, String error) {
    return '$action failed: $error';
  }

  @override
  String failedWith(String label, String error) {
    return '$label: $error';
  }

  @override
  String nowPlayingNamed(String name) {
    return 'Playing $name';
  }

  @override
  String playNamed(String name) {
    return 'Play $name';
  }

  @override
  String chartCount(int count) {
    return '$count charts';
  }

  @override
  String hiddenUntil(String name) {
    return 'Hidden until you turn on “$name”';
  }

  @override
  String songsHeader(int count) {
    return 'Songs ($count)';
  }

  @override
  String playlistsHeader(int count) {
    return 'Playlists ($count)';
  }

  @override
  String importProgress(int loaded, int total) {
    return '$loaded/$total';
  }

  @override
  String confirmImport(int count) {
    return 'Import all $count songs into a local playlist?';
  }

  @override
  String importedFrom(String source) {
    return 'Imported from $source';
  }

  @override
  String importedResult(String name, int count) {
    return 'Imported “$name”, $count songs';
  }

  @override
  String parsingProgress(String progress) {
    return 'Reading $progress';
  }

  @override
  String addedToFavorites(int count) {
    return 'Added $count to Favorites';
  }

  @override
  String searchFailed(String error) {
    return 'Search failed: $error';
  }

  @override
  String searchEmptyTitle(String query) {
    return 'Nothing for \"$query\"';
  }

  @override
  String localArtist(String singer) {
    return '$singer · Local';
  }

  @override
  String queueTitle(int count) {
    return 'Queue ($count)';
  }

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String playlistTitleCount(String name, int count) {
    return '$name ($count)';
  }

  @override
  String favoritedSongs(int count) {
    return 'Added $count songs to Favorites';
  }

  @override
  String queuedDownloads(int count) {
    return 'Added $count songs to downloads';
  }

  @override
  String unfavoritedSongs(int count) {
    return 'Removed $count songs from Favorites';
  }

  @override
  String clearFavoritesBody(int count) {
    return 'Remove $count songs from Favorites. This cannot be undone, and it does not delete the original files or playlist songs.';
  }

  @override
  String deletePlaylistConfirm(String name) {
    return 'Delete “$name”?';
  }

  @override
  String pagePosition(int page, int count) {
    return 'Page $page / $count';
  }

  @override
  String startupFailedHint(String error) {
    return 'Open Koyze again. If this keeps happening, check Diagnostics in Settings.\\n$error';
  }

  @override
  String bandsReady(int count, String range) {
    return 'Device bands: $count ($range)';
  }

  @override
  String localSongCount(int count) {
    return '$count local songs\\nPlay them from Playlists > Local music';
  }

  @override
  String mediaStoreHint(int count) {
    return 'MediaStore can rescan. $count folders saved';
  }

  @override
  String downloadFolder(String path) {
    return 'Downloads · added automatically\\n$path';
  }

  @override
  String importingCount(int done, int total) {
    return 'Importing $done / $total';
  }

  @override
  String mediaStoreImporting(int done, int total) {
    return 'MediaStore $done / $total';
  }

  @override
  String allFilesScanning(int done, int total) {
    return 'Scanning $done / $total';
  }

  @override
  String scanningPath(String path) {
    return 'Scanning $path…';
  }

  @override
  String readingMetadata(int done, int total) {
    return 'Reading tags $done / $total';
  }

  @override
  String scrapingCount(int done, int total) {
    return 'Matching $done / $total';
  }

  @override
  String localUpdated(int count) {
    return 'Local music updated ($count songs)';
  }

  @override
  String writingTagsCount(int done, int total) {
    return 'Writing tags $done / $total';
  }

  @override
  String tagsWritten(int written, int attempted) {
    return 'Tags written: $written / $attempted';
  }

  @override
  String activeHeader(int count) {
    return 'Active ($count)';
  }

  @override
  String finishedHeader(int count) {
    return 'Finished ($count)';
  }

  @override
  String downloadingPercent(String percent) {
    return 'Downloading $percent%';
  }

  @override
  String pausedPercent(String singer, String percent) {
    return '$singer · Paused $percent%';
  }

  @override
  String deleteFinishedBody(int count) {
    return 'Delete $count finished downloads and their audio files? This cannot be undone.';
  }

  @override
  String clearFailedBody(int count) {
    return 'Delete $count failed downloads and leftover files?';
  }

  @override
  String dailyPeak(int days, int maxCount) {
    return '$days days · peak $maxCount';
  }

  @override
  String statSubtitle(String subtitle, int count) {
    return '$subtitle · $count plays';
  }

  @override
  String duplicateGroup(String artist, int count) {
    return '$artist · $count versions · select the ones to remove';
  }

  @override
  String removedDuplicates(int count) {
    return 'Removed $count duplicates';
  }

  @override
  String playlistSongCount(int count) {
    return '$count songs';
  }

  @override
  String recommendUpdated(int count) {
    return '$count songs · keeps updating';
  }

  @override
  String scrapingProgress(int done, int total) {
    return 'Matching $done / $total';
  }

  @override
  String notConnected(String name) {
    return '$name is not connected';
  }

  @override
  String connectedHost(String host) {
    return 'Connected to $host';
  }

  @override
  String matchedSongs(int matched, int total) {
    return 'Matched artwork and lyrics for $matched / $total songs';
  }

  @override
  String scrapeFailed(String error) {
    return 'Match failed: $error';
  }

  @override
  String nasPlaylistTitle(String name) {
    return '$name playlist';
  }

  @override
  String loggedInAs(String name) {
    return 'Signed in: $name';
  }

  @override
  String roleLine(String role) {
    return 'Role: $role';
  }

  @override
  String deviceLine(String id) {
    return 'Device: $id';
  }

  @override
  String timeLine(String time) {
    return 'Time: $time';
  }

  @override
  String syncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String adminUser(String id) {
    return 'Admin · id=$id';
  }

  @override
  String normalUser(String id) {
    return 'User · id=$id';
  }

  @override
  String deleteUser(String name) {
    return 'Delete $name';
  }

  @override
  String deletedUser(String name) {
    return 'Deleted $name';
  }

  @override
  String usersLoadFailed(String error) {
    return 'Could not load users: $error';
  }

  @override
  String sourceInitFailed(String name) {
    return '$name failed to start. Check the script.';
  }

  @override
  String importScriptFailed(String reason) {
    return 'Script import failed: $reason';
  }

  @override
  String readFileFailed(String error) {
    return 'Could not read the file: $error';
  }

  @override
  String deleteSourceConfirm(String name) {
    return 'Delete “$name”?';
  }

  @override
  String sourceLogTitle(String name) {
    return '$name log';
  }

  @override
  String disconnected(String name) {
    return 'Disconnected from $name';
  }

  @override
  String diagnosticsCount(int count) {
    return 'Log $count';
  }

  @override
  String playingQuoted(String name) {
    return 'Playing “$name”';
  }

  @override
  String unresolvedUrl(String title) {
    return 'Could not resolve “$title”. The source had no playable address, or the local cache failed.';
  }

  @override
  String playSongFailed(String title, String error) {
    return 'Could not play “$title”: $error';
  }

  @override
  String get quickTitle_theme => 'Theme';

  @override
  String get quickTitle_search => 'Search';

  @override
  String get quickTitle_playlists => 'Playlists';

  @override
  String get quickTitle_settings => 'App settings';

  @override
  String get quickTitle_sync => 'Cloud sync';

  @override
  String get quickTitle_local_scan => 'Scan device';

  @override
  String get quickTitle_leaderboard_settings => 'Chart settings';

  @override
  String get quickSubtitle_recommend => 'Based on what you play';

  @override
  String get quickSubtitle_local => 'Songs on this device';

  @override
  String get quickSubtitle_downloads => 'Tasks and progress';

  @override
  String get quickSubtitle_stats => 'Week, month, and year';

  @override
  String get quickSubtitle_sleep_timer => 'Stop playback on a timer';

  @override
  String get quickSubtitle_theme => 'Dark or light';

  @override
  String get quickSubtitle_favorites => 'Songs you saved';

  @override
  String get quickSubtitle_recent => 'Pick up where you left off';

  @override
  String get quickSubtitle_leaderboard => 'Popular songs';

  @override
  String get quickSubtitle_search => 'Find music quickly';

  @override
  String get quickSubtitle_playlists => 'Organize your playlists';

  @override
  String get quickSubtitle_settings => 'Quality, downloads, appearance';

  @override
  String get quickSubtitle_custom_source => 'Manage music sources';

  @override
  String get quickSubtitle_sync => 'Sync favorites and playlists';

  @override
  String get quickSubtitle_local_scan => 'Scan music on this device';

  @override
  String get quickSubtitle_leaderboard_settings => 'Choose which charts show';

  @override
  String get quickSubtitle_audio_quality => 'Default playback quality';

  @override
  String get quickSubtitle_download_quality => 'Default download quality';

  @override
  String get quickSubtitle_default_search => 'Where search starts';

  @override
  String get quickSubtitle_backup => 'Export playlists and settings';

  @override
  String get quickSubtitle_restore => 'Restore from a backup file';

  @override
  String get quickSubtitle_clear_cache => 'Free playback and artwork cache';

  @override
  String get quickSubtitle_diagnostic_log => 'Live runtime log';

  @override
  String get platformName_qq => 'QQ Music';

  @override
  String get platformName_tx => 'QQ Music';

  @override
  String get platformName_kw => 'Kuwo';

  @override
  String get platformName_wy => 'NetEase';

  @override
  String get platformName_kg => 'Kugou';

  @override
  String get qualityText_flac24bit => 'Master';

  @override
  String get qualityText_flac => 'Lossless';

  @override
  String get platformText_tx => 'QQ Music';

  @override
  String get platformText_kw => 'Kuwo';

  @override
  String get platformText_wy => 'NetEase';

  @override
  String get platformText_kg => 'Kugou';

  @override
  String get platformText_mg => 'Migu';

  @override
  String get platformText_audiostation => 'Unknown';

  @override
  String get presetName_flat => 'Flat';

  @override
  String get presetName_pop => 'Pop';

  @override
  String get presetName_rock => 'Rock';

  @override
  String get presetName_jazz => 'Jazz';

  @override
  String get presetName_classical => 'Classical';

  @override
  String get presetName_electronic => 'Electronic';

  @override
  String get presetName_folk => 'Folk';

  @override
  String get presetName_vocal => 'Vocal';

  @override
  String get presetName_bass => 'Bass boost';

  @override
  String get presetName_treble => 'Treble boost';

  @override
  String get connectedType_default => 'Connected to \$type';

  @override
  String get connectedType_default_2 => 'Connected to \$type \$version';

  @override
  String get currentConnection_default => 'Current: \$title · \$host';

  @override
  String get currentConnection_default_2 =>
      'Current: \$title · \$host · \$username';

  @override
  String get playlistLinkExample =>
      'Example: https://y.qq.com/n/ryqq/playlist/123\nKugou: https://www.kugou.com/yy/special/single/547134.html\nor a numeric ID';

  @override
  String get sourceCheckTitle => 'Source check';

  @override
  String get sourceCheckSubtitle =>
      'Test whether each script can fetch a playable URL';

  @override
  String get sourceCheckIntro =>
      'Each script runs against a fixed sample song: one URL request per declared quality, then a partial download to confirm it really returns audio. The result feeds playback source selection.';

  @override
  String get sourceCheckStart => 'Run check';

  @override
  String get sourceCheckPreparing => 'Preparing…';

  @override
  String sourceCheckRunning(String current) {
    return 'Testing: $current';
  }

  @override
  String sourceCheckProgress(int done, int total) {
    return '$done/$total';
  }

  @override
  String get sourceCheckAffectsSelection =>
      'Hard failures are skipped when picking a source; timeouts only move to the back.';

  @override
  String get sourceCheckCancelled => 'Cancelled. Partial results are kept.';

  @override
  String get sourceCheckNeverRun => 'Not tested yet';

  @override
  String get sourceCheckTesting => 'Testing…';

  @override
  String sourceCheckSummary(int ok, int total, String time) {
    return '$ok/$total platforms usable · $time';
  }

  @override
  String get sourceCheckDefaultQuality => 'Default quality';

  @override
  String get sourceCheckColdStart => 'cold start';

  @override
  String get sourceCheckNoSources => 'No source scripts yet. Import one first.';

  @override
  String sourceCheckSkipped(String platforms) {
    return 'No sample song for: $platforms';
  }

  @override
  String get sourceCheckDisabledBadge => 'Disabled';

  @override
  String get aiSettingsTitle => 'AI settings';

  @override
  String get aiSettingsIntro =>
      'Works with any OpenAI-compatible endpoint. The key goes into the system secure storage and is only sent to the URL you enter here.';

  @override
  String get aiBaseUrl => 'API base URL';

  @override
  String get aiBaseUrlHint => 'https://api.deepseek.com/v1';

  @override
  String get aiModel => 'Model';

  @override
  String get aiModelHint => 'deepseek-chat';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiApiKeyHint => 'sk-...';

  @override
  String get aiApiKeyStoredHint => 'Saved — leave blank to keep it';

  @override
  String get aiTestConnection => 'Test connection';

  @override
  String get aiTesting => 'Testing…';

  @override
  String get aiTestOk => 'Connection works';

  @override
  String get aiConfigSaved => 'AI settings saved';

  @override
  String get aiConfigInvalid =>
      'Fill a valid http(s) URL, a model and a key first';

  @override
  String get aiErrorNotConfigured => 'AI is not configured yet';

  @override
  String get aiErrorUnauthorized => 'Key rejected — check the API key';

  @override
  String get aiErrorNotFound => 'Endpoint or model not found';

  @override
  String get aiErrorRateLimited => 'Rate limited — try again later';

  @override
  String get aiErrorServer => 'The AI service returned an error';

  @override
  String get aiErrorTimeout => 'Request timed out';

  @override
  String get aiErrorNetwork => 'Network unavailable';

  @override
  String get aiErrorEmpty => 'The model returned nothing';

  @override
  String get aiErrorBadResponse => 'Could not parse the model output';

  @override
  String get aiOpenTitle => 'AI playlist';

  @override
  String get aiOpenSubtitle => 'Describe it in one sentence';

  @override
  String get aiPlaylistTitle => 'AI playlist';

  @override
  String get aiPromptLabel => 'What kind of playlist?';

  @override
  String get aiPromptHint => 'Late-night coding, instrumental, nothing loud';

  @override
  String get aiGenerate => 'Generate';

  @override
  String get aiGenerating => 'Generating…';

  @override
  String aiMatching(int index, int total) {
    return 'Matching $index/$total';
  }

  @override
  String aiMatchedCount(int matched, int total) {
    return '$matched of $total songs found';
  }

  @override
  String get aiCreatePlaylist => 'Create playlist';

  @override
  String aiCreated(String name) {
    return 'Playlist \"$name\" created';
  }

  @override
  String get aiNotConfigured => 'Configure the AI endpoint first';

  @override
  String get aiEmptyResult => 'No usable songs came back';

  @override
  String aiSongUnmatched(String name) {
    return 'Not found: $name';
  }

  @override
  String get aiSettingsSubtitle => 'Endpoint, key and model';
}
