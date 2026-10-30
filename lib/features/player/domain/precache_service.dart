import 'package:connectivity_plus/connectivity_plus.dart';

import 'music_item.dart';

/// 把一首歌解析成可播地址的钩子；成功返回地址，失败返回 null。
typedef PrecacheResolver =
    Future<String?> Function(MusicItem song, {required String quality});

typedef WifiProbe = Future<bool> Function();

/// 播放地址预取的接入点。
///
/// `PlaybackUrlResolver` 依赖音源服务与播放缓存，两者都在 `main()` 里装配，
/// 不是 provider 图的一部分。这里留一个可写钩子，由启动流程在装配完成后
/// 接进来——和 `LxAudioHandler.urlResolver` 是同一套做法。
class PlaybackPrewarm {
  PrecacheResolver? _resolver;

  bool get isWired => _resolver != null;

  void wire(PrecacheResolver resolver) => _resolver = resolver;

  /// 预取一首歌。解析成功会顺带把音频写进播放缓存（解析器本身的副作用），
  /// 之后真正播放时命中缓存，起播不需要再等网络。
  Future<bool> prewarm(MusicItem song, {required String quality}) async {
    final resolver = _resolver;
    if (resolver == null) return false;
    try {
      final url = await resolver(song, quality: quality);
      return url != null && url.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// 常听预缓存：把最近常听的若干首歌提前解析 + 落到播放缓存里。
///
/// 只做「一次性、串行、可随时放弃」的批量预取：
/// - 串行是为了不给正常播放抢带宽；
/// - 每首独立 try/catch，一首失败不影响后面的；
/// - 同一进程内同一首歌只预取一次（`_done`），避免反复下载。
class PrecacheService {
  PrecacheService({PlaybackPrewarm? prewarm, WifiProbe? onWifi})
    : _prewarm = prewarm ?? PlaybackPrewarm(),
      _onWifi = onWifi ?? _deviceOnWifi;

  final PlaybackPrewarm _prewarm;
  final WifiProbe _onWifi;
  final Set<String> _done = <String>{};
  bool _running = false;

  /// 已经预取过的曲目数（本次进程内）。
  int get warmCount => _done.length;

  bool get isRunning => _running;

  /// 返回本次真正预取成功的数量。
  Future<int> run({
    required List<MusicItem> candidates,
    required String quality,
    required int limit,
    bool requireWifi = true,
  }) async {
    if (_running || limit <= 0 || !_prewarm.isWired) return 0;
    final targets = <MusicItem>[];
    for (final song in candidates) {
      if (targets.length >= limit) break;
      if (!_isPrecachable(song)) continue;
      if (_done.contains(song.identityKey)) continue;
      targets.add(song);
    }
    if (targets.isEmpty) return 0;
    if (requireWifi && !await _onWifi()) return 0;

    _running = true;
    var warmed = 0;
    try {
      for (final song in targets) {
        if (await _prewarm.prewarm(song, quality: quality)) {
          _done.add(song.identityKey);
          warmed++;
        }
      }
    } finally {
      _running = false;
    }
    return warmed;
  }

  /// 本地文件不需要解析，预缓存没有意义。
  bool _isPrecachable(MusicItem song) {
    if (song.id.trim().isEmpty) return false;
    final source = song.source.trim().toLowerCase();
    if (source == 'local') return false;
    final meta = song.meta;
    if (meta != null && meta['local'] == true) {
      return false;
    }
    return true;
  }

  /// 只在 Wi-Fi / 有线 / 未知网络下预取；明确走蜂窝网络时放弃。
  static Future<bool> _deviceOnWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return false;
      if (results.contains(ConnectivityResult.none)) return false;
      return !results.contains(ConnectivityResult.mobile);
    } catch (_) {
      return false;
    }
  }
}
