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
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/widgets/sleep_timer_sheet.dart';
import 'settings_provider.dart';
import '../../search/presentation/search_provider.dart';
import '../../playlist/data/playlist_repository.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../player/presentation/player_provider.dart';
import '../../download/presentation/download_provider.dart';
import '../domain/playlist_backup.dart';
import 'app_log_screen.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../sync/data/sync_identity_store.dart';

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

    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 列表可滚动到栏内部（栏高度不变），顶栏磨砂才可见。
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          // 顶栏整栏磨砂玻璃，无底部渐变透明。
          flexibleSpace: GradientAppBarBackground(
            background: Theme.of(context).scaffoldBackgroundColor,
          ),
          title: Text(
            '设置',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight,
          ),
          children: [
            _buildSection(context, '同步', [
              _buildNavTile(
                context,
                ref,
                '云端账号 / 歌单',
                '同步收藏、歌单、设置与自定义音源',
                () => context.push('/sync'),
                captureExpandOrigin: true,
              ),
            ]),
            _buildSection(context, '高级功能', [
              _buildNavTile(
                context,
                ref,
                '本地音乐目录',
                '设置扫描目录、刷新本地歌曲与在线刮削',
                () => context.push('/local-music'),
                captureExpandOrigin: true,
              ),
              _buildNavTile(
                context,
                ref,
                '自定义源',
                '管理自定义音乐源',
                () => context.push('/custom-source'),
                captureExpandOrigin: true,
              ),
            ]),
            _buildSection(context, '播放', [
              _buildNavTile(
                context,
                ref,
                '音质选择',
                _getQualityName(audioQuality),
                () => _showAudioQualityDialog(context, ref),
              ),
              _buildNavTile(
                context,
                ref,
                '睡眠定时',
                sleepTimerSubtitle(ref.watch(sleepTimerProvider)),
                () => _showSleepTimerMenu(context, ref),
                trailing: ref.watch(sleepTimerProvider) is SleepTimerRunning
                    ? TextButton(
                        onPressed: () {
                          ref.read(sleepTimerProvider.notifier).cancelTimer();
                          showAppNotification(
                            '已取消睡眠定时',
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
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_off_outlined, size: 16),
                            SizedBox(width: 4),
                            Text('取消', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      )
                    : null,
              ),
              _buildSwitchTile(
                context,
                ref,
                '自动恢复播放',
                '打开 App 时自动继续播放上次的歌曲',
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
                '默认搜索平台',
                _platformName(ref.watch(defaultSearchPlatformProvider)),
                () => _showDefaultPlatformDialog(context, ref),
              ),
              _buildNavTile(
                context,
                ref,
                '听歌统计',
                '播放历史 · Top 排行 · 热力图',
                () => context.push('/stats'),
                captureExpandOrigin: true,
              ),
            ]),
            _buildSection(context, '外观', [
              _buildSwitchTile(
                context,
                ref,
                '深色模式',
                '使用深色主题',
                isDark && themeMode != ThemeMode.system,
                (value) {
                  ref
                      .read(themeModeProvider.notifier)
                      .setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                },
              ),
              _buildSwitchTile(
                context,
                ref,
                '跟随系统',
                '自动切换亮色/深色主题',
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
            _buildSection(context, '歌单', [
              _buildNavTile(
                context,
                ref,
                '重复歌曲',
                '检测并清理重复歌曲',
                () => context.push('/duplicates'),
                captureExpandOrigin: true,
              ),
            ]),
            _buildSection(context, '下载', [
              _buildNavTile(
                context,
                ref,
                '下载管理',
                '查看和管理下载任务',
                () => context.push('/download'),
                captureExpandOrigin: true,
              ),
              _buildSwitchTile(
                context,
                ref,
                '仅 WiFi 下载',
                '仅在 WiFi 环境下下载歌曲',
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
                '下载音质',
                _getQualityName(ref.watch(downloadQualityProvider)),
                () => _showDownloadQualityDialog(context, ref),
              ),
            ]),
            _buildSection(context, '数据', [
              _buildNavTile(
                context,
                ref,
                '备份数据',
                '导出歌单、设置等数据到文件',
                () => _backupData(context, ref),
              ),
              _buildNavTile(
                context,
                ref,
                '恢复数据',
                '从备份文件恢复数据',
                () => _restoreData(context, ref),
              ),
              _buildNavTile(
                context,
                ref,
                '清除缓存',
                '清除歌曲播放缓存、封面缓存和临时文件',
                () => _clearCache(context, ref),
              ),
            ]),
            _buildSection(context, '关于', [
              const _SettingRow(name: '版本', value: '2.2.0'),
              _DeviceIdRow(
                deviceId: ref.watch(settingsDeviceIdProvider).valueOrNull,
              ),
              _buildNavTile(
                context,
                ref,
                '实时诊断日志',
                '点开开始记录，最小化后继续记录（不保存）',
                () => showDiagnosticLogOverlay(context),
              ),
            ]),
            const SizedBox(height: 40),
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

  String _getQualityName(AudioQualityOption quality) => qualityName(quality);

  void _showSleepTimerMenu(BuildContext context, WidgetRef ref) {
    showSleepTimerSheet(context, ref);
  }

  String _platformName(String id) => platformDisplayName(id);

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

  void _showAudioQualityDialog(BuildContext context, WidgetRef ref) {
    _showQualityDialog(context, ref, '选择音质', false);
  }

  void _showDownloadQualityDialog(BuildContext context, WidgetRef ref) {
    _showQualityDialog(context, ref, '选择下载音质', true);
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
      }..removeWhere((_, value) => value == null);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final fileName =
          'koyze_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final savedPath = await FilePicker.saveFile(
        dialogTitle: '导出 Koyze 备份',
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
          '备份已导出到 $savedPath',
          type: AppNotificationType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppNotification('备份失败: $e', type: AppNotificationType.error);
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
        },
      ).restore(data);

      if (context.mounted) {
        showAppNotification('数据恢复成功', type: AppNotificationType.success);
      }
    } catch (e) {
      if (context.mounted) {
        showAppNotification('恢复失败: $e', type: AppNotificationType.error);
      }
    }
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final selected = <AppCacheCategory>{...AppCacheCategory.values};
    final choices =
        <({AppCacheCategory category, String title, String subtitle})>[
          (
            category: AppCacheCategory.playback,
            title: '歌曲播放缓存',
            subtitle: '自动缓存的歌曲文件，不包含手动下载的歌曲',
          ),
          (
            category: AppCacheCategory.artwork,
            title: '封面缓存',
            subtitle: '专辑封面的磁盘和内存缓存',
          ),
          (
            category: AppCacheCategory.temporaryFiles,
            title: '临时文件',
            subtitle: '系统临时目录中的中间文件',
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
              '选择要清除的内容',
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
                      '全选',
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
                      '手动下载的歌曲不会被删除；正在播放的歌曲缓存会安全保留。',
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
                  '取消',
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
                  '清除',
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
            retained == 0 ? '所选缓存已清除' : '缓存已清除，$retained 个正在使用的歌曲缓存已安全保留',
            type: AppNotificationType.success,
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppNotification('清除失败: $e', type: AppNotificationType.error);
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
        : (raw.isEmpty ? '读取中…' : raw);
    return InkWell(
      onTap: full == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: full));
              showAppNotification('完整设备 UUID 已复制');
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备 UUID',
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
class _PlatformPickerDialog extends ConsumerWidget {
  const _PlatformPickerDialog();

  static const _options = <String, (IconData, String)>{
    'tx': (Icons.music_note_rounded, '腾讯 · QQ 音乐'),
    'kw': (Icons.headphones_rounded, '酷我'),
    'wy': (Icons.cloud_rounded, '网易云'),
    'local': (Icons.folder_rounded, '本地音乐'),
    'favorites': (Icons.favorite_rounded, '收藏夹'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(defaultSearchPlatformProvider);
    final accent = AppColors.accentOf(context);
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
                        '默认搜索平台',
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
              for (final entry in _options.entries) ...[
                _PlatformOptionTile(
                  name: platformDisplayName(entry.key),
                  icon: entry.value.$1,
                  description: _platformDescription(entry.key),
                  selected: current == entry.key,
                  accent: accent,
                  onTap: () {
                    ref
                        .read(defaultSearchPlatformProvider.notifier)
                        .setPlatform(entry.key);
                    ref.read(selectedSourceIdProvider.notifier).state =
                        entry.key;
                    Navigator.pop(context);
                  },
                ),
              ],
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

String _platformDescription(String id) {
  switch (id) {
    case 'tx':
      return '覆盖最全，默认优先';
    case 'kw':
      return '酷我音乐源';
    case 'wy':
      return '网易云音乐源';
    case 'local':
      return '仅本地已扫描歌曲';
    case 'favorites':
      return '仅收藏夹内容';
    default:
      return '';
  }
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
                final meta = _qualityMeta(quality);
                return _QualityOptionTile(
                  quality: quality,
                  name: qualityName(quality),
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

String platformDisplayName(String id) {
  switch (id) {
    case 'tx':
      return '腾讯 (QQ 音乐)';
    case 'kw':
      return '酷我';
    case 'wy':
      return '网易云';
    case 'local':
      return '本地';
    case 'favorites':
      return '收藏';
    default:
      return id;
  }
}

(IconData, String) _qualityMeta(AudioQualityOption quality) {
  return switch (quality) {
    AudioQualityOption.low => (Icons.volume_down_outlined, '128kbps，节省流量'),
    AudioQualityOption.high => (Icons.volume_up_outlined, '320kbps，兼顾音质与体积'),
    AudioQualityOption.lossless => (Icons.audio_file_outlined, 'FLAC 无损'),
    AudioQualityOption.lossless24 => (Icons.album_outlined, 'FLAC 24bit 臻品母带'),
    AudioQualityOption.hires => (Icons.speed_outlined, 'Hi-Res 高解析'),
  };
}

String qualityName(AudioQualityOption quality) {
  switch (quality) {
    case AudioQualityOption.low:
      return '标准 (128kbps)';
    case AudioQualityOption.high:
      return '超高品质 (320kbps)';
    case AudioQualityOption.lossless:
      return '无损 (FLAC)';
    case AudioQualityOption.lossless24:
      return '臻品母带 (FLAC 24bit)';
    case AudioQualityOption.hires:
      return 'Hi-Res';
  }
}
