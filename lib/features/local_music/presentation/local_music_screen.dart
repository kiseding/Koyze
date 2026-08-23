import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:koyze/core/theme/app_colors.dart';
import 'package:koyze/core/widgets/artwork_disk_cache.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/features/local_music/domain/local_music_library.dart';
import 'package:koyze/features/local_music/domain/local_music_scanner.dart';
import 'package:koyze/features/local_music/domain/local_metadata_writer.dart';
import 'package:koyze/features/local_music/domain/local_music_scraper.dart';
import 'package:koyze/features/local_music/domain/android_directory_access.dart';
import 'package:koyze/features/local_music/domain/local_music_debug_log.dart';
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
  bool _tagWriting = false;
  int _scanned = 0;
  int _total = 0;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(localMusicLibraryProvider);
    final dirs = libraryAsync.value?.directories ?? const <String>[];
    final downloadDir = libraryAsync.value?.downloadDirectory;
    final mediaStoreEnabled =
        libraryAsync.value?.androidMediaStoreEnabled ?? false;
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
              onPressed: _scanning || _scraping || _tagWriting
                  ? null
                  : () => _rescan(),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildHeader(context, dirs, downloadDir, mediaStoreEnabled),
            if (_scanning || _scraping || _tagWriting) _buildProgress(context),
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
    bool mediaStoreEnabled,
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
                        mediaStoreEnabled ||
                                directories.isNotEmpty ||
                                downloadDirectory != null
                            ? 'MediaStore 可重扫，已配置 ${directories.length} 个目录'
                            : '添加会打开系统文件夹选择器并授权访问',
                        style: TextStyle(
                          color: AppColors.mutedText(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: _scanning || _scraping || _tagWriting
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
          if (mediaStoreEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Icon(Icons.album_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Android MediaStore · 默认优先扫描',
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
                          if (dir != downloadDirectory)
                            FxIconButton(
                              tooltip: '移除',
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: AppColors.mutedText(context),
                              ),
                              onPressed: _scanning || _scraping || _tagWriting
                                  ? null
                                  : () => _removeDirectory(dir),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (mediaStoreEnabled ||
              directories.isNotEmpty ||
              downloadDirectory != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
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
                      child: Icon(Icons.edit_note_rounded, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '注入tag',
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '将歌名，歌手，专辑，封面等信息写入歌曲文件，需要读写权限',
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: _scanning || _scraping || _tagWriting
                          ? null
                          : () => _writeScrapedTags(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        minimumSize: const Size(0, 40),
                      ),
                      child: const Text('开始'),
                    ),
                  ],
                ),
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
    if (Platform.isAndroid) {
      try {
        LocalMusicDebugLog.info(
          'ui.android_saf_picker.start',
          'source=add_button',
        );
        final path = await AndroidDirectoryAccess.select();
        if (path != null && path.isNotEmpty && mounted) {
          await _scanAndroidSafDirectory(path);
        }
      } catch (error, stackTrace) {
        LocalMusicDebugLog.error(
          'ui.android_saf_picker.error',
          'error=$error',
          stackTrace: stackTrace,
        );
        if (mounted) _showError('选择音乐文件夹失败', error);
      }
      return;
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
    try {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择音乐文件夹');
      if (path == null || !mounted) return;
      await _scan(path);
    } catch (error) {
      if (mounted) _showError('选择文件夹失败', error);
    }
  }

  Future<void> _scanAndroidSafDirectory(String directoryPath) async {
    final library = await ref.read(localMusicLibraryProvider.future);
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scraping = false;
      _scanned = 0;
      _total = 0;
      _status = 'SAF 正在导入音乐文件夹…';
    });
    LocalMusicDebugLog.info(
      'ui.android_saf.start',
      'directory=${LocalMusicDebugLog.quote(directoryPath)}',
    );
    try {
      await library.addAndroidSafDirectory(
        directoryPath,
        onProgress: (scanned, total) {
          if (!mounted) return;
          setState(() {
            _scanned = scanned;
            _total = total;
            _status = 'SAF 正在导入 $_scanned / $_total';
          });
        },
      );
      await _finishAndroidScan(library);
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'ui.android_saf.error',
        'directory=${LocalMusicDebugLog.quote(directoryPath)} error=$error',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _scraping = false;
        });
        _showError('扫描 Android 音乐文件夹失败', error);
      }
    }
  }

  Future<void> _scanAndroidPreferred() async {
    final library = await ref.read(localMusicLibraryProvider.future);
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _scraping = false;
      _scanned = 0;
      _total = 0;
      _status = '正在通过 Android MediaStore 扫描本地音乐…';
    });
    LocalMusicDebugLog.info('ui.android_access.start', 'priority=MediaStore');
    Object? lastError;
    try {
      final audioGranted = await _requestAndroidAudioAccess();
      if (audioGranted) {
        try {
          final before = library.fileCount;
          final scanned = await library.enableAndroidMediaStore(
            onProgress: (scanned, total) {
              if (!mounted) return;
              setState(() {
                _scanned = scanned;
                _total = total;
                _status = 'MediaStore 正在导入 $_scanned / $_total';
              });
            },
          );
          LocalMusicDebugLog.info(
            'ui.android_mediastore.finish',
            'scanned=$scanned before=$before files=${library.fileCount}',
          );
          if (scanned > 0 || library.fileCount > before) {
            await _finishAndroidScan(library);
            return;
          }
          lastError = StateError('MediaStore 未返回音频');
        } catch (error, stackTrace) {
          lastError = error;
          LocalMusicDebugLog.warning(
            'ui.android_mediastore.error',
            'error=$error',
            stackTrace: stackTrace,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _status = 'MediaStore 不可用，正在尝试全部文件访问权限…';
      });
      final allFilesGranted = await _requestAndroidAllFilesAccess();
      if (allFilesGranted) {
        final root = await AndroidDirectoryAccess.externalStorageRoot();
        if (root != null && root.isNotEmpty) {
          LocalMusicDebugLog.info(
            'ui.android_manage_external.start',
            'root=${LocalMusicDebugLog.quote(root)}',
          );
          await library.addDirectory(
            root,
            onProgress: (scanned, total) {
              if (!mounted) return;
              setState(() {
                _scanned = scanned;
                _total = total;
                _status = '全部文件访问正在扫描 $_scanned / $_total';
              });
            },
          );
          await _finishAndroidScan(library);
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        _status = '全部文件访问不可用，正在打开 SAF 目录授权…';
      });
      final path = await AndroidDirectoryAccess.select();
      if (path != null && path.isNotEmpty) {
        await _scanAndroidSafDirectory(path);
        return;
      }
      throw lastError ?? StateError('未获得可用的 Android 本地音乐访问权限');
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'ui.android_access.error',
        'error=$error',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _scanning = false;
          _scraping = false;
        });
        _showError('Android 本地音乐授权失败', error);
      }
    }
  }

  Future<void> _finishAndroidScan(LocalMusicLibrary library) async {
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scraping = true;
      _scanned = 0;
      _status = '正在匹配在线歌曲（刮削）…';
    });
    await _scrapeAndSync(library);
  }

  Future<bool> _requestAndroidAudioAccess() async {
    final audio = await Permission.audio.request();
    if (audio.isGranted || audio.isLimited) {
      LocalMusicDebugLog.info('ui.permission.audio', 'status=$audio');
      return true;
    }
    final storage = await Permission.storage.request();
    final granted = storage.isGranted || storage.isLimited;
    LocalMusicDebugLog.warning(
      'ui.permission.audio_denied',
      'audio=$audio storage=$storage granted=$granted',
    );
    return granted;
  }

  Future<bool> _requestAndroidAllFilesAccess() async {
    if (await AndroidDirectoryAccess.isExternalStorageManager()) {
      LocalMusicDebugLog.info('ui.permission.manage_external', 'already=true');
      return true;
    }
    final status = await Permission.manageExternalStorage.request();
    final nativeGranted =
        await AndroidDirectoryAccess.isExternalStorageManager();
    final granted = status.isGranted || nativeGranted;
    LocalMusicDebugLog.warning(
      'ui.permission.manage_external',
      'status=$status native=$nativeGranted granted=$granted',
    );
    return granted;
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
    LocalMusicDebugLog.info(
      'ui.scan.start',
      'directory=${LocalMusicDebugLog.quote(directoryPath)}',
    );
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
      LocalMusicDebugLog.info(
        'ui.scan.metadata.finish',
        'directory=${LocalMusicDebugLog.quote(directoryPath)} files=${library.fileCount}',
      );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scraping = true;
        _scanned = 0;
        _status = '正在匹配在线歌曲（刮削）…';
      });
      await _scrapeAndSync(library);
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'ui.scan.error',
        'directory=${LocalMusicDebugLog.quote(directoryPath)} error=$error',
        stackTrace: stackTrace,
      );
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
    if (!library.hasConfiguredSources) {
      if (Platform.isAndroid) {
        await _scanAndroidPreferred();
        return;
      }
      if (mounted) _showError('还没有配置本地音乐来源', StateError('empty'));
      return;
    }
    setState(() {
      _scanning = true;
      _status = '正在重新扫描本地音乐来源…';
    });
    LocalMusicDebugLog.info(
      'ui.rescan.start',
      'directories=${library.directories.length} mediaStore=${library.androidMediaStoreEnabled} files=${library.fileCount}',
    );
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
      LocalMusicDebugLog.info(
        'ui.rescan.metadata.finish',
        'files=${library.fileCount}',
      );
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scraping = true;
        _scanned = 0;
        _status = '正在匹配在线歌曲（刮削）…';
      });
      await _scrapeAndSync(library);
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'ui.rescan.error',
        'error=$error',
        stackTrace: stackTrace,
      );
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
    LocalMusicDebugLog.info(
      'ui.scrape_sync.start',
      'songs=${songs.length} files=${library.fileCount}',
    );
    var matched = 0;
    var unmatched = 0;
    var artworkEmbedded = 0;
    var artworkCached = 0;
    var artworkMissing = 0;
    for (var index = 0; index < songs.length; index++) {
      final song = songs[index];
      final path = song.meta?['filePath']?.toString();
      if (path == null) {
        LocalMusicDebugLog.warning(
          'ui.scrape.skip_missing_path',
          'index=${index + 1}/${songs.length} name=${LocalMusicDebugLog.quote(song.name)} singer=${LocalMusicDebugLog.quote(song.singer)}',
        );
        continue;
      }
      final entry = library.files[path];
      if (entry == null) {
        LocalMusicDebugLog.warning(
          'ui.scrape.index_entry_missing',
          'path=${LocalMusicDebugLog.quote(path)} song=${LocalMusicDebugLog.quote(song.name)}',
        );
      }
      final bitrate = entry?['bitrate'];
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
        bitrate: bitrate is int ? bitrate : null,
        hasEmbeddedTags: entry?['hasEmbeddedTags'] == true,
        hasEmbeddedArtwork: entry?['hasEmbeddedArtwork'] == true,
        contentUri: entry?['contentUri']?.toString(),
        androidSource: entry?['androidSource']?.toString(),
        safRoot: entry?['safRoot']?.toString(),
        mimeType: entry?['mimeType']?.toString(),
      );
      LocalMusicDebugLog.info(
        'ui.scrape.track',
        'index=${index + 1}/${songs.length} ${LocalMusicDebugLog.track(track)}',
      );
      final identity = await scraper.scrapeTrack(track);
      if (identity != null) {
        matched++;
        final identityJson = identity.toJson();
        LocalMusicDebugLog.info(
          'ui.scrape.identity.raw',
          'path=${LocalMusicDebugLog.quote(path)} ${LocalMusicDebugLog.identity(identityJson)}',
        );
        // Never persist an unverified remote artwork URL for local music.
        identityJson.remove('artwork');
        LocalMusicDebugLog.info(
          'ui.scrape.artwork.remote_removed',
          'path=${LocalMusicDebugLog.quote(path)} remoteArtwork=${LocalMusicDebugLog.present(identity.artwork)}',
        );
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
          artworkEmbedded++;
          identityJson['artwork'] = embeddedArtworkPath;
          LocalMusicDebugLog.info(
            'ui.scrape.artwork.embedded_keep',
            'path=${LocalMusicDebugLog.quote(path)} artwork=${LocalMusicDebugLog.quote(embeddedArtworkPath)}',
          );
        } else if (artwork != null && artwork.isNotEmpty) {
          // Remote artwork must be downloaded successfully before it enters
          // the local identity; a failed CDN request must not leave a broken
          // HTTP URL that the local list cannot render.
          final candidates = LocalMusicScraper.artworkCandidates(
            identity.platform,
            artwork,
          );
          LocalMusicDebugLog.info(
            'ui.scrape.artwork.candidates',
            'path=${LocalMusicDebugLog.quote(path)} count=${candidates.length}',
          );
          for (final candidate in candidates) {
            try {
              LocalMusicDebugLog.info(
                'ui.scrape.artwork.cache_try',
                'path=${LocalMusicDebugLog.quote(path)} url=${LocalMusicDebugLog.quote(candidate)}',
              );
              final localFile = await ArtworkDiskCache.instance.ensureLocalFile(
                candidate,
              );
              if (localFile != null && await localFile.exists()) {
                artworkCached++;
                identityJson['artwork'] = localFile.path;
                LocalMusicDebugLog.info(
                  'ui.scrape.artwork.cache_hit',
                  'path=${LocalMusicDebugLog.quote(path)} local=${LocalMusicDebugLog.quote(localFile.path)}',
                );
                break;
              }
              LocalMusicDebugLog.warning(
                'ui.scrape.artwork.cache_empty',
                'path=${LocalMusicDebugLog.quote(path)} url=${LocalMusicDebugLog.quote(candidate)}',
              );
            } catch (error, stackTrace) {
              LocalMusicDebugLog.warning(
                'ui.scrape.artwork.cache_error',
                'path=${LocalMusicDebugLog.quote(path)} url=${LocalMusicDebugLog.quote(candidate)} error=$error',
                stackTrace: stackTrace,
              );
              // Try the next CDN rendition.
            }
          }
        } else {
          LocalMusicDebugLog.info(
            'ui.scrape.artwork.none',
            'path=${LocalMusicDebugLog.quote(path)} reason=noRemoteArtworkAndNoEmbeddedArtwork',
          );
        }
        if (identityJson['artwork'] == null ||
            identityJson['artwork']?.toString().isEmpty == true) {
          artworkMissing++;
          LocalMusicDebugLog.warning(
            'ui.scrape.artwork.unresolved',
            'path=${LocalMusicDebugLog.quote(path)}',
          );
        }
        LocalMusicDebugLog.info(
          'ui.scrape.identity.persist',
          'path=${LocalMusicDebugLog.quote(path)} ${LocalMusicDebugLog.identity(identityJson)}',
        );
        await library.applyScrapedIdentity(path, identityJson);
      } else {
        unmatched++;
        LocalMusicDebugLog.warning(
          'ui.scrape.identity.none',
          'path=${LocalMusicDebugLog.quote(path)} ${LocalMusicDebugLog.track(track)}',
        );
      }
      if (!mounted) return;
      setState(() {
        _scanned = index + 1;
        _total = songs.length;
        _status = '正在刮削 $_scanned / $_total';
      });
    }

    final playlistService = ref.read(playlistServiceProvider);
    final syncedSongs = library.songs;
    LocalMusicDebugLog.info(
      'ui.playlist_sync.start',
      'songs=${syncedSongs.length} matched=$matched unmatched=$unmatched artworkEmbedded=$artworkEmbedded artworkCached=$artworkCached artworkMissing=$artworkMissing',
    );
    await playlistService.replaceLocalSongs(syncedSongs);
    LocalMusicDebugLog.info(
      'ui.playlist_sync.finish',
      'songs=${syncedSongs.length}',
    );
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

  Future<void> _writeScrapedTags() async {
    final library = await ref.read(localMusicLibraryProvider.future);
    await _requestTagWritePermissions();
    final songs = library.songs;
    if (songs.isEmpty) {
      if (mounted) _showError('没有可写入的本地歌曲', StateError('empty'));
      return;
    }
    if (!mounted) return;
    setState(() {
      _tagWriting = true;
      _scanned = 0;
      _total = songs.length;
      _status = '正在尝试写回原文件标签…';
    });
    var attempted = 0;
    var written = 0;
    LocalMusicDebugLog.info('ui.tag_write.start', 'songs=${songs.length}');
    try {
      for (var index = 0; index < songs.length; index++) {
        final song = songs[index];
        final path = song.meta?['filePath']?.toString();
        if (path == null || path.isEmpty) {
          LocalMusicDebugLog.warning(
            'ui.tag_write.skip_missing_path',
            'index=${index + 1}/${songs.length} name=${LocalMusicDebugLog.quote(song.name)}',
          );
          continue;
        }
        final identity = library.scrapedIdentity(path);
        if (identity == null) {
          LocalMusicDebugLog.info(
            'ui.tag_write.skip_no_identity',
            'path=${LocalMusicDebugLog.quote(path)}',
          );
          continue;
        }
        final title = identity['name']?.toString();
        final artist = identity['singer']?.toString();
        if (title == null ||
            title.isEmpty ||
            artist == null ||
            artist.isEmpty) {
          LocalMusicDebugLog.warning(
            'ui.tag_write.skip_incomplete_identity',
            'path=${LocalMusicDebugLog.quote(path)} ${LocalMusicDebugLog.identity(identity)}',
          );
          continue;
        }
        attempted++;
        final artworkBytes = await _localArtworkBytes(
          identity['artwork']?.toString() ?? song.artwork,
        );
        LocalMusicDebugLog.info(
          'ui.tag_write.attempt',
          'path=${LocalMusicDebugLog.quote(path)} title=${LocalMusicDebugLog.quote(title)} artist=${LocalMusicDebugLog.quote(artist)} album=${LocalMusicDebugLog.quote(identity['album']?.toString() ?? song.album)} artworkBytes=${artworkBytes?.length ?? 0}',
        );
        final success = await writeScrapedMetadata(
          path,
          title: title,
          artist: artist,
          album: identity['album']?.toString() ?? song.album,
          artwork: artworkBytes,
        );
        LocalMusicDebugLog.info(
          success ? 'ui.tag_write.success' : 'ui.tag_write.failed',
          'path=${LocalMusicDebugLog.quote(path)}',
        );
        if (success) {
          written++;
        }
        if (!mounted) return;
        setState(() {
          _scanned = index + 1;
          _status = '正在写回原文件标签 $_scanned / $_total';
        });
      }
      if (!mounted) return;
      setState(() {
        _tagWriting = false;
      });
      LocalMusicDebugLog.info(
        'ui.tag_write.finish',
        'attempted=$attempted written=$written',
      );
      showAppNotification(
        attempted == 0 ? '没有可写回的刮削标签' : '标签写回完成：成功 $written / $attempted',
        type: written == attempted && attempted > 0
            ? AppNotificationType.success
            : AppNotificationType.info,
      );
    } catch (error, stackTrace) {
      LocalMusicDebugLog.error(
        'ui.tag_write.error',
        'attempted=$attempted written=$written error=$error',
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _tagWriting = false;
        });
        _showError('写回标签失败', error);
      }
    }
  }

  Future<void> _requestTagWritePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      await Permission.audio.request();
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
    } catch (_) {
      // SAF tree grants may still allow writing even when broad storage
      // permissions are unavailable on newer Android versions.
    }
  }

  Future<Uint8List?> _localArtworkBytes(String? artwork) async {
    if (artwork == null || artwork.isEmpty) {
      LocalMusicDebugLog.info(
        'ui.tag_write.artwork_bytes.skip',
        'artwork=empty',
      );
      return null;
    }
    try {
      final uri = Uri.tryParse(artwork);
      final file = uri?.scheme == 'file'
          ? File(uri!.toFilePath())
          : (uri?.scheme.isNotEmpty == true ? null : File(artwork));
      if (file == null) {
        LocalMusicDebugLog.warning(
          'ui.tag_write.artwork_bytes.skip',
          'unsupportedUri=${LocalMusicDebugLog.quote(artwork)}',
        );
        return null;
      }
      if (!await file.exists()) {
        LocalMusicDebugLog.warning(
          'ui.tag_write.artwork_bytes.missing',
          'path=${LocalMusicDebugLog.quote(file.path)}',
        );
        return null;
      }
      final bytes = await file.readAsBytes();
      LocalMusicDebugLog.info(
        'ui.tag_write.artwork_bytes.read',
        'path=${LocalMusicDebugLog.quote(file.path)} bytes=${bytes.length}',
      );
      return bytes.isEmpty ? null : bytes;
    } catch (error, stackTrace) {
      LocalMusicDebugLog.warning(
        'ui.tag_write.artwork_bytes.error',
        'artwork=${LocalMusicDebugLog.quote(artwork)} error=$error',
        stackTrace: stackTrace,
      );
      return null;
    }
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
