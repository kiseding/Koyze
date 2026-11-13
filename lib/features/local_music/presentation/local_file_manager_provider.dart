import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koyze/features/local_music/domain/local_file_manager.dart';
import 'package:koyze/features/local_music/domain/local_file_system.dart';

/// 文件系统实现。测试里覆盖这个 provider 换成替身。
final localFileSystemProvider = Provider<LocalFileSystem>((ref) {
  return LocalFileSystem.forPlatform();
});

/// 本地文件搬运服务。
final localFileManagerProvider = Provider<LocalFileManager>((ref) {
  return LocalFileManager(fileSystem: ref.watch(localFileSystemProvider));
});
