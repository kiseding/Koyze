import '../../subsonic/domain/subsonic_url.dart';
import 'nas_kind.dart';

const nasKindIds = {
  'emby',
  'jellyfin',
  'plex',
  'audiostation',
};

const nasSourceIds = {
  'subsonic',
  ...nasKindIds,
};

const allowedSearchPlatforms = {
  'tx',
  'kw',
  'wy',
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

String nasHostLabel(String url) => subsonicHostLabel(url);

bool isNasMusic(String? source, String? platform) {
  return nasKindIds.contains(source) || nasKindIds.contains(platform);
}

NasKind? nasKindOf(String? source, String? platform) {
  return NasKind.tryParse(source) ?? NasKind.tryParse(platform);
}
