import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/card_expand.dart';
import '../../../core/io/bounded_input.dart';
import '../../../core/storage/cache_maintenance_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/widgets/sleep_timer_sheet.dart';
import 'settings_provider.dart';
import '../../search/presentation/search_provider.dart';
import '../../playlist/data/playlist_repository.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../equalizer/presentation/equalizer_provider.dart';
import '../../download/presentation/download_provider.dart';
import '../domain/playlist_backup.dart';
import 'app_log_screen.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../l10n/app_strings.dart';
import '../../sync/data/sync_identity_store.dart';
import '../../nas/domain/nas_url.dart';

final settingsDeviceIdProvider = FutureProvider<String>((ref) async {
  return (await SyncIdentityStore().load()).deviceId;
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialAction});

  final String? initialAction;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _handledInitialAction = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialAction || widget.initialAction == null) return;
    _handledInitialAction = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.initialAction) {
        case 'audio-quality':
          _showAudioQualityDialog(context, ref);
        case 'download-quality':
          _showDownloadQualityDialog(context, ref);
        case 'default-search':
          _showDefaultPlatformDialog(context, ref);
        case 'backup':
          _backupData(context, ref);
        case 'restore':
          _restoreData(context, ref);
        case 'clear-cache':
          _clearCache(context, ref);
        case 'diagnostic-log':
          showDiagnosticLogOverlay(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final audioQuality = ref.watch(audioQualityProvider);
    final language = ref.watch(appLanguageProvider);
    final s = S.of(context);

    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            ListView(
              padding: EdgeInsets.only(top: FrostedTabHeader.extent(context)),
              children: [
                _buildSection(context, s.sync, [
                  _buildNavTile(
                    context,
                    ref,
                    s.cloudAccount,
                    s.cloudAccountSubtitle,
                    () => context.push('/sync'),
                    captureExpandOrigin: true,
                  ),
                ]),
                _buildSection(context, s.advanced, [
                  _buildNavTile(
                    context,
                    ref,
                    s.localLibrary,
                    s.localLibrarySubtitle,
                    () => context.push('/local-music'),
                    captureExpandOrigin: true,
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.customSources,
                    s.customSourcesSubtitle,
                    () => context.push('/custom-source'),
                    captureExpandOrigin: true,
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.nasServer,
                    platformPickerDescription(
                      'subsonic',
                      locale: Localizations.localeOf(context),
                    ),
                    () => context.push('/subsonic-settings'),
                    captureExpandOrigin: true,
                  ),
                ]),
                _buildSection(context, s.playback, [
                  _buildNavTile(
                    context,
                    ref,
                    s.audioQuality,
                    _getQualityName(audioQuality),
                    () => _showAudioQualityDialog(context, ref),
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.equalizer,
                    equalizerSubtitle(
                      ref.watch(equalizerProvider),
                      locale: Localizations.localeOf(context),
                    ),
                    () => context.push('/equalizer'),
                    captureExpandOrigin: true,
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.sleepTimer,
                    sleepTimerSubtitle(
                      ref.watch(sleepTimerProvider),
                      locale: Localizations.localeOf(context),
                    ),
                    () => _showSleepTimerMenu(context, ref),
                    trailing: ref.watch(sleepTimerProvider) is SleepTimerRunning
                        ? TextButton(
                            onPressed: () {
                              ref
                                  .read(sleepTimerProvider.notifier)
                                  .cancelTimer();
                              showAppNotification(
                                s.sleepTimerCancelled,
                                type: AppNotificationType.success,
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: AppColors.accentOf(context),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_off_outlined, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  s.cancel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  _buildSwitchTile(
                    context,
                    ref,
                    s.autoResume,
                    s.autoResumeSubtitle,
                    ref.watch(autoResumePlaybackProvider),
                    (value) {
                      ref
                          .read(autoResumePlaybackProvider.notifier)
                          .setAutoResume(value);
                    },
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.defaultSearchPlatform,
                    _platformName(ref.watch(defaultSearchPlatformProvider)),
                    () => _showDefaultPlatformDialog(context, ref),
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.listeningStats,
                    s.listeningStatsSubtitle,
                    () => context.push('/stats'),
                    captureExpandOrigin: true,
                  ),
                ]),
                _buildSection(context, s.appearance, [
                  _buildNavTile(
                    context,
                    ref,
                    s.language,
                    s.languageName(language),
                    () => _showLanguageDialog(context),
                  ),
                  _buildSwitchTile(
                    context,
                    ref,
                    s.darkMode,
                    s.darkModeSubtitle,
                    isDark && themeMode != ThemeMode.system,
                    (value) {
                      ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(
                            value ? ThemeMode.dark : ThemeMode.light,
                          );
                    },
                  ),
                  _buildSwitchTile(
                    context,
                    ref,
                    s.followSystem,
                    s.followSystemThemeSubtitle,
                    themeMode == ThemeMode.system,
                    (value) {
                      if (value) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(ThemeMode.system);
                      } else {
                        final darkNow =
                            MediaQuery.platformBrightnessOf(context) ==
                            Brightness.dark;
                        ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(
                              darkNow ? ThemeMode.dark : ThemeMode.light,
                            );
                      }
                    },
                  ),
                ]),
                _buildSection(context, s.downloads, [
                  _buildNavTile(
                    context,
                    ref,
                    s.downloadManager,
                    s.downloadManagerSubtitle,
                    () => context.push('/download'),
                    captureExpandOrigin: true,
                  ),
                  _buildSwitchTile(
                    context,
                    ref,
                    s.wifiOnly,
                    s.wifiOnlySubtitle,
                    ref.watch(wifiOnlyDownloadProvider),
                    (value) {
                      ref
                          .read(wifiOnlyDownloadProvider.notifier)
                          .setWifiOnly(value);
                      ref.read(setWifiOnlyDownloadProvider)(value);
                    },
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.downloadQuality,
                    _getQualityName(ref.watch(downloadQualityProvider)),
                    () => _showDownloadQualityDialog(context, ref),
                  ),
                ]),
                _buildSection(context, s.data, [
                  _buildNavTile(
                    context,
                    ref,
                    s.backup,
                    s.backupSubtitle,
                    () => _backupData(context, ref),
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.restore,
                    s.restoreSubtitle,
                    () => _restoreData(context, ref),
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.clearCache,
                    s.clearCacheSubtitle,
                    () => _clearCache(context, ref),
                  ),
                ]),
                _buildSection(context, s.about, [
                  _SettingRow(name: s.version, value: 'v3.0.2'),
                  _DeviceIdRow(
                    deviceId: ref.watch(settingsDeviceIdProvider).valueOrNull,
                  ),
                  _buildNavTile(
                    context,
                    ref,
                    s.diagnostics,
                    s.diagnosticsSubtitle,
                    () => showDiagnosticLogOverlay(context),
                  ),
                ]),
                const SizedBox(height: 40),
              ],
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FrostedTabHeader(
                title: s.settings,
                leadingIcon: Icons.settings_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.mutedText(context),
            ),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.fill(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder(context)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: AppColors.cardBorder(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    WidgetRef ref,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onScaffold(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.mutedText(context),
                  ),
                ),
              ],
            ),
          ),
          FxSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildNavTile(
    BuildContext context,
    WidgetRef ref,
    String title,
    String subtitle,
    VoidCallback onTap, {
    Widget? trailing,
    bool captureExpandOrigin = false,
  }) {
    final expandAnchorKey = GlobalKey();
    return RepaintBoundary(
      key: expandAnchorKey,
      child: InkWell(
        onTap: captureExpandOrigin
            ? () async {
                final anchor = expandAnchorKey.currentContext;
                if (anchor != null) await captureCardExpandOrigin(anchor);
                if (context.mounted) onTap();
              }
            : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.mutedText(context),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  String _getQualityName(AudioQualityOption quality) =>
      qualityName(quality, locale: Localizations.localeOf(context));

  void _showSleepTimerMenu(BuildContext context, WidgetRef ref) {
    showSleepTimerSheet(context, ref);
  }

  String _platformName(String id) =>
      platformDisplayName(id, locale: Localizations.localeOf(context));

  void _showDefaultPlatformDialog(BuildContext context, WidgetRef ref) {
    // 与"音质选择"弹窗同一视觉语言：居中圆角卡片 + 图标块选项行。
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const _PlatformPickerDialog(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const _LanguagePickerDialog(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _showAudioQualityDialog(BuildContext context, WidgetRef ref) {
    _showQualityDialog(context, ref, S.of(context).chooseQuality, false);
  }

  void _showDownloadQualityDialog(BuildContext context, WidgetRef ref) {
    _showQualityDialog(context, ref, S.of(context).chooseDownloadQuality, true);
  }

  void _showQualityDialog(
    BuildContext context,
    WidgetRef ref,
    String title,
    bool isDownload,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _QualityPickerDialog(title: title, isDownload: isDownload),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _backupData(BuildContext context, WidgetRef ref) async {
    try {
      final storage = await StorageService.instance;
      final playlists = await ref
          .read(playlistServiceProvider)
          .getAllPlaylists();
      final playlistSnapshot = const PlaylistSnapshotCodec().encode(
        PlaylistSnapshot(schemaVersion: 1, playlists: playlists),
      );
      final backup = <String, dynamic>{
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'playlists': jsonDecode(playlistSnapshot),
        'search_history': storage.getStringList('search_history'),
        'theme_mode': storage.getInt('theme_mode'),
        'audio_quality': storage.getInt('audio_quality'),
        'download_quality': storage.getInt('download_quality'),
        'wifi_only_download': storage.getBool('wifi_only_download'),
      };

      backup['auto_resume_playback'] = storage.getBool('auto_resume_playback');
      backup['default_search_platform'] = storage.getString(
        'default_search_platform',
      );
      backup['additional_settings'] = {
        'leaderboard_layout_v1': storage.getJsonList('leaderboard_layout_v1'),
        'leaderboard_layout_order_version': storage.getInt(
          'leaderboard_layout_order_version',
        ),
        'local_music_dirs_v1': storage.getStringList('local_music_dirs_v1'),
        'local_music_download_dir_v1': storage.getString(
          'local_music_download_dir_v1',
        ),
        'custom_sources': storage.getString('custom_sources'),
        'app_language': storage.getString('app_language'),
      }..removeWhere((_, value) => value == null);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final fileName =
          'koyze_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final savedPath = await FilePicker.saveFile(
        dialogTitle: S.of(context).exportBackupTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Platform.isIOS || Platform.isAndroid ? bytes : null,
      );
      if (savedPath == null) return;
      if (!Platform.isIOS && !Platform.isAndroid) {
        await File(savedPath).writeAsString(jsonStr);
      }

      if (context.mounted) {
        showAppNotification(
          S.of(context).backupExported(savedPath),
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppNotification(
          S.of(context).backupFailed(e),
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _restoreData(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final bytes = await readFileBytesBounded(
        file,
        maximumBytes: BackupLimits.maximumFileBytes,
      );
      final data = decodeBackup(utf8.decode(bytes, allowMalformed: false));
      await BackupRestoreCoordinator(
        storage: await StorageService.instance,
        playlists: ref.read(playlistServiceProvider),
        publishCommitted: (data) {
          ref
              .read(searchHistoryProvider.notifier)
              .applyCommitted(data.searchHistory);
          ref.read(themeModeProvider.notifier).applyCommitted(data.themeMode);
          ref
              .read(audioQualityProvider.notifier)
              .applyCommitted(data.audioQuality);
          ref
              .read(downloadQualityProvider.notifier)
              .applyCommitted(data.downloadQuality);
          ref
              .read(wifiOnlyDownloadProvider.notifier)
              .applyCommitted(data.wifiOnlyDownload);
          ref.read(setWifiOnlyDownloadProvider)(data.wifiOnlyDownload);
          ref
              .read(autoResumePlaybackProvider.notifier)
              .applyCommitted(data.autoResumePlayback);
          ref
              .read(defaultSearchPlatformProvider.notifier)
              .applyCommitted(data.defaultSearchPlatform);
          final language = data.additionalSettings['app_language'];
          if (language is String) {
            ref
                .read(appLanguageProvider.notifier)
                .applyCommitted(AppLanguage.parse(language));
          }
        },
      ).restore(data);

      if (context.mounted) {
        showAppNotification(
          S.of(context).restoreSucceeded,
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppNotification(
          S.of(context).restoreFailed(e),
          type: AppNotificationType.error,
        );
      }
    }
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final selected = <AppCacheCategory>{...AppCacheCategory.values};
    final copy = S.of(context);
    final choices =
        <({AppCacheCategory category, String title, String subtitle})>[
          (
            category: AppCacheCategory.playback,
            title: copy.playbackCache,
            subtitle: copy.playbackCacheSubtitle,
          ),
          (
            category: AppCacheCategory.artwork,
            title: copy.artworkCache,
            subtitle: copy.artworkCacheSubtitle,
          ),
          (
            category: AppCacheCategory.temporaryFiles,
            title: copy.tempFiles,
            subtitle: copy.tempFilesSubtitle,
          ),
        ];
    final confirmed = await showDialog<Set<AppCacheCategory>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final allSelected = selected.length == AppCacheCategory.values.length;
          final selectAllValue = allSelected
              ? true
              : selected.isEmpty
              ? false
              : null;
          return AlertDialog(
            backgroundColor: AppColors.dialogBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              copy.chooseCache,
              style: TextStyle(color: AppColors.onScaffold(context)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: selectAllValue,
                    tristate: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.accentOf(context),
                    title: Text(
                      copy.selectAll,
                      style: TextStyle(
                        color: AppColors.onScaffold(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        selected.clear();
                        if (value != false) {
                          selected.addAll(AppCacheCategory.values);
                        }
                      });
                    },
                  ),
                  const Divider(height: 1),
                  ...choices.map((choice) {
                    return CheckboxListTile(
                      value: selected.contains(choice.category),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.accentOf(context),
                      title: Text(
                        choice.title,
                        style: TextStyle(color: AppColors.onScaffold(context)),
                      ),
                      subtitle: Text(
                        choice.subtitle,
                        style: TextStyle(
                          color: AppColors.secondaryText(context),
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(choice.category);
                          } else {
                            selected.remove(choice.category);
                          }
                        });
                      },
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      copy.cacheKeepNote,
                      style: TextStyle(
                        color: AppColors.secondaryText(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  copy.cancel,
                  style: TextStyle(color: AppColors.mutedText(context)),
                ),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        Set<AppCacheCategory>.of(selected),
                      ),
                child: Text(
                  copy.clear,
                  style: TextStyle(
                    color: selected.isEmpty
                        ? AppColors.mutedText(context)
                        : AppColors.accentOf(context),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != null && confirmed.isNotEmpty && context.mounted) {
      try {
        final summary = await ref
            .read(cacheMaintenanceProvider)
            .clear(confirmed);
        if (confirmed.contains(AppCacheCategory.artwork)) {
          PaintingBinding.instance.imageCache
            ..clear()
            ..clearLiveImages();
        }
        if (context.mounted) {
          final retained = summary.retainedPlaybackEntries;
          showAppNotification(
            retained == 0
                ? S.of(context).cacheCleared
                : S.of(context).cacheClearedRetained(retained),
            type: AppNotificationType.success,
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppNotification(
            S.of(context).clearFailed(e),
            type: AppNotificationType.error,
          );
        }
      }
    }
  }
}

class _SettingRow extends StatelessWidget {
  final String name;
  final String value;

  const _SettingRow({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onScaffold(context),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: AppColors.mutedText(context)),
          ),
        ],
      ),
    );
  }
}

class _DeviceIdRow extends StatelessWidget {
  const _DeviceIdRow({required this.deviceId});

  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final full = deviceId;
    final raw = full?.replaceFirst('device_', '') ?? '';
    final short = raw.length > 12
        ? '${raw.substring(0, 8)}…${raw.substring(raw.length - 4)}'
        : (raw.isEmpty ? S.of(context).loading : raw);
    return InkWell(
      onTap: full == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: full));
              showAppNotification(S.of(context).deviceUuidCopied);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).deviceUuid,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.onScaffold(context),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    short,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppColors.mutedText(context),
                    ),
                  ),
                ),
                if (full != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppColors.mutedText(context),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 默认搜索平台选择弹窗：与"音质选择"弹窗同款视觉语言
/// （圆角 24 卡片 + 图标块 + 勾选胶囊 + easeOutBack 入场）。
/// 选项跟搜索源列表走，NAS 乐库始终出现。
class _PlatformPickerDialog extends ConsumerWidget {
  const _PlatformPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = canonicalSearchPlatform(
      ref.watch(defaultSearchPlatformProvider),
    );
    final accent = AppColors.accentOf(context);
    final options = [
      for (final source in ref.watch(allSearchSourcesProvider))
        if (source.id != 'all') source,
    ];
    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassSurface(
              style: AppGlassStyle.regular,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              S.of(context).defaultSearchPlatform,
                              style: TextStyle(
                                color: AppColors.onScaffold(context),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.mutedText(context),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final id = options[index].id;
                          return _PlatformOptionTile(
                            name: platformDisplayName(
                              id,
                              locale: Localizations.localeOf(context),
                            ),
                            icon: platformPickerIcon(id),
                            description: platformPickerDescription(
                              id,
                              locale: Localizations.localeOf(context),
                            ),
                            selected: current == id,
                            accent: accent,
                            onTap: () {
                              final platform = canonicalSearchPlatform(id);
                              ref
                                  .read(defaultSearchPlatformProvider.notifier)
                                  .setPlatform(platform);
                              ref
                                      .read(selectedSourceIdProvider.notifier)
                                      .state =
                                  platform;
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData platformPickerIcon(String id) {
  return switch (canonicalSearchPlatform(id)) {
    'tx' => Icons.music_note_rounded,
    'kw' => Icons.headphones_rounded,
    'wy' => Icons.cloud_rounded,
    'local' => Icons.folder_rounded,
    'favorites' => Icons.favorite_rounded,
    'subsonic' => Icons.cloud_queue_rounded,
    _ => Icons.dns_rounded,
  };
}

class _PlatformOptionTile extends StatelessWidget {
  const _PlatformOptionTile({
    required this.name,
    required this.icon,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final String description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : AppColors.fill(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected ? accent : AppColors.mutedText(context),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: selected ? accent : AppColors.onScaffold(context),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QualityPickerDialog extends ConsumerWidget {
  const _QualityPickerDialog({required this.title, required this.isDownload});

  final String title;
  final bool isDownload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentQuality = ref.watch(
      isDownload ? downloadQualityProvider : audioQualityProvider,
    );
    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassSurface(
              style: AppGlassStyle.regular,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.mutedText(context),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  ...AudioQualityOption.values.map((quality) {
                    final selected = currentQuality == quality;
                    final accent = AppColors.accentOf(context);
                    final meta = _qualityMeta(
                      quality,
                      locale: Localizations.localeOf(context),
                    );
                    return _QualityOptionTile(
                      quality: quality,
                      name: qualityName(
                        quality,
                        locale: Localizations.localeOf(context),
                      ),
                      description: meta.$2,
                      icon: meta.$1,
                      selected: selected,
                      accent: accent,
                      onTap: () {
                        if (isDownload) {
                          ref
                              .read(downloadQualityProvider.notifier)
                              .setQuality(quality);
                        } else {
                          ref
                              .read(audioQualityProvider.notifier)
                              .setQuality(quality);
                        }
                        Navigator.pop(context);
                      },
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityOptionTile extends StatelessWidget {
  const _QualityOptionTile({
    required this.quality,
    required this.name,
    required this.description,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AudioQualityOption quality;
  final String name;
  final String description;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : AppColors.fill(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected ? accent : AppColors.mutedText(context),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: selected ? accent : AppColors.onScaffold(context),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String platformDisplayName(String id, {Locale? locale}) {
  final en = localeIsEnglish(locale);
  switch (canonicalSearchPlatform(id)) {
    case 'tx':
      return en ? 'Tencent (QQ Music)' : '腾讯 (QQ 音乐)';
    case 'kw':
      return en ? 'Kuwo' : '酷我';
    case 'wy':
      return en ? 'NetEase' : '网易云';
    case 'local':
      return en ? 'Local' : '本地';
    case 'favorites':
      return en ? 'Favorites' : '收藏';
    case 'subsonic':
      return en ? 'NAS library' : 'NAS 乐库';
    default:
      return id;
  }
}

String platformPickerDescription(String id, {Locale? locale}) {
  final en = localeIsEnglish(locale);
  switch (canonicalSearchPlatform(id)) {
    case 'tx':
      return en ? 'Broadest catalog, used first' : '覆盖最全，默认优先';
    case 'kw':
      return en ? 'Kuwo music source' : '酷我音乐源';
    case 'wy':
      return en ? 'NetEase Cloud Music source' : '网易云音乐源';
    case 'local':
      return en ? 'Only songs scanned on this device' : '仅本地已扫描歌曲';
    case 'favorites':
      return en ? 'Only favorited songs' : '仅收藏夹内容';
    case 'subsonic':
      return en
          ? 'Navidrome / Emby / Jellyfin / Plex / Synology'
          : 'Navidrome / Emby / Jellyfin / Plex / 群晖';
    default:
      return '';
  }
}

(IconData, String) _qualityMeta(AudioQualityOption quality, {Locale? locale}) {
  final en = localeIsEnglish(locale);
  return switch (quality) {
    AudioQualityOption.low => (
      Icons.volume_down_outlined,
      en ? '128 kbps, uses less data' : '128kbps，节省流量',
    ),
    AudioQualityOption.high => (
      Icons.volume_up_outlined,
      en ? '320 kbps, quality and size' : '320kbps，兼顾音质与体积',
    ),
    AudioQualityOption.lossless => (
      Icons.audio_file_outlined,
      en ? 'FLAC lossless' : 'FLAC 无损',
    ),
    AudioQualityOption.lossless24 => (
      Icons.album_outlined,
      en ? 'FLAC 24-bit master' : 'FLAC 24bit 臻品母带',
    ),
    AudioQualityOption.hires => (
      Icons.speed_outlined,
      en ? 'Hi-Res' : 'Hi-Res 高解析',
    ),
  };
}

String qualityName(AudioQualityOption quality, {Locale? locale}) {
  final en = localeIsEnglish(locale);
  switch (quality) {
    case AudioQualityOption.low:
      return en ? 'Standard (128 kbps)' : '标准 (128kbps)';
    case AudioQualityOption.high:
      return en ? 'High (320 kbps)' : '超高品质 (320kbps)';
    case AudioQualityOption.lossless:
      return en ? 'Lossless (FLAC)' : '无损 (FLAC)';
    case AudioQualityOption.lossless24:
      return en ? 'Master (FLAC 24-bit)' : '臻品母带 (FLAC 24bit)';
    case AudioQualityOption.hires:
      return 'Hi-Res';
  }
}

class _LanguagePickerDialog extends ConsumerWidget {
  const _LanguagePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appLanguageProvider);
    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    final options = <(AppLanguage, String, String)>[
      (AppLanguage.system, s.followSystem, s.followSystemLanguageSubtitle),
      (AppLanguage.zh, '简体中文', s.chineseInterface),
      (AppLanguage.en, 'English', s.englishInterface),
    ];
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: 340,
            child: GlassSurface(
              style: AppGlassStyle.regular,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.language,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.mutedText(context),
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  for (final option in options)
                    _LanguageOptionTile(
                      name: option.$2,
                      description: option.$3,
                      selected: current == option.$1,
                      accent: accent,
                      onTap: () {
                        ref
                            .read(appLanguageProvider.notifier)
                            .setLanguage(option.$1);
                        Navigator.pop(context);
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.name,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String name;
  final String description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: selected ? accent : AppColors.onScaffold(context),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
