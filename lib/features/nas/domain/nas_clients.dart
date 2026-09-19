import 'package:dio/dio.dart';

import 'audiostation_client.dart';
import 'mediabrowser_client.dart';
import 'nas_client.dart';
import 'nas_kind.dart';
import 'plex_client.dart';

NasClient createNasClient(NasKind kind, {Dio? dio}) {
  switch (kind) {
    case NasKind.emby:
      return EmbyNasClient(dio: dio);
    case NasKind.jellyfin:
      return JellyfinNasClient(dio: dio);
    case NasKind.plex:
      return PlexNasClient(dio: dio);
    case NasKind.audiostation:
      return AudioStationNasClient(dio: dio);
  }
}
