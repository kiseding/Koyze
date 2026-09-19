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

String validateNasServiceUrl(String value) => validateSubsonicServiceUrl(value);

String nasHostLabel(String url) => subsonicHostLabel(url);

bool isNasMusic(String? source, String? platform) {
  return nasKindIds.contains(source) || nasKindIds.contains(platform);
}

NasKind? nasKindOf(String? source, String? platform) {
  return NasKind.tryParse(source) ?? NasKind.tryParse(platform);
}
