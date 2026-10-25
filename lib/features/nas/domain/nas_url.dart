import '../../subsonic/domain/subsonic_url.dart';
import 'nas_kind.dart';

const nasKindIds = {'emby', 'jellyfin', 'plex', 'audiostation', 'webdav'};

const nasSourceIds = {'subsonic', ...nasKindIds};

const allowedSearchPlatforms = {
  'tx',
  'kw',
  'wy',
  'kg',
  'local',
  'favorites',
  ...nasSourceIds,
};

/// 对外搜索入口只有一条 NAS。旧备份 / 设置里的 emby 等 id 都归一到 `subsonic`。
String canonicalSearchPlatform(String? value) {
  final id = value?.trim() ?? '';
  if (id.isEmpty) return 'tx';
  if (nasSourceIds.contains(id)) return 'subsonic';
  return allowedSearchPlatforms.contains(id) ? id : 'tx';
}

String validateNasServiceUrl(String value) => validateSubsonicServiceUrl(value);

/// Normalizes a WebDAV root path so it can be stored in [NasConfig].
///
/// The value is non-sensitive configuration; credentials never belong here.
/// Empty input means the WebDAV server root.
String normalizeNasRootPath(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return '/';
  if (raw.contains('://')) {
    throw ArgumentError.value(value, 'rootPath', '根目录只需填写路径，例如 /music');
  }
  final stripped = raw.replaceFirst(RegExp(r'^/+'), '');
  if (stripped.isEmpty) return '/';
  return '/${stripped.replaceAll(RegExp(r'/+$'), '')}';
}

String nasHostLabel(String url) => subsonicHostLabel(url);

bool isNasMusic(String? source, String? platform) {
  return nasKindIds.contains(source) || nasKindIds.contains(platform);
}

NasKind? nasKindOf(String? source, String? platform) {
  return NasKind.tryParse(source) ?? NasKind.tryParse(platform);
}
