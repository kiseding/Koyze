// 文件说明：歌词自定义字体的运行时状态。
//
// 三件事绑在一起：设置里选中的字体、磁盘上的副本、注册进引擎的字体族。
// 组件只读 [LyricFontState.family]，不关心前两步。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/state/buildless_notifier.dart';
import '../../../core/storage/storage_service.dart';
import '../domain/lyric_font.dart';

class LyricFontState {
  const LyricFontState({this.font, this.loading = false});

  /// 当前生效的自定义字体；null 表示用主题自带字体。
  final LyricFontFile? font;

  /// 正在安装 / 恢复。UI 用它显示转圈，不参与渲染判断。
  final bool loading;

  bool get isCustom => font != null;

  String? get family => font?.family;

  String? get displayName => font?.displayName;

  LyricFontState copyWith({LyricFontFile? font, bool? loading}) {
    return LyricFontState(
      font: font ?? this.font,
      loading: loading ?? this.loading,
    );
  }
}

final lyricFontProvider = NotifierProvider<LyricFontNotifier, LyricFontState>(
  LyricFontNotifier.new,
);

/// 自定义歌词字体。
///
/// 字体注册只发生在两个时刻：用户刚选完文件，以及应用启动后第一次需要歌词
/// 字体时。后者必须做，否则重启后设置里还写着「XX 字体」，歌词却已经退回
/// 主题字体——`FontLoader` 的注册是进程级的，不会跨启动保留。
class LyricFontNotifier extends BuildlessNotifier<LyricFontState> {
  LyricFontNotifier({StorageLoader? storage})
    : _storage = storage ?? (() => StorageService.instance),
      super(const LyricFontState());

  static const String storageKeyPath = 'lyric_font_path';
  static const String storageKeyName = 'lyric_font_name';
  static const String storageKeyFamily = 'lyric_font_family';

  final StorageLoader _storage;
  bool _restoreStarted = false;

  @override
  LyricFontState build() {
    final initial = super.build();
    _restore();
    return initial;
  }

  Future<void> _restore() async {
    if (_restoreStarted) return;
    _restoreStarted = true;
    try {
      final storage = await _storage();
      final path = storage.getString(storageKeyPath);
      final name = storage.getString(storageKeyName);
      final family = storage.getString(storageKeyFamily);
      if (path == null || name == null || family == null) return;
      publish(const LyricFontState(loading: true));
      final restored = await restoreLyricFont(
        path: path,
        displayName: name,
        family: family,
      );
      if (!mounted) return;
      if (restored == null) {
        AppLog.instance.record(
          'lyric.font',
          'stored font missing or unreadable: $path',
          level: AppLogLevel.warning,
        );
        // 文件没了就清掉记录，别让设置里一直显示一个不存在的字体。
        await _forget();
        publish(const LyricFontState());
        return;
      }
      publish(LyricFontState(font: restored));
      AppLog.instance.record(
        'lyric.font',
        'restored "${restored.displayName}" family=${restored.family}',
      );
    } on Object catch (error, stackTrace) {
      AppLog.instance.record(
        'lyric.font',
        'restore failed: $error',
        level: AppLogLevel.warning,
        stackTrace: stackTrace,
      );
      publish(const LyricFontState());
    }
  }

  /// 安装用户刚选中的字体文件。失败时原样式不变，异常交给调用方提示。
  Future<LyricFontFile> adopt({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final previous = value.font;
    publish(LyricFontState(font: previous, loading: true));
    try {
      final installed = await installLyricFont(
        fileName: fileName,
        bytes: bytes,
      );
      publish(LyricFontState(font: installed));
      final storage = await _storage();
      unawaited(storage.setString(storageKeyPath, installed.path));
      unawaited(storage.setString(storageKeyName, installed.displayName));
      unawaited(storage.setString(storageKeyFamily, installed.family));
      AppLog.instance.record(
        'lyric.font',
        'installed "${installed.displayName}" '
            'bytes=${bytes.length} family=${installed.family}',
      );
      return installed;
    } on Object {
      if (mounted) publish(LyricFontState(font: previous));
      rethrow;
    }
  }

  /// 回到主题自带字体。
  Future<void> clear() async {
    final previous = value.font;
    publish(const LyricFontState());
    await _forget();
    if (previous == null) return;
    try {
      final file = File(previous.path);
      if (await file.exists()) await file.delete();
    } on Object {
      // 删不掉就留着，下次安装会顺手清掉旧文件。
    }
  }

  Future<void> _forget() async {
    try {
      final storage = await _storage();
      await storage.remove(storageKeyPath);
      await storage.remove(storageKeyName);
      await storage.remove(storageKeyFamily);
    } on Object {
      // 清理失败不影响当前会话。
    }
  }
}
