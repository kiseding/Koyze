import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/download_service.dart';
import '../domain/download_task.dart';
import '../../player/domain/music_item.dart';
import '../../local_music/presentation/local_music_provider.dart';
import '../../search/presentation/search_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../startup_lifecycle.dart';
import '../../../core/logging/app_log.dart';

final downloadServiceProvider = Provider<DownloadService>((ref) {
  // Startup hydrates these notifiers before constructing the service. Do not
  // watch them here: rebuilding the provider would cancel active downloads.
  final wifiOnly = ref.read(wifiOnlyDownloadProvider);
  // 目录只在创建时读一次；之后改设置走 switchDownloadDirectoryProvider，
  // 那条路径会同时更新运行中的服务，不需要重建 provider（重建会中断下载）。
  final customDirectory = ref.read(downloadDirectoryProvider);
  final connectivity = Connectivity();
  final service = DownloadService(
    customDownloadDirectory: customDirectory,
    wifiOnly: wifiOnly,
    connectivity: connectivity.onConnectivityChanged.map((results) {
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return DownloadNetwork.wifi;
      }
      if (results.contains(ConnectivityResult.none)) {
        return DownloadNetwork.none;
      }
      return DownloadNetwork.mobile;
    }),
    currentNetwork: () async {
      final results = await connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return DownloadNetwork.wifi;
      }
      if (results.contains(ConnectivityResult.none)) {
        return DownloadNetwork.none;
      }
      return DownloadNetwork.mobile;
    },
  );
  final musicSourceService = ref.watch(musicSourceServiceProvider);
  final disposals = ref.read(resourceDisposalTrackerProvider);
  final disposeService = disposals.register(service.dispose);
  service.setMusicSourceService(musicSourceService);
  final sub = service.tasksStream.listen((_) {
    Future.microtask(() {
      try {
        ref.read(downloadVersionProvider.notifier).state++;
      } catch (error) {
        AppLog.instance.record('download.ui', 'refreshing download list after task event failed: $error', level: AppLogLevel.info);
      }
    });
  });
  ref.onDispose(() {
    sub.cancel();
    disposeService();
  });
  return service;
});

// 同步「仅 WiFi 下载」到下载服务（服务实例保持存活）
final setWifiOnlyDownloadProvider = Provider<void Function(bool)>((ref) {
  return (value) {
    ref.read(downloadServiceProvider).setWifiOnly(value);
  };
});

// 版本号，用于触发 UI 刷新
final downloadVersionProvider = StateProvider<int>((ref) => 0);

// 下载任务列表（同步读取，通过版本号触发刷新）
final downloadTasksProvider = Provider<List<DownloadTask>>((ref) {
  ref.watch(downloadVersionProvider);
  final downloadService = ref.watch(downloadServiceProvider);
  return downloadService.tasks;
});

final downloadCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.where((t) => t.status == DownloadStatus.downloading).length;
});

final downloadedCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks.where((t) => t.status == DownloadStatus.completed).length;
});

// 下载歌曲，使用 downloadQuality 设置
final downloadSongProvider = Provider<Future<void> Function(MusicItem)>((ref) {
  return (MusicItem music) async {
    final downloadService = ref.read(downloadServiceProvider);
    final qualityOption = ref.read(downloadQualityProvider);
    const qualityMap = {
      AudioQualityOption.low: '128k',
      AudioQualityOption.high: '320k',
      AudioQualityOption.lossless: 'flac',
      AudioQualityOption.lossless24: 'flac24bit',
      AudioQualityOption.hires: 'hires',
    };
    await downloadService.addTask(
      music,
      quality: qualityMap[qualityOption] ?? '320k',
    );
    ref.read(downloadVersionProvider.notifier).state++;
  };
});

// 下载操作（暂停/恢复/取消/重试/删除），操作后刷新 UI
final downloadActionProvider =
    Provider<void Function(String action, String taskId)>((ref) {
      return (String action, String taskId) {
        final downloadService = ref.read(downloadServiceProvider);
        switch (action) {
          case 'pause':
            downloadService.pauseTask(taskId);
            break;
          case 'resume':
            downloadService.resumeTask(taskId);
            break;
          case 'cancel':
            downloadService.cancelTask(taskId);
            break;
          case 'retry':
            downloadService.retryTask(taskId);
            break;
          case 'delete':
            downloadService.deleteDownloaded(taskId);
            break;
        }
        ref.read(downloadVersionProvider.notifier).state++;
      };
    });

// 清空缓存
final clearDownloadCacheProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final downloadService = ref.read(downloadServiceProvider);
    await downloadService.clearCache();
    ref.read(downloadVersionProvider.notifier).state++;
  };
});

/// 下载目录的展示信息：当前生效的目录与平台默认目录。
///
/// 两个都展示出来，是因为设置页要说清「恢复默认」到底会回到哪里——只写
/// 「默认」的话，用户没法判断默认在哪个盘、还剩多少空间。
class DownloadDirectoryInfo {
  const DownloadDirectoryInfo({
    required this.current,
    required this.defaultPath,
    required this.custom,
    this.fallbackReason,
  });

  /// 当前生效的目录（可能就是 [defaultPath]）。
  final String current;

  /// 平台默认目录。
  final String defaultPath;

  /// 用户显式选过的目录；null 表示当前用的是默认目录。
  final String? custom;

  /// 用户选过的目录这次没能启用时的原因。
  ///
  /// 非 null 表示 [custom] 有值但本次运行实际用的是 [defaultPath]——典型
  /// 场景是 iOS / 鸿蒙的授权在重启后没恢复、目录被删了、外接卷没挂上。
  /// 设置页必须把这件事说出来：用户看到自己选的路径还在，实际下载却跑到了
  /// 默认目录，不解释就是「设置不生效」。
  final String? fallbackReason;

  bool get isDefault => custom == null;

  /// 选了自定义目录、但本次运行降级到了默认目录。
  bool get isFallbackActive => custom != null && fallbackReason != null;
}

final downloadDirectoryInfoProvider = FutureProvider<DownloadDirectoryInfo>((
  ref,
) async {
  // 依赖设置值：切换后 invalidate 一次就够，不必轮询服务。
  ref.watch(downloadDirectoryProvider);
  final service = ref.watch(downloadServiceProvider);
  final fallback = await DownloadService.defaultDownloadDirectory();
  return DownloadDirectoryInfo(
    current: service.downloadDirectory ?? fallback.path,
    defaultPath: fallback.path,
    custom: service.customDownloadDirectory,
    fallbackReason: service.customDirectoryFallbackReason,
  );
});

/// 切换下载目录：先让服务校验并生效，再持久化设置、同步本地音乐库。
///
/// 顺序不能反：先写设置的话，用户选了一个写不进去的目录，设置就已经变了，
/// 之后每首歌都会下载失败；而先让服务建目录 + 写探针文件，失败时抛
/// [DownloadDirectoryException]，设置和当前目录都保持原样。
final switchDownloadDirectoryProvider =
    Provider<Future<String> Function(String?)>((ref) {
      return (String? path) async {
        final service = ref.read(downloadServiceProvider);
        final applied = await service.switchDownloadDirectory(path);
        await ref
            .read(downloadDirectoryProvider.notifier)
            .setDirectory(path == null || path.trim().isEmpty ? null : applied);
        ref.invalidate(downloadDirectoryInfoProvider);
        unawaited(_syncLibraryDownloadDirectory(ref, applied));
        return applied;
      };
    });

/// 让本地音乐库跟着换到新目录（它是「自动扫描目录，不可手动移除」的那个）。
///
/// 扫描可能要遍历几千个文件，所以不 await：目录切换本身已经完成，这里失败
/// 只影响「新下载的歌什么时候出现在本地音乐里」，不该让设置页卡住或报错。
Future<void> _syncLibraryDownloadDirectory(Ref ref, String path) async {
  try {
    final library = await ref.read(localMusicLibraryProvider.future);
    await library.setDownloadDirectory(path);
  } catch (error) {
    AppLog.instance.record(
      'download.directory',
      'syncing local library download directory failed: $error',
      level: AppLogLevel.warning,
    );
  }
}
