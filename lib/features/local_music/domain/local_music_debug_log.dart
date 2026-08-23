import 'package:koyze/core/logging/app_log.dart';

/// Debug hooks for the full local-music scrape pipeline.
///
/// The hooks are intentionally no-ops unless the real-time diagnostic overlay
/// has started [AppLog]. This keeps normal app usage quiet while making the
/// complete scan → search → match → artwork → persist → playlist path visible
/// when a user opens Settings → diagnostic logs.
final class LocalMusicDebugLog {
  const LocalMusicDebugLog._();

  static const _category = 'local.scrape';

  static bool get enabled => AppLog.instance.isActive;

  static void info(String step, Object? message) {
    _record(step, message);
  }

  static void warning(String step, Object? message, {StackTrace? stackTrace}) {
    _record(step, message, level: AppLogLevel.warning, stackTrace: stackTrace);
  }

  static void error(String step, Object? message, {StackTrace? stackTrace}) {
    _record(step, message, level: AppLogLevel.error, stackTrace: stackTrace);
  }

  static void _record(
    String step,
    Object? message, {
    AppLogLevel level = AppLogLevel.info,
    StackTrace? stackTrace,
  }) {
    if (!enabled) return;
    AppLog.instance.record(
      _category,
      '$step | ${message ?? ''}',
      level: level,
      stackTrace: stackTrace,
    );
  }

  static String track(dynamic track) {
    return 'file=${quote(track.fileName)} '
        'title=${quote(track.title)} '
        'artist=${quote(track.artist)} '
        'album=${quote(track.album)} '
        'duration=${track.duration.inSeconds}s '
        'bitrate=${track.bitrate ?? '-'} '
        'embeddedTags=${track.hasEmbeddedTags} '
        'embeddedArtwork=${track.hasEmbeddedArtwork} '
        'path=${quote(track.path)}';
  }

  static String indexedFile(Map<String, dynamic> entry) {
    return 'file=${quote(entry['fileName'])} '
        'title=${quote(entry['title'])} '
        'artist=${quote(entry['artist'])} '
        'album=${quote(entry['album'])} '
        'duration=${entry['duration'] ?? 0}s '
        'embeddedTags=${entry['hasEmbeddedTags'] == true} '
        'embeddedArtwork=${entry['hasEmbeddedArtwork'] == true} '
        'path=${quote(entry['path'])}';
  }

  static String identity(Map<String, dynamic> identity) {
    return 'platform=${quote(identity['platform'])} '
        'songmid=${quote(identity['songmid'])} '
        'hash=${quote(identity['hash'])} '
        'name=${quote(identity['name'])} '
        'singer=${quote(identity['singer'])} '
        'album=${quote(identity['album'])} '
        'artwork=${present(identity['artwork'])} '
        'lyrics=${present(identity['lyrics'])}';
  }

  static String quote(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '\\"')}"';
  }

  static String present(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return 'empty';
    return 'yes(${text.length})';
  }
}
