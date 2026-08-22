import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/widgets/artwork_disk_cache.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';
import 'package:koyze/features/local_music/domain/local_music_scraper.dart';
import 'package:koyze/features/local_music/domain/android_directory_access.dart';
import 'package:koyze/features/local_music/domain/security_scoped_directory.dart';
import 'package:koyze/features/local_music/presentation/local_music_provider.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import '../../../core/widgets/fx_icon_button.dart';

/// 本地音乐管理页：选择文件夹 → 扫描 → 刮削 → 写入「本地音乐」歌单。
class LocalMusicScreen extends ConsumerStatefulWidget {
  const LocalMusicScreen({super.key});

  @override
  ConsumerState<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends ConsumerState<LocalMusicScreen> {
  bool _scanning = false;
  bool _scraping = false;
  int _scanned = 0;
  int _total = 0;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(localMusicLibraryProvider);
    final dirs = libraryAsync.value?.directories ?? const <String>[];
    final downloadDir = libraryAsync.value?.downloadDirectory;
    final songCount = libraryAsync.value?.fileCount ?? 0;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          leading: FxIconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.onScaffold(context)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            '本地音乐设置',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.onScaffold(context),
            ),
          ),
          actions: [
            FxIconButton(
              tooltip: '重新扫描',
              icon: Icon(
                Icons.refresh,
                color: AppColors.onScaffold(context),
                size: 22,
              ),
              onPressed: _scanning || _scraping ? null : () => _rescan(),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildHeader(context, dirs, downloadDir),
            if (_scanning || _scraping) _buildProgress(context),
            Expanded(
              child: Center(
                child: Text(
                  songCount == 0
                      ? '还没有本地歌曲\n添加文件夹或等待下载完成后自动扫描'
                      : '已收录 $songCount 首本地歌曲\n前往「我的歌单 > 本地音乐」播放',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.mutedText(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<String> directories,
    String? downloadDirectory,
  ) {
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.library_music_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本地音乐库',
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        directories.isEmpty && downloadDirectory == null
                            ? '添加文件夹后自动扫描和匹配'
                            : '已配置 ${directories.length} 个扫描位置',
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _scanning || _scraping
                      ? null
                      : () => _pickDirectory(),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 40),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加'),
                ),
              ],
            ),
          ),
          if (downloadDirectory != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.download_done, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '下载目录 · 自动收录\n$downloadDirectory',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.mutedText(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (directories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  for (final dir in directories)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.miniBar(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.folder_rounded, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dir,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.mutedText(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          FxIconButton(
                            tooltip: '移除',
                            icon: Icon(
                              Icons.close,
                              size: 16,
                              color: AppColors.mutedText(context),
                            ),
                            onPressed: _scanning || _scraping
                                ? null
                                : () => _removeDirectory(dir),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: _total > 0 ? _scanned / _total : null,
            backgroundColor: AppColors.miniBar(context),
          ),
          const SizedBox(height: 6),
          Text(
            _status,
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _pickDirectory() async {
    // Android 13+ 读外部音频需 READ_MEDIA_AUDIO；≤12 为 READ_EXTERNAL_STORAGE。
    // 权限被拒时仍允许尝试（SAF 目录选择可能已授权），但提示可能扫描不到。
    if (Platform.isAndroid) {
      final status = await Permission.audio.request();
      if (status == PermissionStatus.permanentlyDenied) {
        if (mounted) {
          _showError('存储权限被永久拒绝', StateError('请在系统设置中允许'));
        }
        return;
      }
    }
    if (Platform.isIOS) {
      try {
        final path = await SecurityScopedDirectory.select();
        if (path != null && mounted) await _scan(path);
      } catch (error) {
        if (mounted) _showError('选择音乐文件夹失败', error);
      }
      return;
    }
    if (Platform.isAndroid) {
      try {
        final path = await AndroidDirectoryAccess.select();
        if (path != null && mounted) await _scan(path);
      } catch (error) {
        if (mounted) _showError('选择音乐文件夹失败', error);
      }
      return;
    }
    try {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择音乐文件夹');
      if (path == null || !mounted) return;
      await _scan(path);
    } catch (error) {
      if (mounted) _showError('选择文件夹失败', error);
    }
  }

  Future<void> _scan(String directoryPath) async {
    final library = await ref.read(localMusicLibraryProvider.future);
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scanned = 0;
      _total = 0;
      _status = '正在扫描 $directoryPath …';
    });
    try {
      await library.addDirectory(
        directoryPath,
        onProgress: (scanned, total) {
          if (!mounted) return;
          setState(() {
            _scanned = scanned;
            _total = total;
            _status = '正在解析元数据 $_scanned / $_total';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scraping = true;
        _scanned = 0;
        _status = '正在匹配在线歌曲（刮削）…';
      });
      await _scrapeAndSync(library);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scraping = false;
        });
        _showError('扫描失败', error);
      }
    }
  }

  Future<void> _rescan() async {
    final library = await ref.read(localMusicLibraryProvider.future);
    if (!mounted) return;
    if (library.directories.isEmpty) {
      if (mounted) _showError('还没有扫描文件夹', StateError('empty'));
      return;
    }
    setState(() {
      _scanning = true;
      _status = '正在重新扫描全部文件夹…';
    });
    try {
      await library.rescanAll(
        onProgress: (scanned, total) {
          if (!mounted) return;
          setState(() {
            _scanned = scanned;
            _total = total;
            _status = '正在解析元数据 $_scanned / $_total';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scraping = true;
        _scanned = 0;
        _status = '正在匹配在线歌曲（刮削）…';
      });
      await _scrapeAndSync(library);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _scraping = false;
        });
        _showError('重新扫描失败', error);
      }
    }
  }

  Future<void> _scrapeAndSync(LocalMusicLibrary library) async {
    final scraper = ref.read(localMusicScraperProvider);
    final songs = library.songs;
    for (var index = 0; index < songs.length; index++) {
      final song = songs[index];
      final path = song.meta?['filePath']?.toString();
      if (path == null) continue;
      final entry = library.files[path];
      final track = LocalTrack(
        path: path,
        fileName: entry?['fileName']?.toString() ?? path,
        extension: entry?['extension']?.toString() ?? '',
        size: entry?['size'] ?? 0,
        modifiedAt: DateTime.now(),
        title: entry?['title']?.toString() ?? song.name,
        artist: entry?['artist']?.toString() ?? song.singer,
        album: entry?['album']?.toString() ?? '',
        duration: Duration(seconds: entry?['duration'] ?? 0),
        hasEmbeddedTags: entry?['hasEmbeddedTags'] == true,
        hasEmbeddedArtwork: entry?['hasEmbeddedArtwork'] == true,
      );
      final identity = await scraper.scrapeTrack(track);
      if (identity != null) {
        final identityJson = identity.toJson();
        // Never persist an unverified remote artwork URL for local music.
        identityJson.remove('artwork');
        // Embedded artwork is authoritative. Keep the local file and never
        // replace it with a remote thumbnail from the scraper.
        final existingArtwork = song.artwork;
        final existingArtworkUri = existingArtwork == null
            ? null
            : Uri.tryParse(existingArtwork);
        final embeddedArtworkPath = existingArtworkUri?.scheme == 'file'
            ? existingArtworkUri!.toFilePath()
            : null;
        final hasEmbeddedArtwork =
            embeddedArtworkPath != null &&
            await File(embeddedArtworkPath).exists();
        final artwork = identity.artwork;
        if (hasEmbeddedArtwork) {
          identityJson['artwork'] = embeddedArtworkPath;
        } else if (artwork != null && artwork.isNotEmpty) {
          // Remote artwork must be downloaded successfully before it enters
          // the local identity; a failed CDN request must not leave a broken
          // HTTP URL that the local list cannot render.
          for (final candidate in LocalMusicScraper.artworkCandidates(
            identity.platform,
            artwork,
          )) {
            try {
              final localFile = await ArtworkDiskCache.instance.ensureLocalFile(
                candidate,
              );
              if (localFile != null && await localFile.exists()) {
                identityJson['artwork'] = localFile.path;
                break;
              }
            } catch (_) {
              // Try the next CDN rendition.
            }
          }
        }
        await library.applyScrapedIdentity(path, identityJson);
      }
      if (!mounted) return;
      setState(() {
        _scanned = index + 1;
        _total = songs.length;
        _status = '正在刮削 $_scanned / $_total';
      });
    }

    final playlistService = ref.read(playlistServiceProvider);
    await playlistService.replaceLocalSongs(library.songs);
    if (!mounted) return;
    setState(() {
      _scraping = false;
    });
    ref.read(localMusicRevisionProvider.notifier).state++;
    showAppNotification(
      '本地音乐已更新（${songs.length} 首）',
      type: AppNotificationType.info,
    );
  }

  Future<void> _removeDirectory(String directoryPath) async {
    final library = await ref.read(localMusicLibraryProvider.future);
    try {
      await library.removeDirectory(directoryPath);
      final playlistService = ref.read(playlistServiceProvider);
      await playlistService.replaceLocalSongs(library.songs);
      ref.read(localMusicRevisionProvider.notifier).state++;
      if (mounted) {
        showAppNotification('已移除文件夹', type: AppNotificationType.info);
      }
    } catch (error) {
      if (mounted) _showError('移除失败', error);
    }
  }

  void _showError(String action, Object error) {
    showAppNotification('$action: $error', type: AppNotificationType.error);
  }
}
