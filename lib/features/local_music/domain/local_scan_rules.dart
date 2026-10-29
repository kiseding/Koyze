import 'local_music_scanner.dart';

/// 本地扫描的过滤规则。
///
/// 默认值刻意是「什么都收」：老用户升级后不应该发现自己的库少了一半。
/// 这些规则只影响之后的扫描，不会删除已入库的记录——删记录是不可逆的，
/// 而用户调阈值往往只是想试试。
class LocalScanRules {
  const LocalScanRules({
    this.minDuration = Duration.zero,
    this.minSizeBytes = 0,
    this.skipDuplicates = false,
    this.excludedFolders = const <String>[],
  });

  /// 短于这个时长的文件不入库（提示音、片头、损坏的残片）。
  final Duration minDuration;

  /// 小于这个体积的文件不入库。
  final int minSizeBytes;

  /// 跳过重复曲目：同「标题 + 歌手 + 时长」只保留体积最大的那份
  /// （通常是码率更高的版本）。
  final bool skipDuplicates;

  /// 不参与扫描的目录（绝对路径前缀）。
  final List<String> excludedFolders;

  bool get isDefault =>
      minDuration == Duration.zero &&
      minSizeBytes == 0 &&
      !skipDuplicates &&
      excludedFolders.isEmpty;

  /// 目录是否被排除：按前缀比较，命中则整枝跳过。
  bool excludes(String directoryPath) {
    if (excludedFolders.isEmpty) return false;
    final normalized = _normalize(directoryPath);
    for (final excluded in excludedFolders) {
      final prefix = _normalize(excluded);
      if (prefix.isEmpty) continue;
      if (normalized == prefix || normalized.startsWith('$prefix/')) {
        return true;
      }
    }
    return false;
  }

  /// 单文件是否满足入库条件（体积 / 时长）。
  bool allows({required int sizeBytes, required Duration duration}) {
    if (minSizeBytes > 0 && sizeBytes < minSizeBytes) return false;
    if (minDuration > Duration.zero &&
        duration > Duration.zero &&
        duration < minDuration) {
      return false;
    }
    return true;
  }

  LocalScanRules copyWith({
    Duration? minDuration,
    int? minSizeBytes,
    bool? skipDuplicates,
    List<String>? excludedFolders,
  }) => LocalScanRules(
    minDuration: minDuration ?? this.minDuration,
    minSizeBytes: minSizeBytes ?? this.minSizeBytes,
    skipDuplicates: skipDuplicates ?? this.skipDuplicates,
    excludedFolders: excludedFolders ?? this.excludedFolders,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'minDurationSeconds': minDuration.inSeconds,
    'minSizeBytes': minSizeBytes,
    'skipDuplicates': skipDuplicates,
    'excludedFolders': excludedFolders,
  };

  static LocalScanRules fromJson(Map<String, dynamic> json) {
    final seconds = (json['minDurationSeconds'] as num?)?.toInt() ?? 0;
    final size = (json['minSizeBytes'] as num?)?.toInt() ?? 0;
    final folders = <String>[];
    final rawFolders = json['excludedFolders'];
    if (rawFolders is List) {
      for (final item in rawFolders) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) folders.add(text);
      }
    }
    return LocalScanRules(
      minDuration: Duration(seconds: seconds < 0 ? 0 : seconds),
      minSizeBytes: size < 0 ? 0 : size,
      skipDuplicates: json['skipDuplicates'] == true,
      excludedFolders: List<String>.unmodifiable(folders),
    );
  }

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();
}

/// 重复曲目的分组键：标题 + 歌手 + 时长。时长未知（0）时不参与去重，
/// 否则「文件名当标题」的那批会互相误杀。
String? duplicateKeyOf(LocalTrack track) {
  if (track.duration <= Duration.zero) return null;
  final title = track.title.trim().toLowerCase();
  final artist = track.artist.trim().toLowerCase();
  if (title.isEmpty) return null;
  return '$title|$artist|${track.duration.inSeconds}';
}
