import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @charts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get charts;

  /// No description provided for @playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get playlists;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @cloudAccount.
  ///
  /// In en, this message translates to:
  /// **'Cloud account'**
  String get cloudAccount;

  /// No description provided for @cloudAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites, playlists, settings, and custom sources'**
  String get cloudAccountSubtitle;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @localLibrary.
  ///
  /// In en, this message translates to:
  /// **'Local music folders'**
  String get localLibrary;

  /// No description provided for @localLibrarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose folders, rescan, and match songs online'**
  String get localLibrarySubtitle;

  /// No description provided for @customSources.
  ///
  /// In en, this message translates to:
  /// **'Custom sources'**
  String get customSources;

  /// No description provided for @customSourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage custom music sources'**
  String get customSourcesSubtitle;

  /// No description provided for @nasServer.
  ///
  /// In en, this message translates to:
  /// **'NAS music server'**
  String get nasServer;

  /// No description provided for @sourcesAndLibrary.
  ///
  /// In en, this message translates to:
  /// **'Sources & library'**
  String get sourcesAndLibrary;

  /// No description provided for @playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get playback;

  /// No description provided for @audioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get audioQuality;

  /// No description provided for @chooseQuality.
  ///
  /// In en, this message translates to:
  /// **'Choose quality'**
  String get chooseQuality;

  /// No description provided for @equalizer.
  ///
  /// In en, this message translates to:
  /// **'Equalizer'**
  String get equalizer;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @sleepTimerCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer cancelled'**
  String get sleepTimerCancelled;

  /// No description provided for @autoResume.
  ///
  /// In en, this message translates to:
  /// **'Resume on launch'**
  String get autoResume;

  /// No description provided for @autoResumeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Continue the last song when the app opens'**
  String get autoResumeSubtitle;

  /// No description provided for @floatingPlayer.
  ///
  /// In en, this message translates to:
  /// **'Floating player'**
  String get floatingPlayer;

  /// No description provided for @floatingPlayerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show cover, lyrics, progress, and playback controls over other apps'**
  String get floatingPlayerSubtitle;

  /// No description provided for @floatingPlayerPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow display over other apps, then return to Koyze'**
  String get floatingPlayerPermission;

  /// No description provided for @forceLandscape.
  ///
  /// In en, this message translates to:
  /// **'Force landscape'**
  String get forceLandscape;

  /// No description provided for @forceLandscapeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the landscape layout. Phones also stay in landscape'**
  String get forceLandscapeSubtitle;

  /// No description provided for @simplifyEffects.
  ///
  /// In en, this message translates to:
  /// **'Reduce effects'**
  String get simplifyEffects;

  /// No description provided for @simplifyEffectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off frosted glass, transparency, and motion. On by default at 4GB or less'**
  String get simplifyEffectsSubtitle;

  /// No description provided for @defaultSearchPlatform.
  ///
  /// In en, this message translates to:
  /// **'Default search source'**
  String get defaultSearchPlatform;

  /// No description provided for @listeningStats.
  ///
  /// In en, this message translates to:
  /// **'Listening stats'**
  String get listeningStats;

  /// No description provided for @listeningStatsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'History, rankings, and activity'**
  String get listeningStatsSubtitle;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @darkModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the dark theme'**
  String get darkModeSubtitle;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @followSystemThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match the system light or dark theme'**
  String get followSystemThemeSubtitle;

  /// No description provided for @followSystemLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the device language when it is Chinese or English'**
  String get followSystemLanguageSubtitle;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme colour'**
  String get themeColor;

  /// No description provided for @themeColorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One accent builds the whole Material 3 palette'**
  String get themeColorSubtitle;

  /// No description provided for @playerBackdrop.
  ///
  /// In en, this message translates to:
  /// **'Player background'**
  String get playerBackdrop;

  /// No description provided for @playerBackdropSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cover blur and dimming'**
  String get playerBackdropSubtitle;

  /// No description provided for @playerBackdropBlur.
  ///
  /// In en, this message translates to:
  /// **'Background blur'**
  String get playerBackdropBlur;

  /// No description provided for @playerBackdropScrim.
  ///
  /// In en, this message translates to:
  /// **'Scrim opacity'**
  String get playerBackdropScrim;

  /// No description provided for @playerBackdropPreviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get playerBackdropPreviewEmpty;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @downloadManager.
  ///
  /// In en, this message translates to:
  /// **'Download manager'**
  String get downloadManager;

  /// No description provided for @downloadManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and manage download tasks'**
  String get downloadManagerSubtitle;

  /// No description provided for @wifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi only'**
  String get wifiOnly;

  /// No description provided for @wifiOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download songs only on Wi-Fi'**
  String get wifiOnlySubtitle;

  /// No description provided for @downloadQuality.
  ///
  /// In en, this message translates to:
  /// **'Download quality'**
  String get downloadQuality;

  /// No description provided for @chooseDownloadQuality.
  ///
  /// In en, this message translates to:
  /// **'Choose download quality'**
  String get chooseDownloadQuality;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @dataAndSync.
  ///
  /// In en, this message translates to:
  /// **'Data & sync'**
  String get dataAndSync;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get backup;

  /// No description provided for @backupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export playlists and settings to a file'**
  String get backupSubtitle;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup file'**
  String get restoreSubtitle;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get clearCache;

  /// No description provided for @clearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear playback cache, artwork, and temporary files'**
  String get clearCacheSubtitle;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @deviceUuid.
  ///
  /// In en, this message translates to:
  /// **'Device UUID'**
  String get deviceUuid;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @deviceUuidCopied.
  ///
  /// In en, this message translates to:
  /// **'Device UUID copied'**
  String get deviceUuidCopied;

  /// No description provided for @diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Live diagnostics'**
  String get diagnostics;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start recording when opened. Keeps recording while minimized.'**
  String get diagnosticsSubtitle;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @addedToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Added to the download queue'**
  String get addedToDownloads;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add download'**
  String get downloadFailed;

  /// No description provided for @exportBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Koyze backup'**
  String get exportBackupTitle;

  /// No description provided for @restoreSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Restore complete'**
  String get restoreSucceeded;

  /// No description provided for @chooseCache.
  ///
  /// In en, this message translates to:
  /// **'Choose what to clear'**
  String get chooseCache;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @playbackCache.
  ///
  /// In en, this message translates to:
  /// **'Playback cache'**
  String get playbackCache;

  /// No description provided for @playbackCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cached songs. Manual downloads are not included.'**
  String get playbackCacheSubtitle;

  /// No description provided for @artworkCache.
  ///
  /// In en, this message translates to:
  /// **'Artwork cache'**
  String get artworkCache;

  /// No description provided for @artworkCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Album art stored on disk and in memory'**
  String get artworkCacheSubtitle;

  /// No description provided for @tempFiles.
  ///
  /// In en, this message translates to:
  /// **'Temporary files'**
  String get tempFiles;

  /// No description provided for @tempFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Intermediate files in the system temp folder'**
  String get tempFilesSubtitle;

  /// No description provided for @cacheKeepNote.
  ///
  /// In en, this message translates to:
  /// **'Manual downloads stay. A song that is playing keeps its cache.'**
  String get cacheKeepNote;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Selected cache cleared'**
  String get cacheCleared;

  /// No description provided for @cancelSleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Cancel sleep timer'**
  String get cancelSleepTimer;

  /// No description provided for @chineseInterface.
  ///
  /// In en, this message translates to:
  /// **'Chinese interface'**
  String get chineseInterface;

  /// No description provided for @englishInterface.
  ///
  /// In en, this message translates to:
  /// **'English interface'**
  String get englishInterface;

  /// No description provided for @shortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcuts;

  /// No description provided for @shortcutSettings.
  ///
  /// In en, this message translates to:
  /// **'Shortcut settings'**
  String get shortcutSettings;

  /// No description provided for @closeShortcutSettings.
  ///
  /// In en, this message translates to:
  /// **'Close shortcut settings'**
  String get closeShortcutSettings;

  /// No description provided for @searchSongsHint.
  ///
  /// In en, this message translates to:
  /// **'Songs, artists, playlists...'**
  String get searchSongsHint;

  /// No description provided for @heroCardSettings.
  ///
  /// In en, this message translates to:
  /// **'Home card'**
  String get heroCardSettings;

  /// No description provided for @heroCardSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Home card settings'**
  String get heroCardSettingsAction;

  /// No description provided for @closeHeroCardSettings.
  ///
  /// In en, this message translates to:
  /// **'Close home card settings'**
  String get closeHeroCardSettings;

  /// No description provided for @heroCardHint.
  ///
  /// In en, this message translates to:
  /// **'Same five cards as Playlists. Only one can be on.'**
  String get heroCardHint;

  /// No description provided for @heroPlayMode.
  ///
  /// In en, this message translates to:
  /// **'Play button mode'**
  String get heroPlayMode;

  /// No description provided for @heroPlayModeHint.
  ///
  /// In en, this message translates to:
  /// **'Only this card\'s button. The player mode stays separate.'**
  String get heroPlayModeHint;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @forYou.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get forYou;

  /// No description provided for @localMusic.
  ///
  /// In en, this message translates to:
  /// **'Local music'**
  String get localMusic;

  /// No description provided for @nasLibrary.
  ///
  /// In en, this message translates to:
  /// **'NAS library'**
  String get nasLibrary;

  /// No description provided for @recentPlays.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get recentPlays;

  /// No description provided for @playInOrder.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get playInOrder;

  /// No description provided for @shufflePlay.
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get shufflePlay;

  /// No description provided for @repeatOne.
  ///
  /// In en, this message translates to:
  /// **'Repeat one'**
  String get repeatOne;

  /// No description provided for @playInOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Play the list in order, then start over'**
  String get playInOrderHint;

  /// No description provided for @shufflePlayHint.
  ///
  /// In en, this message translates to:
  /// **'Shuffle, then keep picking at random'**
  String get shufflePlayHint;

  /// No description provided for @repeatOneHint.
  ///
  /// In en, this message translates to:
  /// **'Repeat the current song'**
  String get repeatOneHint;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @recommendAfterFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorite songs to get recommendations'**
  String get recommendAfterFavorites;

  /// No description provided for @heroRecentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing played yet'**
  String get heroRecentEmpty;

  /// No description provided for @chooseFolderToScan.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder to scan this device'**
  String get chooseFolderToScan;

  /// No description provided for @nasHosts.
  ///
  /// In en, this message translates to:
  /// **'Navidrome / Emby / Plex / Synology'**
  String get nasHosts;

  /// No description provided for @loadSongsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load songs'**
  String get loadSongsFailed;

  /// No description provided for @playFailed.
  ///
  /// In en, this message translates to:
  /// **'Playback failed'**
  String get playFailed;

  /// No description provided for @noSongsOnServer.
  ///
  /// In en, this message translates to:
  /// **'No songs on the server yet'**
  String get noSongsOnServer;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @otherPlatform.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherPlatform;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'Picks'**
  String get featured;

  /// No description provided for @noChartData.
  ///
  /// In en, this message translates to:
  /// **'No chart data'**
  String get noChartData;

  /// No description provided for @chartsHidden.
  ///
  /// In en, this message translates to:
  /// **'Every chart is hidden\\nTurn them back on from the top right'**
  String get chartsHidden;

  /// No description provided for @chartSettings.
  ///
  /// In en, this message translates to:
  /// **'Chart settings'**
  String get chartSettings;

  /// No description provided for @refreshCharts.
  ///
  /// In en, this message translates to:
  /// **'Refresh charts'**
  String get refreshCharts;

  /// No description provided for @noSongData.
  ///
  /// In en, this message translates to:
  /// **'No songs'**
  String get noSongData;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @defaultFirst.
  ///
  /// In en, this message translates to:
  /// **'Shown first'**
  String get defaultFirst;

  /// No description provided for @importPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Import playlist'**
  String get importPlaylist;

  /// No description provided for @newPlaylist.
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get newPlaylist;

  /// No description provided for @searchLibraryHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs or playlists'**
  String get searchLibraryHint;

  /// No description provided for @clearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// No description provided for @clearResults.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearResults;

  /// No description provided for @customPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Custom playlists'**
  String get customPlaylists;

  /// No description provided for @sortPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Sort playlists'**
  String get sortPlaylists;

  /// No description provided for @nothingMatched.
  ///
  /// In en, this message translates to:
  /// **'No matching songs or playlists'**
  String get nothingMatched;

  /// No description provided for @createPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create playlist'**
  String get createPlaylist;

  /// No description provided for @playlistName.
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get playlistName;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @editPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Edit playlist'**
  String get editPlaylist;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get recentlyAdded;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortByName;

  /// No description provided for @sortByCount.
  ///
  /// In en, this message translates to:
  /// **'Song count'**
  String get sortByCount;

  /// No description provided for @pastePlaylistLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a share link or playlist ID'**
  String get pastePlaylistLink;

  /// No description provided for @closeImport.
  ///
  /// In en, this message translates to:
  /// **'Close import'**
  String get closeImport;

  /// No description provided for @sourcePlatform.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourcePlatform;

  /// No description provided for @kuwoShort.
  ///
  /// In en, this message translates to:
  /// **'Kuwo'**
  String get kuwoShort;

  /// No description provided for @kugouShort.
  ///
  /// In en, this message translates to:
  /// **'Kugou'**
  String get kugouShort;

  /// No description provided for @neteaseShort.
  ///
  /// In en, this message translates to:
  /// **'NetEase'**
  String get neteaseShort;

  /// No description provided for @playlistLinkOrId.
  ///
  /// In en, this message translates to:
  /// **'Link or ID'**
  String get playlistLinkOrId;

  /// No description provided for @enterLinkOrId.
  ///
  /// In en, this message translates to:
  /// **'Enter a link or ID'**
  String get enterLinkOrId;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @parsingPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Reading playlist…'**
  String get parsingPlaylist;

  /// No description provided for @parsePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Read playlist'**
  String get parsePlaylist;

  /// No description provided for @addAllToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add all to Favorites'**
  String get addAllToFavorites;

  /// No description provided for @addFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not add'**
  String get addFailed;

  /// No description provided for @alreadyInFavorites.
  ///
  /// In en, this message translates to:
  /// **'Those songs are already in Favorites'**
  String get alreadyInFavorites;

  /// No description provided for @deletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get deletePlaylist;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete'**
  String get deleteFailed;

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create'**
  String get createFailed;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save'**
  String get saveFailed;

  /// No description provided for @choosePlatform.
  ///
  /// In en, this message translates to:
  /// **'Choose a source'**
  String get choosePlatform;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get platform;

  /// No description provided for @searchFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Songs, playlists...'**
  String get searchFieldHint;

  /// No description provided for @searchAction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchAction;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @searchEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Try another keyword, or switch sources.'**
  String get searchEmptyHint;

  /// No description provided for @searchErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Search unavailable'**
  String get searchErrorTitle;

  /// No description provided for @searchAllSources.
  ///
  /// In en, this message translates to:
  /// **'Search all sources'**
  String get searchAllSources;

  /// No description provided for @onlineMusic.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineMusic;

  /// No description provided for @slideForMore.
  ///
  /// In en, this message translates to:
  /// **'Scroll for more'**
  String get slideForMore;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// No description provided for @searchHistory.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchHistory;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearHistory;

  /// No description provided for @hotSearch.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get hotSearch;

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingEllipsis;

  /// No description provided for @playNow.
  ///
  /// In en, this message translates to:
  /// **'Play now'**
  String get playNow;

  /// No description provided for @addToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get addToPlaylist;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get unfavorite;

  /// No description provided for @favoriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not favorite'**
  String get favoriteFailed;

  /// No description provided for @playbackProgress.
  ///
  /// In en, this message translates to:
  /// **'Playback progress'**
  String get playbackProgress;

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlaying;

  /// No description provided for @unknownQuality.
  ///
  /// In en, this message translates to:
  /// **'Unknown quality'**
  String get unknownQuality;

  /// No description provided for @resolvingQuality.
  ///
  /// In en, this message translates to:
  /// **'Resolving…'**
  String get resolvingQuality;

  /// No description provided for @collapsePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get collapsePlayer;

  /// No description provided for @backToArtwork.
  ///
  /// In en, this message translates to:
  /// **'Back to artwork'**
  String get backToArtwork;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @lyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get lyrics;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @openLyrics.
  ///
  /// In en, this message translates to:
  /// **'Open lyrics'**
  String get openLyrics;

  /// No description provided for @playMode.
  ///
  /// In en, this message translates to:
  /// **'Play mode'**
  String get playMode;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @queue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queue;

  /// No description provided for @dislikeAndSkip.
  ///
  /// In en, this message translates to:
  /// **'Dislike and skip'**
  String get dislikeAndSkip;

  /// No description provided for @dislikedNote.
  ///
  /// In en, this message translates to:
  /// **'Marked as disliked. It will be skipped next time.'**
  String get dislikedNote;

  /// No description provided for @dislikeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not mark dislike'**
  String get dislikeFailed;

  /// No description provided for @queueLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Full list failed. Showing the current queue.'**
  String get queueLoadFailed;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get queueEmpty;

  /// No description provided for @playlistMissing.
  ///
  /// In en, this message translates to:
  /// **'Playlist not found'**
  String get playlistMissing;

  /// No description provided for @exitMultiSelect.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get exitMultiSelect;

  /// No description provided for @cancelEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel edit'**
  String get cancelEdit;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @downloadSelected.
  ///
  /// In en, this message translates to:
  /// **'Download selected'**
  String get downloadSelected;

  /// No description provided for @unfavoriteSelected.
  ///
  /// In en, this message translates to:
  /// **'Remove selected from Favorites'**
  String get unfavoriteSelected;

  /// No description provided for @playAll.
  ///
  /// In en, this message translates to:
  /// **'Play all'**
  String get playAll;

  /// No description provided for @alreadyFavorited.
  ///
  /// In en, this message translates to:
  /// **'Already in Favorites'**
  String get alreadyFavorited;

  /// No description provided for @actionFailedShort.
  ///
  /// In en, this message translates to:
  /// **'Action failed'**
  String get actionFailedShort;

  /// No description provided for @favoriteAll.
  ///
  /// In en, this message translates to:
  /// **'Favorite all'**
  String get favoriteAll;

  /// No description provided for @editInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit details'**
  String get editInfo;

  /// No description provided for @manualSort.
  ///
  /// In en, this message translates to:
  /// **'Manual order'**
  String get manualSort;

  /// No description provided for @sortByTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort by title'**
  String get sortByTitle;

  /// No description provided for @sortByArtist.
  ///
  /// In en, this message translates to:
  /// **'Sort by artist'**
  String get sortByArtist;

  /// No description provided for @sortByDuration.
  ///
  /// In en, this message translates to:
  /// **'Sort by duration'**
  String get sortByDuration;

  /// No description provided for @duplicateSongs.
  ///
  /// In en, this message translates to:
  /// **'Duplicate songs'**
  String get duplicateSongs;

  /// No description provided for @clearFavorites.
  ///
  /// In en, this message translates to:
  /// **'Clear favorites'**
  String get clearFavorites;

  /// No description provided for @noSongs.
  ///
  /// In en, this message translates to:
  /// **'No songs'**
  String get noSongs;

  /// No description provided for @locateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not find the song'**
  String get locateFailed;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @removeFromPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get removeFromPlaylist;

  /// No description provided for @removeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove'**
  String get removeFailed;

  /// No description provided for @nothingSelectedToDownload.
  ///
  /// In en, this message translates to:
  /// **'No selected songs to download'**
  String get nothingSelectedToDownload;

  /// No description provided for @nothingSelectedToUnfavorite.
  ///
  /// In en, this message translates to:
  /// **'No selected songs to remove from Favorites'**
  String get nothingSelectedToUnfavorite;

  /// No description provided for @unfavoriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove from Favorites'**
  String get unfavoriteFailed;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @clearFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear favorites?'**
  String get clearFavoritesTitle;

  /// No description provided for @confirmClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get confirmClear;

  /// No description provided for @favoritesAlreadyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Favorites is already empty'**
  String get favoritesAlreadyEmpty;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @log.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get log;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @customPreset.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customPreset;

  /// No description provided for @presets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presets;

  /// No description provided for @pauseAll.
  ///
  /// In en, this message translates to:
  /// **'Pause all'**
  String get pauseAll;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait…'**
  String get pleaseWait;

  /// No description provided for @notice.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get notice;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @dismissNotification.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismissNotification;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @notPlaying.
  ///
  /// In en, this message translates to:
  /// **'Not playing'**
  String get notPlaying;

  /// No description provided for @noLyrics.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get noLyrics;

  /// No description provided for @openNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Open Now Playing'**
  String get openNowPlaying;

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @choosePage.
  ///
  /// In en, this message translates to:
  /// **'Choose page'**
  String get choosePage;

  /// No description provided for @preparingApp.
  ///
  /// In en, this message translates to:
  /// **'Preparing Koyze'**
  String get preparingApp;

  /// No description provided for @startupFailed.
  ///
  /// In en, this message translates to:
  /// **'Koyze could not start'**
  String get startupFailed;

  /// No description provided for @startupLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your library and player…'**
  String get startupLoading;

  /// No description provided for @retryStartup.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryStartup;

  /// No description provided for @lyricsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics'**
  String get lyricsLoading;

  /// No description provided for @fetchingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Fetching lyrics'**
  String get fetchingLyrics;

  /// No description provided for @lyricsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load lyrics'**
  String get lyricsFailed;

  /// No description provided for @checkNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check the connection and try again'**
  String get checkNetwork;

  /// No description provided for @lyricsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No lyrics'**
  String get lyricsEmpty;

  /// No description provided for @lyricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No lyric file for this song'**
  String get lyricsUnavailable;

  /// No description provided for @searchLyrics.
  ///
  /// In en, this message translates to:
  /// **'Search lyrics'**
  String get searchLyrics;

  /// No description provided for @equalizerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Equalizer is not available here'**
  String get equalizerUnavailable;

  /// No description provided for @equalizerUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'The equalizer needs an audio-effects channel. AVPlayer on iOS and macOS, and Media Foundation on Windows, do not expose one, so it currently works on Android only.'**
  String get equalizerUnavailableBody;

  /// No description provided for @equalizerHint.
  ///
  /// In en, this message translates to:
  /// **'Adjust the tone for every source'**
  String get equalizerHint;

  /// No description provided for @unavailableOnPlatform.
  ///
  /// In en, this message translates to:
  /// **'Not available on this platform'**
  String get unavailableOnPlatform;

  /// No description provided for @gainDb.
  ///
  /// In en, this message translates to:
  /// **'Gain (dB)'**
  String get gainDb;

  /// No description provided for @enableEqualizerToAdjust.
  ///
  /// In en, this message translates to:
  /// **'Turn the equalizer on to adjust'**
  String get enableEqualizerToAdjust;

  /// No description provided for @bandsPending.
  ///
  /// In en, this message translates to:
  /// **'Player not connected. Showing a typical 5-band layout until playback starts.'**
  String get bandsPending;

  /// No description provided for @localMusicSettings.
  ///
  /// In en, this message translates to:
  /// **'Local music'**
  String get localMusicSettings;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get rescan;

  /// No description provided for @noLocalSongs.
  ///
  /// In en, this message translates to:
  /// **'No local songs yet\\nAdd a folder, or wait for downloads to be scanned'**
  String get noLocalSongs;

  /// No description provided for @localLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'On this device'**
  String get localLibraryTitle;

  /// No description provided for @folderPickerHint.
  ///
  /// In en, this message translates to:
  /// **'Add opens the system folder picker'**
  String get folderPickerHint;

  /// No description provided for @androidMediaStore.
  ///
  /// In en, this message translates to:
  /// **'Android MediaStore · scanned first'**
  String get androidMediaStore;

  /// No description provided for @writeTags.
  ///
  /// In en, this message translates to:
  /// **'Write tags (experimental)'**
  String get writeTags;

  /// No description provided for @writeTagsHint.
  ///
  /// In en, this message translates to:
  /// **'Write title, artist, album, and artwork into the file. Needs file access.'**
  String get writeTagsHint;

  /// No description provided for @pickFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not choose a music folder'**
  String get pickFolderFailed;

  /// No description provided for @chooseMusicFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose a music folder'**
  String get chooseMusicFolder;

  /// No description provided for @chooseFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not choose a folder'**
  String get chooseFolderFailed;

  /// No description provided for @safImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing the music folder…'**
  String get safImporting;

  /// No description provided for @scanAndroidFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not scan the Android music folder'**
  String get scanAndroidFailed;

  /// No description provided for @mediaStoreScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning local music with Android MediaStore…'**
  String get mediaStoreScanning;

  /// No description provided for @mediaStoreEmpty.
  ///
  /// In en, this message translates to:
  /// **'MediaStore returned no audio'**
  String get mediaStoreEmpty;

  /// No description provided for @tryingAllFiles.
  ///
  /// In en, this message translates to:
  /// **'MediaStore is unavailable. Trying all-files access…'**
  String get tryingAllFiles;

  /// No description provided for @openingSaf.
  ///
  /// In en, this message translates to:
  /// **'All-files access is unavailable. Opening folder access…'**
  String get openingSaf;

  /// No description provided for @androidAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Android music access was not granted'**
  String get androidAccessDenied;

  /// No description provided for @androidAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Android music access failed'**
  String get androidAuthFailed;

  /// No description provided for @matchingOnline.
  ///
  /// In en, this message translates to:
  /// **'Matching online songs…'**
  String get matchingOnline;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get scanFailed;

  /// No description provided for @noLocalSources.
  ///
  /// In en, this message translates to:
  /// **'No local music folders yet'**
  String get noLocalSources;

  /// No description provided for @rescanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning local music again…'**
  String get rescanning;

  /// No description provided for @rescanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not scan again'**
  String get rescanFailed;

  /// No description provided for @noWritableSongs.
  ///
  /// In en, this message translates to:
  /// **'No local songs to write'**
  String get noWritableSongs;

  /// No description provided for @writingTags.
  ///
  /// In en, this message translates to:
  /// **'Writing tags back to the files…'**
  String get writingTags;

  /// No description provided for @noTagsToWrite.
  ///
  /// In en, this message translates to:
  /// **'No tags to write back'**
  String get noTagsToWrite;

  /// No description provided for @writeTagsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write tags'**
  String get writeTagsFailed;

  /// No description provided for @folderRemoved.
  ///
  /// In en, this message translates to:
  /// **'Folder removed'**
  String get folderRemoved;

  /// No description provided for @downloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsTitle;

  /// No description provided for @deleteFinishedDownloads.
  ///
  /// In en, this message translates to:
  /// **'Delete finished downloads'**
  String get deleteFinishedDownloads;

  /// No description provided for @clearFailedTasks.
  ///
  /// In en, this message translates to:
  /// **'Clear failed downloads'**
  String get clearFailedTasks;

  /// No description provided for @noDownloadTasks.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get noDownloadTasks;

  /// No description provided for @noTasks.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get noTasks;

  /// No description provided for @downloadSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get downloadSpeed;

  /// No description provided for @downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// No description provided for @linkExpired.
  ///
  /// In en, this message translates to:
  /// **'Link expired. Download failed.'**
  String get linkExpired;

  /// No description provided for @deleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Delete files'**
  String get deleteFiles;

  /// No description provided for @clearFailedAction.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearFailedAction;

  /// No description provided for @listeningStatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No listening data yet'**
  String get listeningStatsEmpty;

  /// No description provided for @listeningStatsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Play a few songs and a report will show up here'**
  String get listeningStatsEmptyHint;

  /// No description provided for @playCount.
  ///
  /// In en, this message translates to:
  /// **'Plays'**
  String get playCount;

  /// No description provided for @listenTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get listenTime;

  /// No description provided for @activeDays.
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get activeDays;

  /// No description provided for @trackCount.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get trackCount;

  /// No description provided for @dailyPlays.
  ///
  /// In en, this message translates to:
  /// **'Daily plays'**
  String get dailyPlays;

  /// No description provided for @songs.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get songs;

  /// No description provided for @artists.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get artists;

  /// No description provided for @albums.
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get albums;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load'**
  String get loadFailed;

  /// No description provided for @noDuplicateFavorites.
  ///
  /// In en, this message translates to:
  /// **'No duplicate songs in Favorites'**
  String get noDuplicateFavorites;

  /// No description provided for @selectRecommended.
  ///
  /// In en, this message translates to:
  /// **'Select suggested'**
  String get selectRecommended;

  /// No description provided for @working.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get working;

  /// No description provided for @removeSelected.
  ///
  /// In en, this message translates to:
  /// **'Remove selected'**
  String get removeSelected;

  /// No description provided for @removeGroupSelected.
  ///
  /// In en, this message translates to:
  /// **'Remove selected in this group'**
  String get removeGroupSelected;

  /// No description provided for @keepSuggested.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keepSuggested;

  /// No description provided for @hasLyricsMark.
  ///
  /// In en, this message translates to:
  /// **' · Lyrics'**
  String get hasLyricsMark;

  /// No description provided for @addedToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Added to playlist'**
  String get addedToPlaylist;

  /// No description provided for @playlistCreatedAndAdded.
  ///
  /// In en, this message translates to:
  /// **'Playlist created'**
  String get playlistCreatedAndAdded;

  /// No description provided for @collapseNewPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Hide new playlist'**
  String get collapseNewPlaylist;

  /// No description provided for @newPlaylistName.
  ///
  /// In en, this message translates to:
  /// **'New playlist name'**
  String get newPlaylistName;

  /// No description provided for @basedOnFavorites.
  ///
  /// In en, this message translates to:
  /// **'Based on music you like'**
  String get basedOnFavorites;

  /// No description provided for @noRecommendations.
  ///
  /// In en, this message translates to:
  /// **'No recommendations yet'**
  String get noRecommendations;

  /// No description provided for @recommendationsNeedFavorites.
  ///
  /// In en, this message translates to:
  /// **'After Favorites reaches 100 songs, 30 are picked at random'**
  String get recommendationsNeedFavorites;

  /// No description provided for @playlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get playlistEmpty;

  /// No description provided for @playlistEmptyNas.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get playlistEmptyNas;

  /// No description provided for @connectionSettings.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connectionSettings;

  /// No description provided for @scraping.
  ///
  /// In en, this message translates to:
  /// **'Matching'**
  String get scraping;

  /// No description provided for @scrapeArtworkLyrics.
  ///
  /// In en, this message translates to:
  /// **'Match artwork and lyrics'**
  String get scrapeArtworkLyrics;

  /// No description provided for @goConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get goConnect;

  /// No description provided for @noOnlineMatch.
  ///
  /// In en, this message translates to:
  /// **'No online artwork or lyrics matched'**
  String get noOnlineMatch;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Koyze'**
  String get welcome;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync favorites, playlists, settings, and custom sources across devices.'**
  String get welcomeBody;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @syncUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get syncUsernameHint;

  /// No description provided for @syncPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Account password'**
  String get syncPasswordHint;

  /// No description provided for @registerAndSync.
  ///
  /// In en, this message translates to:
  /// **'Create account and sync'**
  String get registerAndSync;

  /// No description provided for @loginAndSync.
  ///
  /// In en, this message translates to:
  /// **'Log in and sync'**
  String get loginAndSync;

  /// No description provided for @backToLogin.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get backToLogin;

  /// No description provided for @needAccount.
  ///
  /// In en, this message translates to:
  /// **'Need an account? Register'**
  String get needAccount;

  /// No description provided for @skipStep.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipStep;

  /// No description provided for @skipStepHint.
  ///
  /// In en, this message translates to:
  /// **'You can still play locally. Add an account later in Settings → Sync.'**
  String get skipStepHint;

  /// No description provided for @fillServerLogin.
  ///
  /// In en, this message translates to:
  /// **'Enter the server, username, and password'**
  String get fillServerLogin;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not log in'**
  String get loginFailed;

  /// No description provided for @syncTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get syncTitle;

  /// No description provided for @syncAccount.
  ///
  /// In en, this message translates to:
  /// **'Sync account'**
  String get syncAccount;

  /// No description provided for @workersServer.
  ///
  /// In en, this message translates to:
  /// **'Workers server'**
  String get workersServer;

  /// No description provided for @workersUnset.
  ///
  /// In en, this message translates to:
  /// **'Not set (for example https://xxx.workers.dev)'**
  String get workersUnset;

  /// No description provided for @notLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get notLoggedIn;

  /// No description provided for @loginToSync.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync cloud playlists'**
  String get loginToSync;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @syncExplainer.
  ///
  /// In en, this message translates to:
  /// **'Search and playback stay on this device. The cloud keeps your account, playlists, settings, and sources.'**
  String get syncExplainer;

  /// No description provided for @eventSync.
  ///
  /// In en, this message translates to:
  /// **'Sync changes'**
  String get eventSync;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @mergingEvents.
  ///
  /// In en, this message translates to:
  /// **'Merging changes from this device and the cloud…'**
  String get mergingEvents;

  /// No description provided for @syncDoesNotOverwrite.
  ///
  /// In en, this message translates to:
  /// **'Uploads local changes and downloads other devices. Nothing is overwritten.'**
  String get syncDoesNotOverwrite;

  /// No description provided for @offlineUntilNetwork.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device. Syncs when the network returns.'**
  String get offlineUntilNetwork;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @logOutHint.
  ///
  /// In en, this message translates to:
  /// **'Favorites, playlists, ratings, history, downloads, and cache stay. Only the login is cleared.'**
  String get logOutHint;

  /// No description provided for @loggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out'**
  String get loggedOut;

  /// No description provided for @userAdmin.
  ///
  /// In en, this message translates to:
  /// **'Users (admin)'**
  String get userAdmin;

  /// No description provided for @userAdminHint.
  ///
  /// In en, this message translates to:
  /// **'Create, delete, or reset passwords'**
  String get userAdminHint;

  /// No description provided for @workersAddress.
  ///
  /// In en, this message translates to:
  /// **'Workers address'**
  String get workersAddress;

  /// No description provided for @serverReachable.
  ///
  /// In en, this message translates to:
  /// **'Server is reachable'**
  String get serverReachable;

  /// No description provided for @savedHealthFailed.
  ///
  /// In en, this message translates to:
  /// **'Saved, but the health check failed. Try again after deploy.'**
  String get savedHealthFailed;

  /// No description provided for @httpsRequired.
  ///
  /// In en, this message translates to:
  /// **'The server address must use HTTPS'**
  String get httpsRequired;

  /// No description provided for @enterServerFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter the server address first'**
  String get enterServerFirst;

  /// No description provided for @loginSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get loginSucceeded;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @syncFinished.
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get syncFinished;

  /// No description provided for @userList.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get userList;

  /// No description provided for @newUser.
  ///
  /// In en, this message translates to:
  /// **'New user'**
  String get newUser;

  /// No description provided for @userCreated.
  ///
  /// In en, this message translates to:
  /// **'User created'**
  String get userCreated;

  /// No description provided for @customSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom sources'**
  String get customSourcesTitle;

  /// No description provided for @importLocalScript.
  ///
  /// In en, this message translates to:
  /// **'Import a script file'**
  String get importLocalScript;

  /// No description provided for @importFromLink.
  ///
  /// In en, this message translates to:
  /// **'Import from a link'**
  String get importFromLink;

  /// No description provided for @addManually.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addManually;

  /// No description provided for @pasteScript.
  ///
  /// In en, this message translates to:
  /// **'Paste a script'**
  String get pasteScript;

  /// No description provided for @noCustomSources.
  ///
  /// In en, this message translates to:
  /// **'No custom sources'**
  String get noCustomSources;

  /// No description provided for @addCustomSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Koyze ships no audio source. Use + to import and enable one before playing online songs.'**
  String get addCustomSourceHint;

  /// No description provided for @importScriptOk.
  ///
  /// In en, this message translates to:
  /// **'Script imported'**
  String get importScriptOk;

  /// No description provided for @importScriptBad.
  ///
  /// In en, this message translates to:
  /// **'Import failed. The script format is wrong.'**
  String get importScriptBad;

  /// No description provided for @addCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Add a custom source'**
  String get addCustomSource;

  /// No description provided for @sourceName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sourceName;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @script.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get script;

  /// No description provided for @editCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Edit custom source'**
  String get editCustomSource;

  /// No description provided for @httpsLinkRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid HTTPS link'**
  String get httpsLinkRequired;

  /// No description provided for @importOk.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importOk;

  /// No description provided for @importLinkBad.
  ///
  /// In en, this message translates to:
  /// **'Import failed. Check the link or the script.'**
  String get importLinkBad;

  /// No description provided for @directDownloadHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a direct link to the script file'**
  String get directDownloadHint;

  /// No description provided for @clipboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'The clipboard has no link'**
  String get clipboardEmpty;

  /// No description provided for @clipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get clipboard;

  /// No description provided for @importCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Import a custom source'**
  String get importCustomSource;

  /// No description provided for @lxScriptHint.
  ///
  /// In en, this message translates to:
  /// **'LX Music scripts are supported'**
  String get lxScriptHint;

  /// No description provided for @pasteScriptHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an LX Music script or JSON…'**
  String get pasteScriptHint;

  /// No description provided for @importFormatBad.
  ///
  /// In en, this message translates to:
  /// **'Import failed. Check the script format.'**
  String get importFormatBad;

  /// No description provided for @exportCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Export custom source'**
  String get exportCustomSource;

  /// No description provided for @deleteCustomSource.
  ///
  /// In en, this message translates to:
  /// **'Delete custom source'**
  String get deleteCustomSource;

  /// No description provided for @logCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied'**
  String get logCopied;

  /// No description provided for @noLog.
  ///
  /// In en, this message translates to:
  /// **'No log yet'**
  String get noLog;

  /// No description provided for @copyLog.
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get copyLog;

  /// No description provided for @enterUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter a username'**
  String get enterUsername;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter a password'**
  String get enterPassword;

  /// No description provided for @enterPasswordOrToken.
  ///
  /// In en, this message translates to:
  /// **'Enter a password or X-Plex-Token'**
  String get enterPasswordOrToken;

  /// No description provided for @connectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get connectFailed;

  /// No description provided for @nasServerTitle.
  ///
  /// In en, this message translates to:
  /// **'NAS music server'**
  String get nasServerTitle;

  /// No description provided for @usernameOptional.
  ///
  /// In en, this message translates to:
  /// **'Username (optional)'**
  String get usernameOptional;

  /// No description provided for @plexAccountHint.
  ///
  /// In en, this message translates to:
  /// **'plex.tv account. Leave empty to use a token.'**
  String get plexAccountHint;

  /// No description provided for @serverLoginName.
  ///
  /// In en, this message translates to:
  /// **'Server username'**
  String get serverLoginName;

  /// No description provided for @passwordOrToken.
  ///
  /// In en, this message translates to:
  /// **'Password / token'**
  String get passwordOrToken;

  /// No description provided for @passwordSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved. Enter it again only when reconnecting.'**
  String get passwordSaved;

  /// No description provided for @passwordOrPlexToken.
  ///
  /// In en, this message translates to:
  /// **'Password or X-Plex-Token'**
  String get passwordOrPlexToken;

  /// No description provided for @serverPassword.
  ///
  /// In en, this message translates to:
  /// **'Server password'**
  String get serverPassword;

  /// No description provided for @webDavRootPath.
  ///
  /// In en, this message translates to:
  /// **'Root folder'**
  String get webDavRootPath;

  /// No description provided for @webDavRootPathHint.
  ///
  /// In en, this message translates to:
  /// **'/music'**
  String get webDavRootPathHint;

  /// No description provided for @webDavAuthMethod.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get webDavAuthMethod;

  /// No description provided for @webDavBasicAuth.
  ///
  /// In en, this message translates to:
  /// **'Username / password'**
  String get webDavBasicAuth;

  /// No description provided for @webDavBearerAuth.
  ///
  /// In en, this message translates to:
  /// **'Bearer token'**
  String get webDavBearerAuth;

  /// No description provided for @webDavTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Paste an access token'**
  String get webDavTokenHint;

  /// No description provided for @webDavRootPathInvalid.
  ///
  /// In en, this message translates to:
  /// **'Root folder must be a path such as /music'**
  String get webDavRootPathInvalid;

  /// No description provided for @webDavScanFailed.
  ///
  /// In en, this message translates to:
  /// **'WebDAV library scan failed'**
  String get webDavScanFailed;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @legacyAuth.
  ///
  /// In en, this message translates to:
  /// **'Legacy sign-in'**
  String get legacyAuth;

  /// No description provided for @legacyAuthHint.
  ///
  /// In en, this message translates to:
  /// **'Only if token sign-in fails. The password is sent as plain text.'**
  String get legacyAuthHint;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @closeDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Close diagnostics'**
  String get closeDiagnostics;

  /// No description provided for @clearMemoryLog.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get clearMemoryLog;

  /// No description provided for @diagnosticsRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get diagnosticsRecording;

  /// No description provided for @diagnosticsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get diagnosticsFilterAll;

  /// No description provided for @diagnosticsFilterWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get diagnosticsFilterWarnings;

  /// No description provided for @diagnosticsFilterErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get diagnosticsFilterErrors;

  /// No description provided for @diagnosticsJumpLatest.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest'**
  String get diagnosticsJumpLatest;

  /// No description provided for @diagnosticsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Panel is open. New runtime events will show up here.'**
  String get diagnosticsEmptyHint;

  /// No description provided for @diagnosticsHint.
  ///
  /// In en, this message translates to:
  /// **'Records only while this panel is open. Kept in memory; cleared on restart.'**
  String get diagnosticsHint;

  /// No description provided for @stoppedAfterRepeatedFailures.
  ///
  /// In en, this message translates to:
  /// **'Five songs failed in a row. Autoplay stopped.'**
  String get stoppedAfterRepeatedFailures;

  /// No description provided for @autoplayNextFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play the next song. Open Koyze and try again.'**
  String get autoplayNextFailed;

  /// No description provided for @reloadingSong.
  ///
  /// In en, this message translates to:
  /// **'Playback failed. Reloading.'**
  String get reloadingSong;

  /// No description provided for @tryingNextSong.
  ///
  /// In en, this message translates to:
  /// **'Playback failed. Trying the next song.'**
  String get tryingNextSong;

  /// No description provided for @backupExported.
  ///
  /// In en, this message translates to:
  /// **'Backup saved to {path}'**
  String backupExported(String path);

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @cacheClearedRetained.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared. {count} songs still in use were kept.'**
  String cacheClearedRetained(int count);

  /// No description provided for @clearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear cache: {error}'**
  String clearFailed(String error);

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutes(int count);

  /// No description provided for @stopsInMinutes.
  ///
  /// In en, this message translates to:
  /// **'Playback stops in {count} min'**
  String stopsInMinutes(int count);

  /// No description provided for @playAction.
  ///
  /// In en, this message translates to:
  /// **'{mode} {target}'**
  String playAction(String mode, String target);

  /// No description provided for @recommendedSongs.
  ///
  /// In en, this message translates to:
  /// **'{count} songs for you'**
  String recommendedSongs(int count);

  /// No description provided for @songCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String songCount(int count);

  /// No description provided for @loadingHost.
  ///
  /// In en, this message translates to:
  /// **'Loading {host}'**
  String loadingHost(String host);

  /// No description provided for @actionFailed.
  ///
  /// In en, this message translates to:
  /// **'{action} failed: {error}'**
  String actionFailed(String action, String error);

  /// No description provided for @failedWith.
  ///
  /// In en, this message translates to:
  /// **'{label}: {error}'**
  String failedWith(String label, String error);

  /// No description provided for @nowPlayingNamed.
  ///
  /// In en, this message translates to:
  /// **'Playing {name}'**
  String nowPlayingNamed(String name);

  /// No description provided for @playNamed.
  ///
  /// In en, this message translates to:
  /// **'Play {name}'**
  String playNamed(String name);

  /// No description provided for @chartCount.
  ///
  /// In en, this message translates to:
  /// **'{count} charts'**
  String chartCount(int count);

  /// No description provided for @hiddenUntil.
  ///
  /// In en, this message translates to:
  /// **'Hidden until you turn on “{name}”'**
  String hiddenUntil(String name);

  /// No description provided for @songsHeader.
  ///
  /// In en, this message translates to:
  /// **'Songs ({count})'**
  String songsHeader(int count);

  /// No description provided for @playlistsHeader.
  ///
  /// In en, this message translates to:
  /// **'Playlists ({count})'**
  String playlistsHeader(int count);

  /// No description provided for @importProgress.
  ///
  /// In en, this message translates to:
  /// **'{loaded}/{total}'**
  String importProgress(int loaded, int total);

  /// No description provided for @confirmImport.
  ///
  /// In en, this message translates to:
  /// **'Import all {count} songs into a local playlist?'**
  String confirmImport(int count);

  /// No description provided for @importedFrom.
  ///
  /// In en, this message translates to:
  /// **'Imported from {source}'**
  String importedFrom(String source);

  /// No description provided for @importedResult.
  ///
  /// In en, this message translates to:
  /// **'Imported “{name}”, {count} songs'**
  String importedResult(String name, int count);

  /// No description provided for @parsingProgress.
  ///
  /// In en, this message translates to:
  /// **'Reading {progress}'**
  String parsingProgress(String progress);

  /// No description provided for @addedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Added {count} to Favorites'**
  String addedToFavorites(int count);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailed(String error);

  /// No description provided for @searchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing for \"{query}\"'**
  String searchEmptyTitle(String query);

  /// No description provided for @localArtist.
  ///
  /// In en, this message translates to:
  /// **'{singer} · Local'**
  String localArtist(String singer);

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue ({count})'**
  String queueTitle(int count);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @playlistTitleCount.
  ///
  /// In en, this message translates to:
  /// **'{name} ({count})'**
  String playlistTitleCount(String name, int count);

  /// No description provided for @favoritedSongs.
  ///
  /// In en, this message translates to:
  /// **'Added {count} songs to Favorites'**
  String favoritedSongs(int count);

  /// No description provided for @queuedDownloads.
  ///
  /// In en, this message translates to:
  /// **'Added {count} songs to downloads'**
  String queuedDownloads(int count);

  /// No description provided for @unfavoritedSongs.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} songs from Favorites'**
  String unfavoritedSongs(int count);

  /// No description provided for @clearFavoritesBody.
  ///
  /// In en, this message translates to:
  /// **'Remove {count} songs from Favorites. This cannot be undone, and it does not delete the original files or playlist songs.'**
  String clearFavoritesBody(int count);

  /// No description provided for @deletePlaylistConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deletePlaylistConfirm(String name);

  /// No description provided for @pagePosition.
  ///
  /// In en, this message translates to:
  /// **'Page {page} / {count}'**
  String pagePosition(int page, int count);

  /// No description provided for @startupFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Open Koyze again. If this keeps happening, check Diagnostics in Settings.\\n{error}'**
  String startupFailedHint(String error);

  /// No description provided for @bandsReady.
  ///
  /// In en, this message translates to:
  /// **'Device bands: {count} ({range})'**
  String bandsReady(int count, String range);

  /// No description provided for @localSongCount.
  ///
  /// In en, this message translates to:
  /// **'{count} local songs\\nPlay them from Playlists > Local music'**
  String localSongCount(int count);

  /// No description provided for @mediaStoreHint.
  ///
  /// In en, this message translates to:
  /// **'MediaStore can rescan. {count} folders saved'**
  String mediaStoreHint(int count);

  /// No description provided for @downloadFolder.
  ///
  /// In en, this message translates to:
  /// **'Downloads · added automatically\\n{path}'**
  String downloadFolder(String path);

  /// No description provided for @importingCount.
  ///
  /// In en, this message translates to:
  /// **'Importing {done} / {total}'**
  String importingCount(int done, int total);

  /// No description provided for @mediaStoreImporting.
  ///
  /// In en, this message translates to:
  /// **'MediaStore {done} / {total}'**
  String mediaStoreImporting(int done, int total);

  /// No description provided for @allFilesScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning {done} / {total}'**
  String allFilesScanning(int done, int total);

  /// No description provided for @scanningPath.
  ///
  /// In en, this message translates to:
  /// **'Scanning {path}…'**
  String scanningPath(String path);

  /// No description provided for @readingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Reading tags {done} / {total}'**
  String readingMetadata(int done, int total);

  /// No description provided for @scrapingCount.
  ///
  /// In en, this message translates to:
  /// **'Matching {done} / {total}'**
  String scrapingCount(int done, int total);

  /// No description provided for @localUpdated.
  ///
  /// In en, this message translates to:
  /// **'Local music updated ({count} songs)'**
  String localUpdated(int count);

  /// No description provided for @writingTagsCount.
  ///
  /// In en, this message translates to:
  /// **'Writing tags {done} / {total}'**
  String writingTagsCount(int done, int total);

  /// No description provided for @tagsWritten.
  ///
  /// In en, this message translates to:
  /// **'Tags written: {written} / {attempted}'**
  String tagsWritten(int written, int attempted);

  /// No description provided for @activeHeader.
  ///
  /// In en, this message translates to:
  /// **'Active ({count})'**
  String activeHeader(int count);

  /// No description provided for @finishedHeader.
  ///
  /// In en, this message translates to:
  /// **'Finished ({count})'**
  String finishedHeader(int count);

  /// No description provided for @downloadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String downloadingPercent(String percent);

  /// No description provided for @pausedPercent.
  ///
  /// In en, this message translates to:
  /// **'{singer} · Paused {percent}%'**
  String pausedPercent(String singer, String percent);

  /// No description provided for @deleteFinishedBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} finished downloads and their audio files? This cannot be undone.'**
  String deleteFinishedBody(int count);

  /// No description provided for @clearFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} failed downloads and leftover files?'**
  String clearFailedBody(int count);

  /// No description provided for @dailyPeak.
  ///
  /// In en, this message translates to:
  /// **'{days} days · peak {maxCount}'**
  String dailyPeak(int days, int maxCount);

  /// No description provided for @statSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{subtitle} · {count} plays'**
  String statSubtitle(String subtitle, int count);

  /// No description provided for @duplicateGroup.
  ///
  /// In en, this message translates to:
  /// **'{artist} · {count} versions · select the ones to remove'**
  String duplicateGroup(String artist, int count);

  /// No description provided for @removedDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Removed {count} duplicates'**
  String removedDuplicates(int count);

  /// No description provided for @playlistSongCount.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String playlistSongCount(int count);

  /// No description provided for @recommendUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count} songs · keeps updating'**
  String recommendUpdated(int count);

  /// No description provided for @scrapingProgress.
  ///
  /// In en, this message translates to:
  /// **'Matching {done} / {total}'**
  String scrapingProgress(int done, int total);

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'{name} is not connected'**
  String notConnected(String name);

  /// No description provided for @connectedHost.
  ///
  /// In en, this message translates to:
  /// **'Connected to {host}'**
  String connectedHost(String host);

  /// No description provided for @matchedSongs.
  ///
  /// In en, this message translates to:
  /// **'Matched artwork and lyrics for {matched} / {total} songs'**
  String matchedSongs(int matched, int total);

  /// No description provided for @scrapeFailed.
  ///
  /// In en, this message translates to:
  /// **'Match failed: {error}'**
  String scrapeFailed(String error);

  /// No description provided for @nasPlaylistTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} playlist'**
  String nasPlaylistTitle(String name);

  /// No description provided for @loggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in: {name}'**
  String loggedInAs(String name);

  /// No description provided for @roleLine.
  ///
  /// In en, this message translates to:
  /// **'Role: {role}'**
  String roleLine(String role);

  /// No description provided for @deviceLine.
  ///
  /// In en, this message translates to:
  /// **'Device: {id}'**
  String deviceLine(String id);

  /// No description provided for @timeLine.
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String timeLine(String time);

  /// No description provided for @syncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String syncFailed(String error);

  /// No description provided for @adminUser.
  ///
  /// In en, this message translates to:
  /// **'Admin · id={id}'**
  String adminUser(String id);

  /// No description provided for @normalUser.
  ///
  /// In en, this message translates to:
  /// **'User · id={id}'**
  String normalUser(String id);

  /// No description provided for @deleteUser.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}'**
  String deleteUser(String name);

  /// No description provided for @deletedUser.
  ///
  /// In en, this message translates to:
  /// **'Deleted {name}'**
  String deletedUser(String name);

  /// No description provided for @usersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load users: {error}'**
  String usersLoadFailed(String error);

  /// No description provided for @sourceInitFailed.
  ///
  /// In en, this message translates to:
  /// **'{name} failed to start. Check the script.'**
  String sourceInitFailed(String name);

  /// No description provided for @importScriptFailed.
  ///
  /// In en, this message translates to:
  /// **'Script import failed: {reason}'**
  String importScriptFailed(String reason);

  /// No description provided for @readFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the file: {error}'**
  String readFileFailed(String error);

  /// No description provided for @deleteSourceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String deleteSourceConfirm(String name);

  /// No description provided for @sourceLogTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} log'**
  String sourceLogTitle(String name);

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected from {name}'**
  String disconnected(String name);

  /// No description provided for @diagnosticsCount.
  ///
  /// In en, this message translates to:
  /// **'Log {count}'**
  String diagnosticsCount(int count);

  /// No description provided for @playingQuoted.
  ///
  /// In en, this message translates to:
  /// **'Playing “{name}”'**
  String playingQuoted(String name);

  /// No description provided for @unresolvedUrl.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve “{title}”. The source had no playable address, or the local cache failed.'**
  String unresolvedUrl(String title);

  /// No description provided for @playSongFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play “{title}”: {error}'**
  String playSongFailed(String title, String error);

  /// No description provided for @quickTitle_theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get quickTitle_theme;

  /// No description provided for @quickTitle_search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get quickTitle_search;

  /// No description provided for @quickTitle_playlists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get quickTitle_playlists;

  /// No description provided for @quickTitle_settings.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get quickTitle_settings;

  /// No description provided for @quickTitle_sync.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync'**
  String get quickTitle_sync;

  /// No description provided for @quickTitle_local_scan.
  ///
  /// In en, this message translates to:
  /// **'Scan device'**
  String get quickTitle_local_scan;

  /// No description provided for @quickTitle_leaderboard_settings.
  ///
  /// In en, this message translates to:
  /// **'Chart settings'**
  String get quickTitle_leaderboard_settings;

  /// No description provided for @quickSubtitle_recommend.
  ///
  /// In en, this message translates to:
  /// **'Based on what you play'**
  String get quickSubtitle_recommend;

  /// No description provided for @quickSubtitle_local.
  ///
  /// In en, this message translates to:
  /// **'Songs on this device'**
  String get quickSubtitle_local;

  /// No description provided for @quickSubtitle_downloads.
  ///
  /// In en, this message translates to:
  /// **'Tasks and progress'**
  String get quickSubtitle_downloads;

  /// No description provided for @quickSubtitle_stats.
  ///
  /// In en, this message translates to:
  /// **'Week, month, and year'**
  String get quickSubtitle_stats;

  /// No description provided for @quickSubtitle_sleep_timer.
  ///
  /// In en, this message translates to:
  /// **'Stop playback on a timer'**
  String get quickSubtitle_sleep_timer;

  /// No description provided for @quickSubtitle_theme.
  ///
  /// In en, this message translates to:
  /// **'Dark or light'**
  String get quickSubtitle_theme;

  /// No description provided for @quickSubtitle_favorites.
  ///
  /// In en, this message translates to:
  /// **'Songs you saved'**
  String get quickSubtitle_favorites;

  /// No description provided for @quickSubtitle_recent.
  ///
  /// In en, this message translates to:
  /// **'Pick up where you left off'**
  String get quickSubtitle_recent;

  /// No description provided for @quickSubtitle_leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Popular songs'**
  String get quickSubtitle_leaderboard;

  /// No description provided for @quickSubtitle_search.
  ///
  /// In en, this message translates to:
  /// **'Find music quickly'**
  String get quickSubtitle_search;

  /// No description provided for @quickSubtitle_playlists.
  ///
  /// In en, this message translates to:
  /// **'Organize your playlists'**
  String get quickSubtitle_playlists;

  /// No description provided for @quickSubtitle_settings.
  ///
  /// In en, this message translates to:
  /// **'Quality, downloads, appearance'**
  String get quickSubtitle_settings;

  /// No description provided for @quickSubtitle_custom_source.
  ///
  /// In en, this message translates to:
  /// **'Manage music sources'**
  String get quickSubtitle_custom_source;

  /// No description provided for @quickSubtitle_sync.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites and playlists'**
  String get quickSubtitle_sync;

  /// No description provided for @quickSubtitle_local_scan.
  ///
  /// In en, this message translates to:
  /// **'Scan music on this device'**
  String get quickSubtitle_local_scan;

  /// No description provided for @quickSubtitle_leaderboard_settings.
  ///
  /// In en, this message translates to:
  /// **'Choose which charts show'**
  String get quickSubtitle_leaderboard_settings;

  /// No description provided for @quickSubtitle_audio_quality.
  ///
  /// In en, this message translates to:
  /// **'Default playback quality'**
  String get quickSubtitle_audio_quality;

  /// No description provided for @quickSubtitle_download_quality.
  ///
  /// In en, this message translates to:
  /// **'Default download quality'**
  String get quickSubtitle_download_quality;

  /// No description provided for @quickSubtitle_default_search.
  ///
  /// In en, this message translates to:
  /// **'Where search starts'**
  String get quickSubtitle_default_search;

  /// No description provided for @quickSubtitle_backup.
  ///
  /// In en, this message translates to:
  /// **'Export playlists and settings'**
  String get quickSubtitle_backup;

  /// No description provided for @quickSubtitle_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup file'**
  String get quickSubtitle_restore;

  /// No description provided for @quickSubtitle_clear_cache.
  ///
  /// In en, this message translates to:
  /// **'Free playback and artwork cache'**
  String get quickSubtitle_clear_cache;

  /// No description provided for @quickSubtitle_diagnostic_log.
  ///
  /// In en, this message translates to:
  /// **'Live runtime log'**
  String get quickSubtitle_diagnostic_log;

  /// No description provided for @platformName_qq.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get platformName_qq;

  /// No description provided for @platformName_tx.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get platformName_tx;

  /// No description provided for @platformName_kw.
  ///
  /// In en, this message translates to:
  /// **'Kuwo'**
  String get platformName_kw;

  /// No description provided for @platformName_wy.
  ///
  /// In en, this message translates to:
  /// **'NetEase'**
  String get platformName_wy;

  /// No description provided for @platformName_kg.
  ///
  /// In en, this message translates to:
  /// **'Kugou'**
  String get platformName_kg;

  /// No description provided for @qualityText_flac24bit.
  ///
  /// In en, this message translates to:
  /// **'Master'**
  String get qualityText_flac24bit;

  /// No description provided for @qualityText_flac.
  ///
  /// In en, this message translates to:
  /// **'Lossless'**
  String get qualityText_flac;

  /// No description provided for @platformText_tx.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get platformText_tx;

  /// No description provided for @platformText_kw.
  ///
  /// In en, this message translates to:
  /// **'Kuwo'**
  String get platformText_kw;

  /// No description provided for @platformText_wy.
  ///
  /// In en, this message translates to:
  /// **'NetEase'**
  String get platformText_wy;

  /// No description provided for @platformText_kg.
  ///
  /// In en, this message translates to:
  /// **'Kugou'**
  String get platformText_kg;

  /// No description provided for @platformText_mg.
  ///
  /// In en, this message translates to:
  /// **'Migu'**
  String get platformText_mg;

  /// No description provided for @platformText_audiostation.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get platformText_audiostation;

  /// No description provided for @presetName_flat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get presetName_flat;

  /// No description provided for @presetName_pop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get presetName_pop;

  /// No description provided for @presetName_rock.
  ///
  /// In en, this message translates to:
  /// **'Rock'**
  String get presetName_rock;

  /// No description provided for @presetName_jazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get presetName_jazz;

  /// No description provided for @presetName_classical.
  ///
  /// In en, this message translates to:
  /// **'Classical'**
  String get presetName_classical;

  /// No description provided for @presetName_electronic.
  ///
  /// In en, this message translates to:
  /// **'Electronic'**
  String get presetName_electronic;

  /// No description provided for @presetName_folk.
  ///
  /// In en, this message translates to:
  /// **'Folk'**
  String get presetName_folk;

  /// No description provided for @presetName_vocal.
  ///
  /// In en, this message translates to:
  /// **'Vocal'**
  String get presetName_vocal;

  /// No description provided for @presetName_bass.
  ///
  /// In en, this message translates to:
  /// **'Bass boost'**
  String get presetName_bass;

  /// No description provided for @presetName_treble.
  ///
  /// In en, this message translates to:
  /// **'Treble boost'**
  String get presetName_treble;

  /// No description provided for @connectedType_default.
  ///
  /// In en, this message translates to:
  /// **'Connected to \$type'**
  String get connectedType_default;

  /// No description provided for @connectedType_default_2.
  ///
  /// In en, this message translates to:
  /// **'Connected to \$type \$version'**
  String get connectedType_default_2;

  /// No description provided for @currentConnection_default.
  ///
  /// In en, this message translates to:
  /// **'Current: \$title · \$host'**
  String get currentConnection_default;

  /// No description provided for @currentConnection_default_2.
  ///
  /// In en, this message translates to:
  /// **'Current: \$title · \$host · \$username'**
  String get currentConnection_default_2;

  /// No description provided for @playlistLinkExample.
  ///
  /// In en, this message translates to:
  /// **'Example: https://y.qq.com/n/ryqq/playlist/123\nKugou: https://www.kugou.com/yy/special/single/547134.html\nor a numeric ID'**
  String get playlistLinkExample;

  /// No description provided for @sourceCheckTitle.
  ///
  /// In en, this message translates to:
  /// **'Source check'**
  String get sourceCheckTitle;

  /// No description provided for @sourceCheckStart.
  ///
  /// In en, this message translates to:
  /// **'Run check'**
  String get sourceCheckStart;

  /// No description provided for @sourceCheckNeverRun.
  ///
  /// In en, this message translates to:
  /// **'Not tested'**
  String get sourceCheckNeverRun;

  /// No description provided for @sourceCheckTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get sourceCheckTesting;

  /// No description provided for @sourceCheckRerun.
  ///
  /// In en, this message translates to:
  /// **'Re-test'**
  String get sourceCheckRerun;

  /// No description provided for @sourceCheckSummary.
  ///
  /// In en, this message translates to:
  /// **'{ok}/{total} platforms usable · {time}'**
  String sourceCheckSummary(int ok, int total, String time);

  /// No description provided for @aiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI settings'**
  String get aiSettingsTitle;

  /// No description provided for @aiSettingsIntro.
  ///
  /// In en, this message translates to:
  /// **'Works with any OpenAI-compatible endpoint. The key goes into the system secure storage and is only sent to the URL you enter here.'**
  String get aiSettingsIntro;

  /// No description provided for @aiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get aiBaseUrl;

  /// No description provided for @aiBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://api.deepseek.com/v1'**
  String get aiBaseUrlHint;

  /// No description provided for @aiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModel;

  /// No description provided for @aiModelHint.
  ///
  /// In en, this message translates to:
  /// **'deepseek-chat'**
  String get aiModelHint;

  /// No description provided for @aiApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiApiKey;

  /// No description provided for @aiApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'sk-...'**
  String get aiApiKeyHint;

  /// No description provided for @aiApiKeyStoredHint.
  ///
  /// In en, this message translates to:
  /// **'Saved — leave blank to keep it'**
  String get aiApiKeyStoredHint;

  /// No description provided for @aiTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get aiTestConnection;

  /// No description provided for @aiTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get aiTesting;

  /// No description provided for @aiTestOk.
  ///
  /// In en, this message translates to:
  /// **'Connection works'**
  String get aiTestOk;

  /// No description provided for @aiTestingVoice.
  ///
  /// In en, this message translates to:
  /// **'Testing voice…'**
  String get aiTestingVoice;

  /// No description provided for @aiConfigSaved.
  ///
  /// In en, this message translates to:
  /// **'AI settings saved'**
  String get aiConfigSaved;

  /// No description provided for @aiConfigInvalid.
  ///
  /// In en, this message translates to:
  /// **'Fill a valid http(s) URL, a model and a key first'**
  String get aiConfigInvalid;

  /// No description provided for @aiErrorNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'AI is not configured yet'**
  String get aiErrorNotConfigured;

  /// No description provided for @aiErrorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Key rejected — check the API key'**
  String get aiErrorUnauthorized;

  /// No description provided for @aiErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Endpoint or model not found'**
  String get aiErrorNotFound;

  /// No description provided for @aiErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Rate limited — try again later'**
  String get aiErrorRateLimited;

  /// No description provided for @aiErrorServer.
  ///
  /// In en, this message translates to:
  /// **'The AI service returned an error'**
  String get aiErrorServer;

  /// No description provided for @aiErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out'**
  String get aiErrorTimeout;

  /// No description provided for @aiErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable'**
  String get aiErrorNetwork;

  /// No description provided for @aiErrorEmpty.
  ///
  /// In en, this message translates to:
  /// **'The model returned nothing'**
  String get aiErrorEmpty;

  /// No description provided for @aiErrorBadResponse.
  ///
  /// In en, this message translates to:
  /// **'Could not parse the model output'**
  String get aiErrorBadResponse;

  /// No description provided for @aiErrorContextTooLong.
  ///
  /// In en, this message translates to:
  /// **'Over the model\'s context window. Clear the chat and retry; if it fails on the very first message, the tool list alone may not fit — turn off \"Let the AI act on the app\" in settings, or switch to a model with a larger window'**
  String get aiErrorContextTooLong;

  /// No description provided for @aiErrorToolsUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This endpoint does not support tool calls. Try turning off \"Let the AI act on the app\" in settings'**
  String get aiErrorToolsUnsupported;

  /// No description provided for @aiErrorRejected.
  ///
  /// In en, this message translates to:
  /// **'The endpoint rejected this request'**
  String get aiErrorRejected;

  /// No description provided for @aiErrorToolLoop.
  ///
  /// In en, this message translates to:
  /// **'Ran too many steps without reaching an answer. Try a more specific request'**
  String get aiErrorToolLoop;

  /// No description provided for @aiErrorGatewayTimeout.
  ///
  /// In en, this message translates to:
  /// **'The API gateway timed out before the model replied. One retry was already attempted — try again later; if it keeps happening, turn off app actions in settings (a smaller tool list gets faster replies)'**
  String get aiErrorGatewayTimeout;

  /// No description provided for @aiNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configure the AI endpoint first'**
  String get aiNotConfigured;

  /// No description provided for @aiToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool calling'**
  String get aiToolsTitle;

  /// No description provided for @aiToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let the model look up your library, playlists, sources and downloads instead of guessing titles'**
  String get aiToolsSubtitle;

  /// No description provided for @aiActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Let the AI operate the app'**
  String get aiActionsTitle;

  /// No description provided for @aiActionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off to keep lookup tools only'**
  String get aiActionsSubtitle;

  /// No description provided for @aiToolRunning.
  ///
  /// In en, this message translates to:
  /// **'Calling {tool}…'**
  String aiToolRunning(String tool);

  /// No description provided for @aiToolSearchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Search library'**
  String get aiToolSearchLibrary;

  /// No description provided for @aiToolListPlaylists.
  ///
  /// In en, this message translates to:
  /// **'List playlists'**
  String get aiToolListPlaylists;

  /// No description provided for @aiToolGetPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Read playlist'**
  String get aiToolGetPlaylist;

  /// No description provided for @aiToolSourceStatus.
  ///
  /// In en, this message translates to:
  /// **'Check sources'**
  String get aiToolSourceStatus;

  /// No description provided for @aiToolCreatePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Create playlist'**
  String get aiToolCreatePlaylist;

  /// No description provided for @aiAssistantTitle.
  ///
  /// In en, this message translates to:
  /// **'AI assistant'**
  String get aiAssistantTitle;

  /// No description provided for @aiAssistantSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One sentence to play, queue, build playlists or change settings'**
  String get aiAssistantSubtitle;

  /// No description provided for @aiAssistantPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'What do you want to hear or do?'**
  String get aiAssistantPlaceholder;

  /// No description provided for @aiAssistantEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Just say what to do'**
  String get aiAssistantEmptyTitle;

  /// No description provided for @aiAssistantEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'It calls the app\'s own APIs in the background, so you never have to hunt for a button.'**
  String get aiAssistantEmptyHint;

  /// No description provided for @aiAssistantExample1.
  ///
  /// In en, this message translates to:
  /// **'Play 晴天 by Jay Chou'**
  String get aiAssistantExample1;

  /// No description provided for @aiAssistantExample2.
  ///
  /// In en, this message translates to:
  /// **'Favorite this song and download it'**
  String get aiAssistantExample2;

  /// No description provided for @aiAssistantExample3.
  ///
  /// In en, this message translates to:
  /// **'Make a late-night coding playlist with 20 quiet tracks'**
  String get aiAssistantExample3;

  /// No description provided for @aiAssistantExample4.
  ///
  /// In en, this message translates to:
  /// **'What did I listen to most this year?'**
  String get aiAssistantExample4;

  /// No description provided for @aiAssistantExample5.
  ///
  /// In en, this message translates to:
  /// **'More bass, clearer vocals'**
  String get aiAssistantExample5;

  /// No description provided for @aiAssistantExample6.
  ///
  /// In en, this message translates to:
  /// **'Change this track\'s artist to Jay Chou'**
  String get aiAssistantExample6;

  /// No description provided for @aiAssistantThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get aiAssistantThinking;

  /// No description provided for @aiAssistantWorking.
  ///
  /// In en, this message translates to:
  /// **'Running {tool}…'**
  String aiAssistantWorking(String tool);

  /// No description provided for @aiAssistantNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get aiAssistantNewChat;

  /// No description provided for @aiAssistantReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Actions are off — the assistant can only advise'**
  String get aiAssistantReadOnly;

  /// No description provided for @aiAssistantToolCount.
  ///
  /// In en, this message translates to:
  /// **'{count} calls'**
  String aiAssistantToolCount(int count);

  /// No description provided for @aiCategoryLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get aiCategoryLibrary;

  /// No description provided for @aiCategoryPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get aiCategoryPlayback;

  /// No description provided for @aiCategoryPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get aiCategoryPlaylist;

  /// No description provided for @aiCategoryDownload.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get aiCategoryDownload;

  /// No description provided for @aiCategorySource.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get aiCategorySource;

  /// No description provided for @aiCategorySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get aiCategorySettings;

  /// No description provided for @carMode.
  ///
  /// In en, this message translates to:
  /// **'Car mode'**
  String get carMode;

  /// No description provided for @carModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the wide layout on a head unit'**
  String get carModeSubtitle;

  /// No description provided for @carModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Follow HiCar'**
  String get carModeAuto;

  /// No description provided for @carModeAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch when a head unit connects'**
  String get carModeAutoSubtitle;

  /// No description provided for @carModeAlways.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get carModeAlways;

  /// No description provided for @carModeAlwaysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Preview the wide layout on any screen'**
  String get carModeAlwaysSubtitle;

  /// No description provided for @carModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get carModeOff;

  /// No description provided for @carModeStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'HiCar connected'**
  String get carModeStatusConnected;

  /// No description provided for @carModeStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'No head unit connected'**
  String get carModeStatusDisconnected;

  /// No description provided for @carModeStatusUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Car Kit is unavailable here'**
  String get carModeStatusUnsupported;

  /// No description provided for @settingsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearch;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings, e.g. quality or dark mode'**
  String get settingsSearchHint;

  /// No description provided for @settingsSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No matching settings'**
  String get settingsSearchEmpty;

  /// No description provided for @aiSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get aiSectionTitle;

  /// No description provided for @aiSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Endpoint, key and model'**
  String get aiSettingsSubtitle;

  /// No description provided for @aiSchedulesTitle.
  ///
  /// In en, this message translates to:
  /// **'AI scheduled tasks'**
  String get aiSchedulesTitle;

  /// No description provided for @aiSchedulesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Let the assistant act on schedule'**
  String get aiSchedulesSubtitle;

  /// No description provided for @aiSchedulesIntro.
  ///
  /// In en, this message translates to:
  /// **'Runs the prompt you write at the time you pick. It fires while the app is open; a run missed in the last 6 hours is caught up on next launch.'**
  String get aiSchedulesIntro;

  /// No description provided for @aiSchedulesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No scheduled tasks yet'**
  String get aiSchedulesEmpty;

  /// No description provided for @aiSchedulesEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'For example: build a playlist from a few songs every morning, or recap last week\'s listening every Sunday.'**
  String get aiSchedulesEmptyHint;

  /// No description provided for @aiSchedulesNew.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get aiSchedulesNew;

  /// No description provided for @aiSchedulesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get aiSchedulesEdit;

  /// No description provided for @aiScheduleName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get aiScheduleName;

  /// No description provided for @aiScheduleNameHint.
  ///
  /// In en, this message translates to:
  /// **'Morning picks'**
  String get aiScheduleNameHint;

  /// No description provided for @aiSchedulePrompt.
  ///
  /// In en, this message translates to:
  /// **'What to do'**
  String get aiSchedulePrompt;

  /// No description provided for @aiSchedulePromptHint.
  ///
  /// In en, this message translates to:
  /// **'Pick 8 songs that suit the morning and create a playlist called Morning'**
  String get aiSchedulePromptHint;

  /// No description provided for @aiScheduleTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get aiScheduleTime;

  /// No description provided for @aiScheduleRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get aiScheduleRepeat;

  /// No description provided for @aiScheduleDaily.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get aiScheduleDaily;

  /// No description provided for @aiScheduleWeekdays.
  ///
  /// In en, this message translates to:
  /// **'Weekdays'**
  String get aiScheduleWeekdays;

  /// No description provided for @aiScheduleWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get aiScheduleWeekly;

  /// No description provided for @aiScheduleDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get aiScheduleDelete;

  /// No description provided for @aiScheduleDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”? It will stop running.'**
  String aiScheduleDeleteConfirm(String name);

  /// No description provided for @aiScheduleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get aiScheduleDeleted;

  /// No description provided for @aiScheduleSaved.
  ///
  /// In en, this message translates to:
  /// **'Task saved'**
  String get aiScheduleSaved;

  /// No description provided for @aiScheduleNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Give the task a name'**
  String get aiScheduleNameRequired;

  /// No description provided for @aiSchedulePromptRequired.
  ///
  /// In en, this message translates to:
  /// **'Describe what to do'**
  String get aiSchedulePromptRequired;

  /// No description provided for @aiScheduleRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get aiScheduleRunNow;

  /// No description provided for @aiScheduleRunning.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get aiScheduleRunning;

  /// No description provided for @aiScheduleNeverRun.
  ///
  /// In en, this message translates to:
  /// **'Not run yet'**
  String get aiScheduleNeverRun;

  /// No description provided for @aiScheduleLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last run {time}'**
  String aiScheduleLastRun(String time);

  /// No description provided for @aiScheduleNextRun.
  ///
  /// In en, this message translates to:
  /// **'Next {time}'**
  String aiScheduleNextRun(String time);

  /// No description provided for @aiSchedulePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get aiSchedulePaused;

  /// No description provided for @aiScheduleRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {reason}'**
  String aiScheduleRunFailed(String reason);

  /// No description provided for @aiScheduleRunDone.
  ///
  /// In en, this message translates to:
  /// **'“{name}” finished'**
  String aiScheduleRunDone(String name);

  /// No description provided for @aiScheduleRunFailedToast.
  ///
  /// In en, this message translates to:
  /// **'“{name}” failed'**
  String aiScheduleRunFailedToast(String name);

  /// No description provided for @aiSchedulePill.
  ///
  /// In en, this message translates to:
  /// **'Scheduled · {name}'**
  String aiSchedulePill(String name);

  /// No description provided for @aiDayToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get aiDayToday;

  /// No description provided for @aiDayTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get aiDayTomorrow;

  /// No description provided for @aiWeekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get aiWeekdayMon;

  /// No description provided for @aiWeekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get aiWeekdayTue;

  /// No description provided for @aiWeekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get aiWeekdayWed;

  /// No description provided for @aiWeekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get aiWeekdayThu;

  /// No description provided for @aiWeekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get aiWeekdayFri;

  /// No description provided for @aiWeekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get aiWeekdaySat;

  /// No description provided for @aiWeekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get aiWeekdaySun;

  /// No description provided for @aiCategoryRecommendation.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get aiCategoryRecommendation;

  /// No description provided for @recommendTunedByAi.
  ///
  /// In en, this message translates to:
  /// **'The assistant tuned this list'**
  String get recommendTunedByAi;

  /// No description provided for @recommendTuningReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get recommendTuningReset;

  /// No description provided for @recommendTuningCleared.
  ///
  /// In en, this message translates to:
  /// **'Recommendations reset'**
  String get recommendTuningCleared;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// No description provided for @untilTrackEnd.
  ///
  /// In en, this message translates to:
  /// **'After this track'**
  String get untilTrackEnd;

  /// No description provided for @untilTrackEndNote.
  ///
  /// In en, this message translates to:
  /// **'Pauses after this track'**
  String get untilTrackEndNote;

  /// No description provided for @fadeOutBeforeStop.
  ///
  /// In en, this message translates to:
  /// **'Fade out before stopping'**
  String get fadeOutBeforeStop;

  /// No description provided for @fadeOutBeforeStopHint.
  ///
  /// In en, this message translates to:
  /// **'Gently fades over the last 10 seconds'**
  String get fadeOutBeforeStopHint;

  /// No description provided for @queueEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit queue'**
  String get queueEditTitle;

  /// No description provided for @playNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playNext;

  /// No description provided for @removeFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get removeFromQueue;

  /// No description provided for @scanRules.
  ///
  /// In en, this message translates to:
  /// **'Scan rules'**
  String get scanRules;

  /// No description provided for @scanRulesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filter by duration, size and duplicates'**
  String get scanRulesSubtitle;

  /// No description provided for @scanRulesHint.
  ///
  /// In en, this message translates to:
  /// **'Applies to future scans; nothing is deleted'**
  String get scanRulesHint;

  /// No description provided for @scanRuleNoLimit.
  ///
  /// In en, this message translates to:
  /// **'No limit'**
  String get scanRuleNoLimit;

  /// No description provided for @scanRuleMinDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum duration'**
  String get scanRuleMinDuration;

  /// No description provided for @scanRuleMinSize.
  ///
  /// In en, this message translates to:
  /// **'Minimum size'**
  String get scanRuleMinSize;

  /// No description provided for @scanRuleSkipDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Skip duplicates'**
  String get scanRuleSkipDuplicates;

  /// No description provided for @scanRuleSkipDuplicatesHint.
  ///
  /// In en, this message translates to:
  /// **'Same title, artist and length keeps the largest file'**
  String get scanRuleSkipDuplicatesHint;

  /// No description provided for @scanRuleExcludedFolders.
  ///
  /// In en, this message translates to:
  /// **'Excluded folders'**
  String get scanRuleExcludedFolders;

  /// No description provided for @scanRuleAddFolder.
  ///
  /// In en, this message translates to:
  /// **'Add excluded folder'**
  String get scanRuleAddFolder;

  /// No description provided for @scanRuleFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Full path'**
  String get scanRuleFolderHint;

  /// No description provided for @scanRuleNoExcludedFolders.
  ///
  /// In en, this message translates to:
  /// **'No folder excluded yet'**
  String get scanRuleNoExcludedFolders;

  /// No description provided for @scanRuleRescanHint.
  ///
  /// In en, this message translates to:
  /// **'Takes effect on the next scan'**
  String get scanRuleRescanHint;

  /// No description provided for @savingNow.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingNow;

  /// No description provided for @secondsShort.
  ///
  /// In en, this message translates to:
  /// **'{n} s'**
  String secondsShort(int n);

  /// No description provided for @resetSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get resetSettings;

  /// No description provided for @resetSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clears preferences, keeps accounts and library'**
  String get resetSettingsSubtitle;

  /// No description provided for @resetSettingsConfirm.
  ///
  /// In en, this message translates to:
  /// **'All preferences return to their defaults. Accounts, NAS, playlists, history and the local library index are kept.'**
  String get resetSettingsConfirm;

  /// No description provided for @resetSettingsAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetSettingsAction;

  /// No description provided for @resetSettingsDone.
  ///
  /// In en, this message translates to:
  /// **'Reset {count} settings'**
  String resetSettingsDone(int count);

  /// No description provided for @resetSettingsFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed: {error}'**
  String resetSettingsFailed(String error);

  /// No description provided for @autoEqImport.
  ///
  /// In en, this message translates to:
  /// **'Import AutoEQ'**
  String get autoEqImport;

  /// No description provided for @autoEqImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {name}'**
  String autoEqImported(String name);

  /// No description provided for @autoEqImportFailed.
  ///
  /// In en, this message translates to:
  /// **'No AutoEQ curve found in this file'**
  String get autoEqImportFailed;

  /// No description provided for @replayGain.
  ///
  /// In en, this message translates to:
  /// **'Loudness normalisation'**
  String get replayGain;

  /// No description provided for @replayGainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Levels album volume using ReplayGain tags'**
  String get replayGainSubtitle;

  /// No description provided for @lockScreenLyric.
  ///
  /// In en, this message translates to:
  /// **'Lock screen lyrics'**
  String get lockScreenLyric;

  /// No description provided for @lockScreenLyricSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shows the current line on the lock screen'**
  String get lockScreenLyricSubtitle;

  /// No description provided for @lyricShare.
  ///
  /// In en, this message translates to:
  /// **'Share lyric card'**
  String get lyricShare;

  /// No description provided for @lyricShareNoLine.
  ///
  /// In en, this message translates to:
  /// **'No lyrics for this track yet'**
  String get lyricShareNoLine;

  /// No description provided for @lyricShareSave.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get lyricShareSave;

  /// No description provided for @lyricShareSaved.
  ///
  /// In en, this message translates to:
  /// **'Lyric card saved'**
  String get lyricShareSaved;

  /// No description provided for @lyricShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String lyricShareFailed(String error);

  /// No description provided for @smartPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Smart playlists'**
  String get smartPlaylists;

  /// No description provided for @smartPlaylistsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Built from rules, nothing to maintain by hand'**
  String get smartPlaylistsSubtitle;

  /// No description provided for @smartRecentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get smartRecentlyAdded;

  /// No description provided for @smartRecentlyAddedHint.
  ///
  /// In en, this message translates to:
  /// **'Newest tracks in your library'**
  String get smartRecentlyAddedHint;

  /// No description provided for @smartMostPlayed.
  ///
  /// In en, this message translates to:
  /// **'Most played'**
  String get smartMostPlayed;

  /// No description provided for @smartMostPlayedHint.
  ///
  /// In en, this message translates to:
  /// **'Sorted by play count'**
  String get smartMostPlayedHint;

  /// No description provided for @smartNeverPlayed.
  ///
  /// In en, this message translates to:
  /// **'Never played'**
  String get smartNeverPlayed;

  /// No description provided for @smartNeverPlayedHint.
  ///
  /// In en, this message translates to:
  /// **'In your library but never played'**
  String get smartNeverPlayedHint;

  /// No description provided for @smartFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Your liked songs'**
  String get smartFavoritesHint;

  /// No description provided for @smartEmpty.
  ///
  /// In en, this message translates to:
  /// **'No songs match this rule yet'**
  String get smartEmpty;

  /// No description provided for @smartSongCount.
  ///
  /// In en, this message translates to:
  /// **'{n} songs'**
  String smartSongCount(int n);

  /// No description provided for @precacheRecent.
  ///
  /// In en, this message translates to:
  /// **'Pre-cache frequent tracks'**
  String get precacheRecent;

  /// No description provided for @precacheRecentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fetches your most played tracks on Wi-Fi so they start instantly'**
  String get precacheRecentSubtitle;

  /// No description provided for @precacheCount.
  ///
  /// In en, this message translates to:
  /// **'How many to pre-cache'**
  String get precacheCount;

  /// No description provided for @precacheCountValue.
  ///
  /// In en, this message translates to:
  /// **'{n} tracks'**
  String precacheCountValue(int n);

  /// No description provided for @pitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get pitch;

  /// No description provided for @pitchSemitonesUnit.
  ///
  /// In en, this message translates to:
  /// **'semitone(s)'**
  String get pitchSemitonesUnit;

  /// No description provided for @pitchReset.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get pitchReset;

  /// No description provided for @pitchHint.
  ///
  /// In en, this message translates to:
  /// **'Shifts pitch without changing speed. Negative values help you sing along lower.'**
  String get pitchHint;

  /// No description provided for @skipSilence.
  ///
  /// In en, this message translates to:
  /// **'Skip silence'**
  String get skipSilence;

  /// No description provided for @skipSilenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Skips silent intros and gaps automatically (Android only)'**
  String get skipSilenceSubtitle;

  /// No description provided for @playbackFade.
  ///
  /// In en, this message translates to:
  /// **'Play/pause fade'**
  String get playbackFade;

  /// No description provided for @playbackFadeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Soft ramps when starting or pausing, so headphones don\'t pop'**
  String get playbackFadeSubtitle;

  /// No description provided for @exportM3u.
  ///
  /// In en, this message translates to:
  /// **'Export as M3U'**
  String get exportM3u;

  /// No description provided for @exportM3uEmpty.
  ///
  /// In en, this message translates to:
  /// **'This playlist has no songs yet'**
  String get exportM3uEmpty;

  /// No description provided for @exportM3uSaved.
  ///
  /// In en, this message translates to:
  /// **'Exported the M3U file'**
  String get exportM3uSaved;

  /// No description provided for @exportM3uFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportM3uFailed(String error);

  /// No description provided for @importM3u.
  ///
  /// In en, this message translates to:
  /// **'Import M3U playlist'**
  String get importM3u;

  /// No description provided for @importM3uEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usable entries in that file'**
  String get importM3uEmpty;

  /// No description provided for @importM3uResult.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported}, skipped {skipped}'**
  String importM3uResult(int imported, int skipped);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
