import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/app_version.dart';
import '../../../core/card_expand.dart';
import '../../../core/io/bounded_input.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/storage/cache_maintenance_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_themes.dart';
import '../../../core/theme/glass_config.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/frosted_tab_header.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/widgets/root_shell_layout.dart';
import '../../../core/widgets/sleep_timer_sheet.dart';
import 'settings_provider.dart';
import '../../search/presentation/search_provider.dart';
import '../../playlist/data/playlist_repository.dart';
import '../../playlist/presentation/playlist_provider.dart';
import '../../player/platform/android_floating_player.dart';
import '../../player/domain/player_backdrop.dart';
import '../../player/presentation/player_backdrop_sheet.dart';
import '../../updates/presentation/update_sheet.dart';
import '../../player/presentation/player_provider.dart';
import '../../equalizer/presentation/equalizer_provider.dart';
import '../../download/presentation/download_provider.dart';
import '../domain/playlist_backup.dart';
import 'app_log_screen.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../../sync/data/sync_identity_store.dart';
import '../../nas/domain/nas_url.dart';
import '../../car_mode/presentation/car_mode_provider.dart';
import '../../car_mode/presentation/car_mode_sheet.dart';
import '../../custom_source/presentation/custom_source_provider.dart';
import '../../lyric/presentation/lyric_font_provider.dart';
import '../../local_music/presentation/scan_rules_sheet.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../domain/settings_reset.dart';
import 'settings_entry.dart';
import 'settings_search_layer.dart';
import 'settings_section_card.dart';
import 'package:koyze/core/widgets/koyze_modal.dart';

const double settingsOptionMaxWidth = 340;

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
  bool _searching = false;
  /// Runs a row picked from search. Search closes first so the page a row
  /// pushes — or the sheet it opens — is not fighting the layer for the
  /// keyboard and the back gesture.
  void _activateFromSearch(SettingsEntry entry) {
    // 开关行没有 onTap：以前这里直接 return，搜索里点一下完全没反应。
    // 就地翻转即可，搜索层留着，方便连着改几项。
    if (entry.isToggle) {
      entry.onToggle!(!(entry.toggleValue ?? false));
      return;
    }
    final action = entry.onTap;
    if (action == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _searching = false);
    action();
  }

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

  Future<void> _setFloatingPlayer(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    if (!value) {
      await ref.read(androidFloatingPlayerProvider.notifier).setEnabled(false);
      return;
    }
    const player = AndroidFloatingPlayer();
    if (await player.canDrawOverlays()) {
      await ref.read(androidFloatingPlayerProvider.notifier).setEnabled(true);
      return;
    }
    await player.requestPermission();
    if (!context.mounted) return;
    showAppNotification(S.of(context).floatingPlayerPermission);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isLandscapeShell = RootShellLayout.usesSideNavigationOf(context);
    final sections = _buildSections(context, ref, s);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            ShellContentFrame(
              // 这里**不要**再给整个 ListView 套 RepaintBoundary：那是把整页
              // 内容包成一个整屏高的超大图层，滚动时必然撑爆栅格缓存，等于
              // 每帧全页重画。分层交给下面的卡片（一卡一层）。
              child: ListView(
                // 每张分区卡片一层，而不是「每一行一层」。别改回行级边界。
                //
                // 这里踩过一次坑：曾经为了避开「整张卡太大、栅格缓存装不下」
                // 而把边界下沉到每一行（配合 `addRepaintBoundaries: false`
                // 手工包），结果正好相反——一屏十几行就是十几层，每层都要
                // 各自分配、缓存、上传一层纹理，合成开销压过了省下的重绘。
                //
                // 注意：当初支撑这个判断的「掉帧 47~56%」是**旧指标算错的**
                // （当时用 build+raster 之和判超预算，而这两条是并行的流水线，
                // 相加会系统性虚报，见 performance_monitor 里的说明）。排除
                // 那批数据之后，行级与卡级边界的差异并没有那么悬殊。
                //
                // 保留卡级分层是因为它同时满足三件事：图层数量少、单层面积
                // 有界、卡片底色/圆角/边线/分隔线画在同一层里不会出现拼缝；
                // 这不是「靠数字证明的最优解」，而是权衡后的稳定选择。
                addRepaintBoundaries: false,
                // 首屏之外的 30 来行在滑动时才第一次建 Element/RenderObject，
                // 那一帧的 build 会到 110ms（120Hz 上等于丢 13 帧）。
                //
                // 真机探针（5.2.9 探针包，iPhone 17 / 120Hz）：
                //   frames=282 worst=110.0ms build_p95=0.5 raster_p95=2.1
                // p95 是正常的、只有单帧离群，且 raster 一直很小——说明贵的是
                // UI 线程把那些行第一次建出来，不是光栅。
                //
                // 靠排版缓存解决不了这件事：TextPainter.layout 只让引擎记住
                // shaping 与字体回退，而 Element、RenderObject、Paragraph
                // 对象本身仍要现建。5.2.9 试过预排整页文本，对首滑没有改善，
                // 那段代码已经删掉——别再走这条路。
                //
                // 这里把视口外的预建范围放宽到覆盖整页（内容约 4 屏），
                // 代价转移到「打开设置页」那一帧。这是有意的取舍：转场动画里
                // 掉一帧，比手指按在屏幕上时卡一下容易被接受。
                cacheExtent: 5000,
                padding: EdgeInsets.only(
                  top: isLandscapeShell ? 0 : FrostedTabHeader.extent(context),
                  bottom: RootShellLayout.obscuredBottomOf(context),
                ),
                children: [
                  for (final section in sections)
                    // 一张卡一层：卡片底色、圆角、边线、分隔线和里面的
                    // 所有行一起进这一个图层。不要下沉到行级（原因见上）。
                    RepaintBoundary(
                      child: SettingsSectionCard(
                        title: section.title,
                        children: [
                          for (final leadIn in section.leadIn) leadIn,
                          for (final entry in section.entries)
                            _buildEntry(context, entry),
                        ],
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (_searching)
              Positioned.fill(
                child: SettingsSearchLayer(
                  sections: sections,
                  topInset: isLandscapeShell
                      ? 0
                      : FrostedTabHeader.extent(context),
                  bottomInset: RootShellLayout.obscuredBottomOf(context),
                  onClose: () => setState(() => _searching = false),
                  onActivate: _activateFromSearch,
                ),
              ),
            // 标题和右上角的搜索入口都交给根壳层：切 tab 时栏原地不动，
            // 只有文字和按钮换位置。
            RootHeaderPublisher(
              index: 3,
              title: s.settings,
              actions: [
                FrostedHeaderButton(
                  icon: _searching ? Icons.close_rounded : Icons.search_rounded,
                  semanticLabel: _searching ? s.cancel : s.settingsSearch,
                  onTap: () => setState(() => _searching = !_searching),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 设置项的唯一来源：页面按它渲染，搜索按它建索引。
  ///
  /// 以前每个入口都是 build 里手写的一行，加一项就得记得在两处改；现在
  /// 一张表同时喂给列表和搜索，谁都不会漏。
  List<SettingsSectionSpec> _buildSections(
    BuildContext context,
    WidgetRef ref,
    S s,
  ) {
    final themeMode = ref.watch(themeModeProvider);
    final audioQuality = ref.watch(audioQualityProvider);
    final language = ref.watch(appLanguageProvider);
    final backdropBlur = ref.watch(playerBackdropBlurProvider);
    final backdropScrim = ref.watch(playerBackdropScrimProvider);

    // 分组的依据是「用户对一首歌做了什么」，不是代码在哪个目录，也不是
    // 哪个功能顺手写在了这里。十个小节按一首歌的一生排下来：
    //
    //   音源（从哪来）→ 音乐库（存哪）→ 下载（怎么拿到本机）→ 播放（怎么听）
    //   → 歌词（听的时候看什么）→ 外观（长什么样）→ 数据（带走什么）
    //   → 通用（系统级开关与复位）→ 关于
    //
    // 三条硬规则，新增设置项时照这个走：
    //
    // 1. 区内先「内容」再「行为」再「场景」。播放区里音质、均衡器在前，
    //    淡入淡出这类行为开关居中，睡眠定时、车载、悬浮这类「什么时候、
    //    在哪听」压尾。
    // 2. 平台专属项一律放区内末尾。锁屏歌词全平台都有、桌面歌词只有
    //    Win/Linux 有，把锁屏歌词放前面，移动端和桌面端看到的前几项就一致。
    // 3. 越往下越重。语言 → 方向 → 动效 → 重置设置，破坏性最大的排最后，
    //    正好贴着「关于」，滑到底才会碰到。
    //
    // 歌词单独成区，是因为它同时被「播放」（开关）和「外观」（样式）牵扯，
    // 两边各放一半时用户只能靠猜。
    return [
      SettingsSectionSpec(
        title: s.aiSectionTitle,
        entries: [
          SettingsEntry(
            title: s.aiAssistantTitle,
            subtitle: s.aiAssistantSubtitle,
            keywords: const [
              'ai',
              '助手',
              'assistant',
              '智能',
              '对话',
              'chat',
              '模型',
              'model',
            ],
            onTap: () => context.push('/ai-assistant'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.aiSettingsTitle,
            subtitle: s.aiSettingsSubtitle,
            keywords: const [
              'ai',
              '设置',
              'settings',
              '密钥',
              'key',
              'api',
              '接口',
              'endpoint',
              '模型',
              'model',
            ],
            onTap: () => context.push('/ai-settings'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.aiSchedulesTitle,
            subtitle: s.aiSchedulesSubtitle,
            keywords: const [
              'ai',
              '定时',
              'schedule',
              '任务',
              'task',
              '自动化',
              'automation',
              '每天',
              '每周',
            ],
            onTap: () => context.push('/ai-schedules'),
            captureExpandOrigin: true,
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.sources,
        // 「从哪找歌」和「我的歌怎么组织」是两件事，以前挤在一格里，
        // 结果「默认搜索平台」跟「本地音乐目录」并排。拆开后这一格只剩
        // 内容来源：默认的、自己加的、自己建的。
        entries: [
          SettingsEntry(
            title: s.defaultSearchPlatform,
            subtitle: _platformName(ref.watch(defaultSearchPlatformProvider)),
            keywords: const [
              '搜索',
              'search',
              '平台',
              'platform',
              '默认',
              'default',
              '音源',
              'source',
            ],
            onTap: () => _showDefaultPlatformDialog(context, ref),
          ),
          SettingsEntry(
            title: s.customSources,
            // 副标题给的是「已经接了几个」，而不是把标题再说一遍。
            subtitle: switch (ref.watch(customSourcesProvider).length) {
              0 => s.customSourcesEmpty,
              final count => s.customSourcesCount(count),
            },
            keywords: const ['音源', 'source', '自定义', 'custom', '插件', 'plugin'],
            onTap: () => context.push('/custom-source'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.nasServer,
            subtitle: platformPickerDescription(
              'subsonic',
              locale: Localizations.localeOf(context),
            ),
            keywords: const ['nas', 'subsonic', '服务器', 'server', '乐库', '自建'],
            onTap: () => context.push('/subsonic-settings'),
            captureExpandOrigin: true,
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.musicLibrary,
        // 顺序就是「文件 → 规则 → 视图」：先定文件放哪（读的一端本地目录、
        // 写的一端下载目录），再定扫什么，最后才是歌单这种派生出来的视图。
        //
        // 「下载目录」不再单独占一行：它已经进了「本地音乐目录」页面（那一页
        // 列出的正是"这个库由哪些目录组成"，下载目录本来就在里面，而且不能
        // 手动移除）。设置页这层再摆一行，等于同一个目录有两个入口，用户还得
        // 猜哪个才是"真正的"设置。
        entries: [
          SettingsEntry(
            title: s.localLibrary,
            subtitle: s.localLibrarySubtitle,
            keywords: const [
              '本地',
              'local',
              '扫描',
              'scan',
              '文件夹',
              'folder',
              '音乐库',
              'library',
              // 下载目录已经收进这一页，搜「下载目录 / 保存位置」也应该能找到
              // 入口，否则从设置页删掉那一行之后它就彻底搜不到了。
              '下载',
              'download',
              '目录',
              'directory',
              '路径',
              'path',
              '保存位置',
            ],
            onTap: () => context.push('/local-music'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.scanRules,
            subtitle: s.scanRulesSubtitle,
            keywords: const [
              '扫描',
              'scan',
              '过滤',
              'filter',
              '重复',
              'duplicate',
              '时长',
              'duration',
              '排除',
              'exclude',
            ],
            onTap: () => showScanRulesSheet(context, ref),
          ),
          SettingsEntry(
            title: s.smartPlaylists,
            subtitle: s.smartPlaylistsSubtitle,
            keywords: const [
              '智能',
              'smart',
              '歌单',
              'playlist',
              '规则',
              'rule',
              '最近添加',
              '最常播放',
            ],
            onTap: () => context.push('/smart-playlists'),
            captureExpandOrigin: true,
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.downloads,
        // 这里只管「怎么下」：看任务 → 定质量 → 限网络。位置已经归音乐库。
        entries: [
          SettingsEntry(
            title: s.downloadManager,
            subtitle: s.downloadManagerSubtitle,
            keywords: const ['下载', 'download', '任务', '队列', 'queue'],
            onTap: () => context.push('/download'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.downloadQuality,
            subtitle: _getQualityName(ref.watch(downloadQualityProvider)),
            keywords: const [
              '下载音质',
              'download',
              'quality',
              '码率',
              'bitrate',
              '无损',
            ],
            onTap: () => _showDownloadQualityDialog(context, ref),
          ),
          SettingsEntry(
            title: s.wifiOnly,
            subtitle: s.wifiOnlySubtitle,
            keywords: const ['wifi', '无线', '流量', 'data', '网络', 'network', '下载'],
            toggleValue: ref.watch(wifiOnlyDownloadProvider),
            onToggle: (value) {
              ref.read(wifiOnlyDownloadProvider.notifier).setWifiOnly(value);
              ref.read(setWifiOnlyDownloadProvider)(value);
            },
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.playback,
        entries: [
          SettingsEntry(
            title: s.audioQuality,
            subtitle: _getQualityName(audioQuality),
            keywords: const [
              '音质',
              'quality',
              '码率',
              'bitrate',
              '无损',
              'flac',
              'hires',
              '音效',
            ],
            onTap: () => _showAudioQualityDialog(context, ref),
          ),
          // 均衡器紧跟音质：这两项改的都是「声音本身」，剩下的是播放行为。
          SettingsEntry(
            title: s.equalizer,
            subtitle: equalizerSubtitle(
              ref.watch(equalizerProvider),
              locale: Localizations.localeOf(context),
            ),
            keywords: const [
              '均衡器',
              'equalizer',
              'eq',
              '音效',
              '低音',
              'bass',
              '频段',
            ],
            onTap: () => context.push('/equalizer'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.playbackFade,
            subtitle: s.playbackFadeSubtitle,
            keywords: const ['淡入', '淡出', 'fade', '爆音', 'pop', '渐变', 'ramp'],
            toggleValue: ref.watch(playbackFadeEnabledProvider),
            onToggle: (value) {
              ref.read(playbackFadeEnabledProvider.notifier).setEnabled(value);
            },
          ),
          SettingsEntry(
            title: s.skipSilence,
            subtitle: s.skipSilenceSubtitle,
            keywords: const ['静音', 'silence', '跳过', 'skip', '空白', 'gapless'],
            toggleValue: ref.watch(skipSilenceEnabledProvider),
            onToggle: (value) {
              ref.read(skipSilenceEnabledProvider.notifier).setEnabled(value);
            },
          ),
          SettingsEntry(
            title: s.replayGain,
            subtitle: s.replayGainSubtitle,
            keywords: const [
              '响度',
              'replaygain',
              '音量',
              'volume',
              '均衡',
              'loudness',
              '归一',
            ],
            toggleValue: ref.watch(replayGainEnabledProvider),
            onToggle: (value) {
              ref.read(replayGainEnabledProvider.notifier).setEnabled(value);
            },
          ),
          SettingsEntry(
            title: s.autoResume,
            subtitle: s.autoResumeSubtitle,
            keywords: const ['续播', 'resume', 'autoplay', '自动播放', '接着播'],
            toggleValue: ref.watch(autoResumePlaybackProvider),
            onToggle: (value) {
              ref
                  .read(autoResumePlaybackProvider.notifier)
                  .setAutoResume(value);
            },
          ),
          SettingsEntry(
            title: s.precacheRecent,
            subtitle: s.precacheRecentSubtitle,
            keywords: const [
              '预缓存',
              'precache',
              '缓存',
              'cache',
              '常听',
              'frequent',
              '下载',
            ],
            toggleValue: ref.watch(precacheEnabledProvider),
            onToggle: (value) {
              ref.read(precacheEnabledProvider.notifier).setEnabled(value);
            },
          ),
          if (ref.watch(precacheEnabledProvider))
            SettingsEntry(
              title: s.precacheCount,
              subtitle: s.precacheCountValue(ref.watch(precacheCountProvider)),
              keywords: const ['数量', 'count', '预缓存', 'precache'],
              onTap: () => _showPrecacheCountDialog(context, ref),
            ),
          SettingsEntry(
            title: s.sleepTimer,
            subtitle: sleepTimerSubtitle(
              ref.watch(sleepTimerProvider),
              locale: Localizations.localeOf(context),
            ),
            keywords: const ['睡眠', 'sleep', '定时', 'timer', '关闭播放', '睡前'],
            onTap: () => _showSleepTimerMenu(context, ref),
            trailing: _sleepTimerTrailing(context, ref, s),
          ),
          SettingsEntry(
            title: s.carMode,
            subtitle: carModeStatusText(ref.watch(carConnectionProvider), s),
            keywords: const ['车机', 'car', 'hicar', '车载', '投屏', '驾驶'],
            onTap: () => showCarModeSheet(context, ref),
          ),
          if (androidFloatingPlayerSupported)
            SettingsEntry(
              title: s.floatingPlayer,
              subtitle: s.floatingPlayerSubtitle,
              keywords: const ['悬浮', 'floating', '浮窗', 'overlay', '小窗', '桌面'],
              toggleValue: ref.watch(androidFloatingPlayerProvider),
              onToggle: (value) => _setFloatingPlayer(context, ref, value),
            ),
        ],
      ),
      SettingsSectionSpec(
        title: s.lyrics,
        // 以前这四项一半在「播放」（三个开关）、一半在「外观」（样式页），
        // 找「歌词怎么调」得先猜它在哪一边。现在样式在前，开关在后，
        // 平台专属的两个再往后。
        entries: [
          SettingsEntry(
            title: s.lyricDisplay,
            subtitle: s.lyricDisplaySubtitle,
            keywords: const [
              '歌词',
              'lyric',
              '偏移',
              'offset',
              '对不上',
              '延迟',
              'delay',
              '字号',
              'font',
              '字体',
              'typeface',
              '大小',
              'size',
              '模糊',
              'blur',
              '景深',
              '翻译',
              'translation',
            ],
            onTap: () => context.push('/lyric-display'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.lockScreenLyric,
            subtitle: s.lockScreenLyricSubtitle,
            keywords: const [
              '歌词',
              'lyric',
              '桌面歌词',
              'desktop lyrics',
              '锁屏',
              'lock',
              '通知栏',
              'notification',
            ],
            toggleValue: ref.watch(lockScreenLyricEnabledProvider),
            onToggle: (value) {
              ref
                  .read(lockScreenLyricEnabledProvider.notifier)
                  .setEnabled(value);
            },
          ),
          if (Platform.isWindows || Platform.isLinux) ...[
            SettingsEntry(
              title: s.desktopLyricWindow,
              subtitle: s.desktopLyricWindowSubtitle,
              keywords: const ['桌面歌词', 'desktop lyrics', '歌词窗', 'overlay'],
              toggleValue: ref.watch(desktopLyricEnabledProvider),
              onToggle: (value) => ref
                  .read(desktopLyricEnabledProvider.notifier)
                  .setEnabled(value),
            ),
            // 锁定只在窗口开着时有意义，紧跟父项，不单独成行。
            if (ref.watch(desktopLyricEnabledProvider))
              SettingsEntry(
                title: s.desktopLyricLock,
                subtitle: s.desktopLyricLockSubtitle,
                keywords: const ['锁定歌词窗', 'click through', '穿透'],
                toggleValue: ref.watch(desktopLyricLockedProvider),
                onToggle: (value) => ref
                    .read(desktopLyricLockedProvider.notifier)
                    .setLocked(value),
              ),
          ],
        ],
      ),
      SettingsSectionSpec(
        title: s.appearance,
        // 面板浓度直接在列表里调：拖动时周围的分区卡片就是预览，不用另开
        // 一个"看不见变化"的弹层。
        leadIn: const [_GlassOpacitySlider(), _GlassBlurSlider()],
        entries: [
          SettingsEntry(
            title: s.themeColor,
            subtitle: s.themeColorSubtitle,
            keywords: const [
              '主题',
              'theme',
              '颜色',
              'color',
              '配色',
              'accent',
              '强调色',
            ],
            onTap: () => _showThemeColorDialog(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: ref.watch(accentColorProvider),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cardBorder(context)),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: AppColors.mutedText(context)),
              ],
            ),
          ),
          // 紧跟主题色：它改的是同一个强调色，只是来源换成了封面。
          SettingsEntry(
            title: s.accentFollowsCover,
            subtitle: s.accentFollowsCoverSubtitle,
            keywords: const [
              '封面',
              'cover',
              '取色',
              'palette',
              '跟随',
              'follow',
              '配色',
              'accent',
              'artwork',
            ],
            toggleValue: ref.watch(coverThemedAccentProvider),
            onToggle: (value) =>
                ref.read(coverThemedAccentProvider.notifier).setEnabled(value),
          ),
          SettingsEntry(
            title: s.themeModeRow,
            subtitle: switch (themeMode) {
              ThemeMode.light => s.lightMode,
              ThemeMode.dark => s.darkMode,
              ThemeMode.system => s.followSystem,
            },
            keywords: const [
              '深色',
              'dark',
              '夜间',
              'night',
              '浅色',
              'light',
              '主题',
              'theme',
              '跟随',
              'system',
              '自动',
            ],
            onTap: () => showKoyzeSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _ThemeModePickerDialog(),
            ),
          ),
          SettingsEntry(
            title: s.playerBackdrop,
            subtitle: s.playerBackdropSubtitle,
            keywords: const [
              '背景',
              'background',
              '模糊',
              'blur',
              '遮罩',
              'scrim',
              '透明度',
              'opacity',
              '播放页',
              '封面',
              'cover',
              '虚化',
            ],
            onTap: () => showPlayerBackdropSheet(context),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // 光写「60 · 80%」看不出哪个是哪个，按行的副标题顺序标出来。
                  '${s.backdropBlurShort} ${PlayerBackdrop.blurLabel(backdropBlur)}'
                  ' · '
                  '${s.backdropScrimShort} ${PlayerBackdrop.scrimLabel(backdropScrim)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.mutedText(context),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: AppColors.mutedText(context)),
              ],
            ),
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.dataAndSync,
        // 云 → 统计 → 导出 → 导入 → 清缓存：都是「我的数据」，从云端看到
        // 本机，从搬走看到清掉。
        entries: [
          SettingsEntry(
            title: s.cloudAccount,
            subtitle: s.cloudAccountSubtitle,
            keywords: const ['同步', 'sync', '账号', 'account', '云端', 'cloud'],
            onTap: () => context.push('/sync'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.listeningStats,
            subtitle: s.listeningStatsSubtitle,
            keywords: const ['统计', 'stats', '听歌', '报告', 'report', '数据'],
            onTap: () => context.push('/stats'),
            captureExpandOrigin: true,
          ),
          SettingsEntry(
            title: s.backup,
            subtitle: s.backupSubtitle,
            keywords: const ['备份', 'backup', '导出', 'export', '数据', 'data'],
            onTap: () => _backupData(context, ref),
          ),
          SettingsEntry(
            title: s.restore,
            subtitle: s.restoreSubtitle,
            keywords: const ['恢复', 'restore', '导入', 'import', '数据', 'data'],
            onTap: () => _restoreData(context, ref),
          ),
          SettingsEntry(
            title: s.clearCache,
            subtitle: s.clearCacheSubtitle,
            keywords: const ['缓存', 'cache', '清理', 'clean', '空间', 'storage'],
            onTap: () => _clearCache(context, ref),
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.general,
        // 系统级、与听歌无关的开关，再往下就只剩「关于」。重置排最后：
        // 它前面每一项都是可以撤销的，它自己不是。
        entries: [
          SettingsEntry(
            title: s.language,
            subtitle: s.languageName(language),
            keywords: const ['语言', 'language', '中文', 'english', '英文', '简体'],
            onTap: () => _showLanguageDialog(context),
          ),
          SettingsEntry(
            title: s.forceLandscape,
            subtitle: s.forceLandscapeSubtitle,
            keywords: const [
              '横屏',
              'landscape',
              '旋转',
              'rotate',
              '方向',
              'orientation',
            ],
            toggleValue: ref.watch(forceLandscapeProvider),
            onToggle: (value) {
              ref.read(forceLandscapeProvider.notifier).setEnabled(value);
            },
          ),
          SettingsEntry(
            title: s.simplifyEffects,
            subtitle: s.simplifyEffectsSubtitle,
            keywords: const [
              '动效',
              'effects',
              '动画',
              'animation',
              '流畅',
              '性能',
              'performance',
            ],
            toggleValue: ref.watch(simplifyEffectsProvider),
            onToggle: (value) {
              ref.read(simplifyEffectsProvider.notifier).setEnabled(value);
            },
          ),
          SettingsEntry(
            title: s.resetSettings,
            subtitle: s.resetSettingsSubtitle,
            keywords: const [
              '重置',
              'reset',
              '默认',
              'default',
              '恢复',
              'restore',
              '设置',
            ],
            onTap: () => _resetPreferences(context, ref),
          ),
        ],
      ),
      SettingsSectionSpec(
        title: s.about,
        leadIn: [
          _SettingRow(name: s.version, value: kAppVersionLabel),
          _DeviceIdRow(
            deviceId: ref.watch(settingsDeviceIdProvider).valueOrNull,
          ),
        ],
        entries: [
          if (Platform.isAndroid)
            SettingsEntry(
              title: s.checkUpdates,
              // 版本号已经由上面那张「版本」行给出，这里再写一遍只是重复。
              subtitle: '',
              keywords: const [
                '更新',
                'update',
                '升级',
                'upgrade',
                '版本',
                'version',
                '新版本',
              ],
              onTap: () => showUpdateSheet(context),
            ),
          SettingsEntry(
            title: s.diagnostics,
            subtitle: s.diagnosticsSubtitle,
            keywords: const [
              '日志',
              'log',
              '诊断',
              'diagnostics',
              '反馈',
              'feedback',
              '排查',
            ],
            onTap: () => showDiagnosticLogOverlay(context),
          ),
          SettingsEntry(
            title: s.termsTitle,
            subtitle: s.termsEntrySubtitle,
            keywords: const [
              '条款',
              'terms',
              '免责',
              'disclaimer',
              '隐私',
              'privacy',
              '协议',
              'license',
              '版权',
              'copyright',
            ],
            onTap: () => context.push('/terms'),
            captureExpandOrigin: true,
          ),
        ],
      ),
    ];
  }

  /// 一行的渲染入口。列表在调用处给每一行套一层 [RepaintBoundary]（见
  /// build 里 `addRepaintBoundaries: false` 的注释），这里只管内容。
  Widget _buildEntry(BuildContext context, SettingsEntry entry) {
    if (entry.isToggle) {
      return _buildSwitchTile(
        context,
        entry.title,
        entry.subtitle,
        entry.toggleValue!,
        entry.onToggle!,
      );
    }
    return _SettingsNavTile(
      title: entry.title,
      subtitle: entry.subtitle,
      onTap: entry.onTap ?? () {},
      trailing: entry.trailing,
      captureExpandOrigin: entry.captureExpandOrigin,
    );
  }

  /// 睡眠定时开着时，行尾给一颗「取消」；其余时候这把位子留空。
  Widget? _sleepTimerTrailing(BuildContext context, WidgetRef ref, S s) {
    if (ref.watch(sleepTimerProvider) is! SleepTimerRunning) return null;
    return TextButton(
      onPressed: () {
        ref.read(sleepTimerProvider.notifier).cancelTimer();
        showAppNotification(
          s.sleepTimerCancelled,
          type: AppNotificationType.success,
        );
      },
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: AppColors.accentOf(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_outlined, size: 16),
          const SizedBox(width: 4),
          Text(s.cancel, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  /// 带开关的一行。
  ///
  /// 整行都能点：以前只有右边那颗开关能吃点击，用户按习惯点标题（尤其是
  /// 手指落在副标题上）完全没反应，看起来就像「这个设置不起作用」。
  /// 现在和系统 `SwitchListTile` 一样，点行任意位置都翻转。
  ///
  /// 开关本身套 `IgnorePointer`：它的手势交给外层这一层统一处理，否则按在
  /// 开关上会连着触发两次（先开关、再整行），切回去等于没变。
  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    void toggle() => onChanged(!value);
    return MergeSemantics(
      child: InkWell(
        onTap: toggle,
        // 卡片不再裁剪内容，水波纹自己按卡片圆角收边（见 kSettingsCardRadius）。
        customBorder: const RoundedRectangleBorder(
          borderRadius: kSettingsCardRadius,
        ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: settingsRowTitleStyle(
                        AppColors.onScaffold(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: settingsRowSubtitleStyle(
                          AppColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IgnorePointer(
                child: FxSwitch(value: value, onChanged: onChanged),
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
    showKoyzeSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PlatformPickerDialog(),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showKoyzeSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LanguagePickerDialog(),
    );
  }

  void _showThemeColorDialog(BuildContext context) {
    showKoyzeSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ThemeColorPickerDialog(),
    );
  }

  void _showAudioQualityDialog(BuildContext context, WidgetRef ref) {
    _showQualityDialog(context, ref, S.of(context).chooseQuality, false);
  }

  void _showPrecacheCountDialog(BuildContext context, WidgetRef ref) {
    showKoyzeSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PrecacheCountPicker(title: S.of(context).precacheCount),
    );
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
    showKoyzeSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _QualityPickerDialog(title: title, isDownload: isDownload),
    );
  }

  Future<void> _resetPreferences(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);
    final confirmed = await showKoyzeDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.resetSettings),
        content: Text(s.resetSettingsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.resetSettingsAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final storage = await StorageService.instance;
      final hadCustomDownloadDirectory =
          ref.read(downloadDirectoryProvider) != null;
      final removed = await resetPreferences(storage);
      // 下载目录是「运行中的服务 + 持久化设置」两份状态，只删存储的话，
      // 本次进程还会继续往旧的目录里写，界面上也还显示旧路径。这里补一次
      // 真正的切换（失败就保持现状，不影响其它项已恢复的默认值）。
      if (hadCustomDownloadDirectory) {
        try {
          await ref.read(switchDownloadDirectoryProvider)(null);
        } catch (error) {
          AppLog.instance.record(
            'settings.reset',
            'restoring the default download directory failed: $error',
            level: AppLogLevel.warning,
          );
        }
      }
      // 通知每个设置项重新读取：它们各自持有内存值，只删存储不会刷新界面。
      for (final provider in <ProviderOrFamily>[
        themeModeProvider,
        accentColorProvider,
        audioQualityProvider,
        downloadQualityProvider,
        wifiOnlyDownloadProvider,
        autoResumePlaybackProvider,
        androidFloatingPlayerProvider,
        forceLandscapeProvider,
        simplifyEffectsProvider,
        playbackVolumeProvider,
        playbackSpeedProvider,
        pitchSemitonesProvider,
        skipSilenceEnabledProvider,
        playbackFadeEnabledProvider,
        replayGainEnabledProvider,
        lockScreenLyricEnabledProvider,
        desktopLyricEnabledProvider,
        desktopLyricLockedProvider,
        desktopLyricFontSizeProvider,
        precacheEnabledProvider,
        precacheCountProvider,
        defaultSearchPlatformProvider,
        playerBackdropBlurProvider,
        playerBackdropScrimProvider,
        glassOpacityProvider,
        equalizerProvider,
        localMusicLibraryProvider,
        // 歌词与外观：这些键现在也会被清掉，不重新读一遍会留着内存里的旧值，
        // 界面上看起来就是「点了恢复默认，但有的项没变」。
        lyricOffsetProvider,
        lyricScaleProvider,
        lyricAlignProvider,
        lyricTranslationProvider,
        lyricBlurProvider,
        lyricEntranceProvider,
        coverThemedAccentProvider,
        flowingBackdropProvider,
        carModePreferenceProvider,
        lyricFontProvider,
      ]) {
        ref.invalidate(provider);
      }
      if (!context.mounted) return;
      showAppNotification(
        s.resetSettingsDone(removed),
        type: AppNotificationType.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppNotification(
        s.resetSettingsFailed('$error'),
        type: AppNotificationType.error,
      );
    }
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
    final confirmed = await showKoyzeDialog<Set<AppCacheCategory>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final allSelected = selected.length == AppCacheCategory.values.length;
          final selectAllValue = allSelected
              ? true
              : selected.isEmpty
              ? false
              : null;
          return KoyzeDialog(
            backgroundColor: AppColors.dialogBg(context),
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

class _SettingsNavTile extends StatefulWidget {
  const _SettingsNavTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.captureExpandOrigin = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool captureExpandOrigin;

  @override
  State<_SettingsNavTile> createState() => _SettingsNavTileState();
}

class _SettingsNavTileState extends State<_SettingsNavTile> {
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final tile = InkWell(
      // 同 _buildSwitchTile：水波纹按卡片圆角自己收边。
      customBorder: const RoundedRectangleBorder(
        borderRadius: kSettingsCardRadius,
      ),
      onTap: widget.captureExpandOrigin
          ? () async {
              final anchor = _anchorKey.currentContext;
              if (anchor != null) await captureCardExpandOrigin(anchor);
              if (context.mounted) widget.onTap();
            }
          : widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: settingsRowTitleStyle(
                      AppColors.onScaffold(context),
                    ),
                  ),
                  if (widget.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: settingsRowSubtitleStyle(
                        AppColors.secondaryText(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            widget.trailing ??
                Icon(Icons.chevron_right, color: AppColors.mutedText(context)),
          ],
        ),
      ),
    );
    if (!widget.captureExpandOrigin) return tile;
    return RepaintBoundary(key: _anchorKey, child: tile);
  }
}

/// 外观分区顶部的一枚「标题 + 说明 + 百分比 + 滑杆」控件。
///
/// 不透明度和虚化长得一样，只有文案、区间、落点不同，抽出来免得两份重复代码
/// 各自漂移。
class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String subtitle;
  final double value;
  final double min;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final percent = '${(value * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onScaffold(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: AppColors.secondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                percent,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondaryText(context),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, 1.0),
            min: min,
            max: 1,
            // 5% 一档：再细就找不到"刚好看得清"的位置了。
            divisions: divisions,
            label: percent,
            onChanged: onChanged,
            onChangeEnd: (_) => onChangeEnd(),
          ),
        ],
      ),
    );
  }
}

/// 「界面不透明度」滑杆。
///
/// 这一档统一缩放玻璃面的染色浓度：拖动时设置页自己的分区卡片就是预览，
/// 所以不需要单独的面板。
class _GlassOpacitySlider extends ConsumerWidget {
  const _GlassOpacitySlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return _GlassSlider(
      title: s.glassOpacity,
      subtitle: s.glassOpacitySubtitle,
      value: ref.watch(glassOpacityProvider),
      min: GlassEffectConfig.minSurfaceOpacity,
      divisions: 14,
      onChanged: (next) {
        // 立刻写进静态配置，同一帧里周围的面板就跟着变。
        GlassEffectConfig.setSurfaceOpacity(next);
        ref.read(glassOpacityProvider.notifier).setOpacity(next);
      },
      onChangeEnd: () => ref.read(glassOpacityProvider.notifier).flush(),
    );
  }
}

/// 「虚化」滑杆。
///
/// 与不透明度是一对：不透明度决定「透多少」，虚化决定「透过来的东西糊不糊」。
/// 出厂 0% 即不采样背后，和这一档上线前的观感完全一致。
class _GlassBlurSlider extends ConsumerWidget {
  const _GlassBlurSlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return _GlassSlider(
      title: s.glassBlur,
      subtitle: s.glassBlurSubtitle,
      value: ref.watch(glassBlurProvider),
      min: GlassEffectConfig.minSurfaceBlur,
      divisions: 20,
      onChanged: (next) {
        GlassEffectConfig.setSurfaceBlur(next);
        ref.read(glassBlurProvider.notifier).setBlur(next);
      },
      onChangeEnd: () => ref.read(glassBlurProvider.notifier).flush(),
    );
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
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: AppColors.onScaffold(context),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.secondaryText(context),
            ),
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
      customBorder: const RoundedRectangleBorder(
        borderRadius: kSettingsCardRadius,
      ),
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
                fontSize: 14.5,
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

/// Settings pickers share one content rail and one header. The outer glass
/// surface is supplied by [KoyzeDialog], so a picker never nests another glass
/// card inside the modal.
class _SettingsOptionPanel extends StatelessWidget {
  const _SettingsOptionPanel({
    required this.title,
    required this.child,
    this.maxHeight,
  });

  final String title;
  final Widget child;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    // 选择面板保持 iOS 的轻量标题区：没有额外的粗横线，
    // 只用标题、关闭按钮和玻璃边缘来表达层级。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(title: title, onClose: () => Navigator.pop(context)),
        Flexible(
          child: maxHeight == null
              ? child
              : ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight!),
                  child: child,
                ),
        ),
        const SizedBox(height: 4),
      ],
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
    return _SettingsOptionPanel(
      title: S.of(context).defaultSearchPlatform,
      maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: options.length,
        itemBuilder: (context, index) {
          final id = options[index].id;
          return _SettingsOptionTile(
            icon: platformPickerIcon(id),
            name: platformDisplayName(
              id,
              locale: Localizations.localeOf(context),
            ),
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
              ref.read(selectedSourceIdProvider.notifier).state = platform;
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

IconData platformPickerIcon(String id) {
  return switch (canonicalSearchPlatform(id)) {
    'tx' => Icons.music_note_rounded,
    'kw' => Icons.headphones_rounded,
    'wy' => Icons.cloud_rounded,
    'kg' => Icons.graphic_eq_rounded,
    'local' => Icons.folder_rounded,
    'favorites' => Icons.favorite_rounded,
    'subsonic' => Icons.cloud_queue_rounded,
    _ => Icons.dns_rounded,
  };
}

class _SettingsOptionTile extends StatelessWidget {
  const _SettingsOptionTile({
    required this.icon,
    required this.name,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String name;
  final String description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    // 选中态学 Origo 的菜单：整行铺一层很淡的强调色，文字转强调色，
    // 右侧只留一个勾。原来那颗"实心绿方块 + 黑勾"在玻璃上太重，
    // 也把行尾压得比行首还显眼。
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: isDark ? 0.14 : 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              // 选中态只加一道极细的强调色描边：玻璃底上放大色块会脏，
              // 一道 0.9pt 的边就足够把这一行从列表里拎出来。
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: isDark ? 0.26 : 0.20)
                    : Colors.transparent,
                width: 0.9,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: isDark ? 0.20 : 0.16)
                        : AppColors.fill(context),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    color: selected ? accent : AppColors.mutedText(context),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? accent
                              : AppColors.onScaffold(context),
                          fontSize: 14.5,
                          height: 1.15,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.secondaryText(context),
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: AnimatedScale(
                    scale: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Icon(Icons.check_rounded, size: 20, color: accent),
                  ),
                ),
              ],
            ),
          ),
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
    return _SettingsOptionPanel(
      title: title,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          ...AudioQualityOption.values.map((quality) {
            final selected = currentQuality == quality;
            final accent = AppColors.accentOf(context);
            final meta = _qualityMeta(
              quality,
              locale: Localizations.localeOf(context),
            );
            return _SettingsOptionTile(
              icon: meta.$1,
              name: qualityName(
                quality,
                locale: Localizations.localeOf(context),
              ),
              description: meta.$2,
              selected: selected,
              accent: accent,
              onTap: () {
                if (isDownload) {
                  ref
                      .read(downloadQualityProvider.notifier)
                      .setQuality(quality);
                } else {
                  ref.read(audioQualityProvider.notifier).setQuality(quality);
                }
                Navigator.pop(context);
              },
            );
          }),
        ],
      ),
    );
  }
}

/// 预缓存数量选择：只给离散档位，避免用户填出「3 首」这种既不省流量
/// 也换不来体验的中间值。
class _PrecacheCountPicker extends ConsumerWidget {
  const _PrecacheCountPicker({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(precacheCountProvider);
    return _SettingsOptionPanel(
      title: title,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          for (final count in kPrecacheCountSteps)
            _SettingsOptionTile(
              icon: Icons.download_for_offline_outlined,
              name: S.of(context).precacheCountValue(count),
              // 按 320k 平均一首 8MB 估个量级，比只写数字更能说明代价。
              description: '≈ ${count * 8} MB',
              selected: count == current,
              accent: AppColors.accentOf(context),
              onTap: () {
                ref.read(precacheCountProvider.notifier).setCount(count);
                Navigator.pop(context);
              },
            ),
        ],
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
    case 'kg':
      return en ? 'Kugou' : '酷狗';
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
    case 'kg':
      return en ? 'Kugou Music source' : '酷狗音乐源';
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

IconData languagePickerIcon(AppLanguage language) {
  return switch (language) {
    AppLanguage.system => Icons.language_rounded,
    AppLanguage.zh => Icons.translate_rounded,
    AppLanguage.en => Icons.translate_rounded,
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

/// 主题：浅色 / 深色 / 跟随系统，三选一。
///
/// 以前是两个并列开关（「深色模式」「跟随系统」）驱动同一个三态值：拨「跟随
/// 系统」会让「深色模式」自己弹回去，拨「深色模式」又会把「跟随系统」关掉。
/// 用户看到的是两个开关互相打架，反馈成「设置不起作用」。三态本来就是单选。
class _ThemeModePickerDialog extends ConsumerWidget {
  const _ThemeModePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    final options = <(ThemeMode, IconData, String, String)>[
      (
        ThemeMode.light,
        Icons.light_mode_rounded,
        s.lightMode,
        s.lightModeSubtitle,
      ),
      (ThemeMode.dark, Icons.dark_mode_rounded, s.darkMode, s.darkModeSubtitle),
      (
        ThemeMode.system,
        Icons.brightness_auto_rounded,
        s.followSystem,
        s.followSystemThemeSubtitle,
      ),
    ];
    return _SettingsOptionPanel(
      title: s.themeModeRow,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final option in options)
            _SettingsOptionTile(
              icon: option.$2,
              name: option.$3,
              description: option.$4,
              selected: current == option.$1,
              accent: accent,
              onTap: () {
                ref.read(themeModeProvider.notifier).setThemeMode(option.$1);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
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
    return _SettingsOptionPanel(
      title: s.language,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final option in options)
            _SettingsOptionTile(
              icon: languagePickerIcon(option.$1),
              name: option.$2,
              description: option.$3,
              selected: current == option.$1,
              accent: accent,
              onTap: () {
                ref.read(appLanguageProvider.notifier).setLanguage(option.$1);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

/// 主题色选择：origo-x 的强调色列表，选一个就换整套 M3 色板。
class _ThemeColorPickerDialog extends ConsumerWidget {
  const _ThemeColorPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(accentColorProvider);
    return _SettingsOptionPanel(
      title: S.of(context).themeColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final color in AppThemes.accentColors)
              _AccentSwatch(
                color: color,
                selected: current.toARGB32() == color.toARGB32(),
                onTap: () {
                  ref.read(accentColorProvider.notifier).setAccentColor(color);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? AppColors.onScaffold(context)
                  : AppColors.cardBorder(context),
              width: selected ? 2 : 1,
            ),
          ),
          child: selected
              // 勾号跟着色块明暗走：亮黄、亮橙上用白勾等于没画。
              ? Icon(
                  Icons.check,
                  size: 18,
                  color: AppThemes.onAccentColor(color),
                )
              : null,
        ),
      ),
    );
  }
}
