import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/network/app_http_client.dart';
import '../../../core/music_source/platform/source_utils.dart';
import '../../player/domain/music_item.dart';

class ImportedPlaylist {
  final String name;
  final String source;
  final String sourceId;
  final List<MusicItem> songs;

  const ImportedPlaylist({
    required this.name,
    required this.source,
    required this.sourceId,
    required this.songs,
  });
}

/// 本地解析 QQ / 酷我 / 网易歌单（无需登录）
class PlaylistImportService {
  final Dio _dio = AppHttpClient.create(
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  static String kwArtwork(Map<String, dynamic> song) {
    return normalizeKuwoArtwork(song);
  }

  Future<ImportedPlaylist> import({
    required String input,
    String platformHint = 'tx',
    void Function(int loaded, int total)? onProgress,
  }) async {
    final trimmed = input.trim();
    final isRawId = _digitsOnly.hasMatch(trimmed);
    var source = '';
    var listId = '';

    if (trimmed.contains('y.qq.com') || trimmed.contains('i.y.qq.com')) {
      source = 'tx';
      listId = _matchId(trimmed, [
        r'[?&]id=(\d+)',
        r'playlist/(\d+)',
        r'songList/(\d+)',
        r'taoge/(\d+)',
        r'/(\d{5,})',
      ]);
    } else if (trimmed.contains('kuwo.cn')) {
      source = 'kw';
      listId = _matchId(trimmed, [
        r'[?&]id=(\d+)',
        r'playlist/(\d+)',
        r'pid=(\d+)',
        r'detail/(\d+)',
      ]);
    } else if (trimmed.contains('music.163.com') ||
        trimmed.contains('163.com') ||
        trimmed.contains('163cn.tv')) {
      source = 'wy';
      // 网易云分享出来的多是 163cn.tv 短链，本地取不到 ID，需要跟随跳转解析。
      listId = isRawId ? trimmed : await _resolveWyId(trimmed);
    }

    if (source.isEmpty && isRawId) {
      source = platformHint;
      listId = trimmed;
    }

    if (source.isEmpty || listId.isEmpty) {
      if (source == 'wy') {
        throw Exception('无法识别网易云歌单链接，请粘贴完整分享链接或数字 ID');
      }
      throw Exception('无法识别，请选择平台后输入歌单链接或 ID');
    }

    switch (source) {
      case 'tx':
        return _importTx(listId);
      case 'kw':
        return _importKw(listId);
      case 'wy':
        return _importWy(listId, onProgress: onProgress);
      default:
        throw Exception('不支持的平台');
    }
  }

  /// 解析网易云歌单 ID：支持 163cn.tv 短链、music.163.com 链接与裸数字 ID。
  Future<String> _resolveWyId(String input) async {
    var text = input.trim();

    // 163cn.tv 短链：不跟随跳转，直接读 Location，避免整链路重定向开销。
    if (text.contains('163cn.tv')) {
      try {
        final resp = await _dio.get(
          text,
          options: Options(
            followRedirects: false,
            validateStatus: (s) => s != null && s < 400,
          ),
        );
        final location = resp.headers.value('location');
        if (location != null && location.trim().isNotEmpty) {
          text = location.trim();
        }
      } catch (_) {
        // 取不到 Location 时退回按原文匹配。
      }
    }

    final id = _matchId(text, [
      r'[?&]id=(\d+)',
      r'playlist/(\d+)',
      r'[?&]list=(\d+)',
    ]);
    if (id.isNotEmpty) return id;

    return RegExp(r'^\d+$').hasMatch(text) ? text : '';
  }

  String _matchId(String input, List<String> patterns) {
    for (final p in patterns) {
      final m = RegExp(p).firstMatch(input);
      if (m != null) return m.group(1)!;
    }
    return '';
  }

  static String txMediaMid(Map<String, dynamic> song) {
    final file = song['file'];
    final fileMap = file is Map ? file : const <String, dynamic>{};
    return (song['strMediaMid'] ??
            song['media_mid'] ??
            song['mediaMid'] ??
            fileMap['strMediaMid'] ??
            fileMap['media_mid'] ??
            fileMap['mediaMid'] ??
            '')
        .toString()
        .trim();
  }

  Future<ImportedPlaylist> _importTx(String id) async {
    final url =
        'https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=$id&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0&g_tk=5381';
    final resp = await _dio.get(
      url,
      options: Options(
        headers: {
          'Referer': 'https://y.qq.com/portal/player.html',
          'Origin': 'https://y.qq.com',
        },
      ),
    );
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (data is! Map ||
        data['code'] != 0 ||
        data['cdlist'] is! List ||
        (data['cdlist'] as List).isEmpty) {
      throw Exception('获取 QQ 歌单失败');
    }
    final cd = data['cdlist'][0] as Map;
    final songlist = cd['songlist'] as List? ?? [];
    final songs = songlist
        .map((s) {
          final m = Map<String, dynamic>.from(s as Map);
          final file = m['file'] is Map
              ? Map<String, dynamic>.from(m['file'])
              : <String, dynamic>{};
          final types = <String>[];
          if ('${file['size_hires'] ?? 0}' != '0' &&
              file['size_hires'] != null) {
            types.add('flac24bit');
          }
          if ('${file['size_flac'] ?? 0}' != '0' && file['size_flac'] != null) {
            types.add('flac');
          }
          if ('${file['size_320mp3'] ?? 0}' != '0' &&
              file['size_320mp3'] != null) {
            types.add('320k');
          }
          if (types.isEmpty && '${file['size_128mp3'] ?? 0}' != '0') {
            types.add('128k');
          }
          final singers =
              (m['singer'] as List?)
                  ?.map((x) => (x as Map)['name'])
                  .join('、') ??
              '';
          final album = m['album'] is Map
              ? Map<String, dynamic>.from(m['album'])
              : <String, dynamic>{};
          final mid = (m['mid'] ?? m['songmid'] ?? '').toString();
          final mediaMid = txMediaMid(m);
          final albumMid = album['mid']?.toString() ?? '';
          final interval = int.tryParse('${m['interval'] ?? 0}') ?? 0;
          return MusicItem(
            id: mid,
            name: (m['title'] ?? m['name'] ?? '').toString(),
            singer: singers,
            album: album['name']?.toString() ?? '',
            duration: Duration(seconds: interval),
            source: 'tx',
            platform: 'tx',
            songmid: mid,
            hash: mid,
            artwork: albumMid.isNotEmpty
                ? 'https://y.gtimg.cn/music/photo_new/T002R300x300M000$albumMid.jpg'
                : '',
            meta: {
              'source': 'tx',
              'songmid': mid,
              if (mediaMid.isNotEmpty) 'strMediaMid': mediaMid,
              'types': types,
              'albumName': album['name'],
            },
          );
        })
        .where((s) => s.songmid != null && s.songmid!.isNotEmpty)
        .toList();

    return ImportedPlaylist(
      name: (cd['dissname'] ?? 'QQ 歌单').toString(),
      source: 'tx',
      sourceId: id,
      songs: songs,
    );
  }

  Future<ImportedPlaylist> _importKw(String id) async {
    final url =
        'https://nplserver.kuwo.cn/pl.svc?op=getlistinfo&pid=$id&pn=0&rn=1000&encode=utf8&keyset=pl2012&identity=kuwo&pcmp4=1&vipver=MUSIC_9.0.5.0_W1&newver=1';
    final resp = await _dio.get(url);
    final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (data is! Map || data['musiclist'] == null) {
      throw Exception('获取酷我歌单失败');
    }
    final re = RegExp(r'level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)');
    final musiclist = data['musiclist'] as List;
    final songs = musiclist
        .map((s) {
          final m = Map<String, dynamic>.from(s as Map);
          final types = <String>[];
          for (final part in '${m['N_MINFO'] ?? ''}'.split(';')) {
            final match = re.firstMatch(part);
            if (match != null) {
              switch (match.group(2)) {
                case '4000':
                  types.add('flac24bit');
                case '2000':
                  types.add('flac');
                case '320':
                  types.add('320k');
                case '128':
                  types.add('128k');
              }
            }
          }
          final rid = (m['rid'] ?? m['id'] ?? '').toString();
          final duration = int.tryParse('${m['duration'] ?? 0}') ?? 0;
          return MusicItem(
            id: rid,
            name: (m['name'] ?? '').toString(),
            singer: (m['artist'] ?? '').toString(),
            album: (m['album'] ?? '').toString(),
            duration: Duration(seconds: duration),
            source: 'kw',
            platform: 'kw',
            songmid: rid,
            hash: rid,
            artwork: kwArtwork(m),
            meta: {'source': 'kw', 'songmid': rid, 'types': types},
          );
        })
        .where((s) => s.songmid != null && s.songmid!.isNotEmpty)
        .toList();

    return ImportedPlaylist(
      name: (data['title'] ?? data['info']?['name'] ?? '酷我歌单').toString(),
      source: 'kw',
      sourceId: id,
      songs: songs,
    );
  }

  // ==================== 网易云歌单 ====================
  // 方法参考 Suxiaoqinx/Netease_url：
  //   1) POST music.163.com/api/v6/playlist/detail 取歌单元信息与完整 trackIds
  //      （该接口的 tracks 只回前若干首，直接读 tracks 会漏歌）；
  //   2) POST interface3.music.163.com/api/v3/song/detail，c 为 id 数组，100 首一批；
  //   3) 按 trackIds 原顺序回填，保留重复曲目，并带上 privilege 版权信息。

  static const wyPlaylistDetailUrl =
      'https://music.163.com/api/v6/playlist/detail';
  static const wySongDetailUrl =
      'https://interface3.music.163.com/api/v3/song/detail';

  /// 分批大小：批量详情接口对单次 id 数量敏感，100 首一批最稳。
  static const wySongDetailBatchSize = 100;

  /// 分批请求的并发度，兼顾大歌单耗时与对接口的礼貌。
  static const _wySongDetailConcurrency = 3;

  static const _wyUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/2.10.2.200154';

  static final _digitsOnly = RegExp(r'^\d+$');

  static Map<String, String> get _wyHeaders => const {
        'User-Agent': _wyUserAgent,
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
      };

  Future<ImportedPlaylist> _importWy(
    String id, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    final playlist = await _fetchWyPlaylist(id);

    final trackIds = wyTrackIds(playlist);
    if (trackIds.isEmpty) {
      throw Exception('歌单为空或无法解析');
    }

    final details = await _fetchWySongDetails(trackIds, onProgress: onProgress);
    final songs = wySongsFromDetails(trackIds, details);
    if (songs.isEmpty) {
      throw Exception('歌单解析失败，歌单可能已私密或曲目全部不可用');
    }

    final name = '${playlist['name'] ?? ''}'.trim();
    return ImportedPlaylist(
      name: name.isEmpty ? '网易云歌单' : name,
      source: 'wy',
      sourceId: id,
      songs: songs,
    );
  }

  Future<Map<String, dynamic>> _fetchWyPlaylist(String id) async {
    const failure = '获取网易云歌单失败，请确认歌单 ID 正确且歌单公开';

    final resp = await _dio.post(
      wyPlaylistDetailUrl,
      data: {'id': id},
      options: Options(
        headers: _wyHeaders,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final raw = resp.data;
    dynamic body = raw;
    if (raw is String) {
      try {
        body = jsonDecode(raw);
      } catch (_) {
        throw Exception(failure);
      }
    }
    if (body is! Map || body['code'] != 200 || body['playlist'] is! Map) {
      throw Exception(failure);
    }
    return Map<String, dynamic>.from(body['playlist'] as Map);
  }

  /// 取出有序曲目 ID：优先官方 trackIds（完整列表），缺失时退回 tracks。
  /// 返回顺序即歌单顺序，且保留同一首歌的多份拷贝。
  static List<String> wyTrackIds(Map<String, dynamic> playlist) {
    List<String> collect(dynamic source) {
      final ids = <String>[];
      if (source is! List) return ids;
      for (final entry in source) {
        final id = entry is Map ? '${entry['id'] ?? ''}' : '${entry ?? ''}';
        if (_digitsOnly.hasMatch(id.trim())) ids.add(id.trim());
      }
      return ids;
    }

    final fromTrackIds = collect(playlist['trackIds']);
    return fromTrackIds.isNotEmpty
        ? fromTrackIds
        : collect(playlist['tracks']);
  }

  Future<Map<String, Map<String, dynamic>>> _fetchWySongDetails(
    List<String> ids, {
    void Function(int loaded, int total)? onProgress,
  }) async {
    // 同一首歌可能有多份拷贝，请求前先去重，避免浪费批量配额。
    final uniqueIds = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (seen.add(id)) uniqueIds.add(id);
    }

    final batches = <List<String>>[];
    for (var i = 0; i < uniqueIds.length; i += wySongDetailBatchSize) {
      batches.add(
        uniqueIds.sublist(
          i,
          (i + wySongDetailBatchSize).clamp(0, uniqueIds.length),
        ),
      );
    }

    final total = uniqueIds.length;
    var loaded = 0;
    onProgress?.call(0, total);

    final details = <String, Map<String, dynamic>>{};
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < batches.length) {
        final batch = batches[cursor++];
        try {
          details.addAll(await _postWySongDetail(batch));
        } catch (_) {
          // 单批失败不影响其他批次，缺失曲目会在回填时被跳过。
        }
        loaded += batch.length;
        onProgress?.call(loaded, total);
      }
    }

    await Future.wait([
      for (var i = 0; i < _wySongDetailConcurrency; i++) worker(),
    ]);
    return details;
  }

  Future<Map<String, Map<String, dynamic>>> _postWySongDetail(
    List<String> ids,
  ) async {
    final payload = jsonEncode([
      for (final id in ids) {'id': int.parse(id), 'v': 0},
    ]);

    final resp = await _dio.post(
      wySongDetailUrl,
      data: {'c': payload},
      options: Options(
        headers: _wyHeaders,
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );

    final raw = resp.data;
    dynamic body = raw;
    if (raw is String) {
      try {
        body = jsonDecode(raw);
      } catch (_) {
        return const {};
      }
    }
    if (body is! Map || body['code'] != 200) return const {};
    return wyDecodeSongDetail(Map<String, dynamic>.from(body));
  }

  /// 解析 api/v3/song/detail 响应为 id → 曲目，并把 privileges 按 id 合并进去。
  static Map<String, Map<String, dynamic>> wyDecodeSongDetail(
    Map<String, dynamic> body,
  ) {
    final privileges = <String, Map<String, dynamic>>{};
    for (final entry in (body['privileges'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final id = '${entry['id'] ?? ''}';
      if (id.isNotEmpty) privileges[id] = Map<String, dynamic>.from(entry);
    }

    final details = <String, Map<String, dynamic>>{};
    for (final entry in (body['songs'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final id = '${entry['id'] ?? ''}';
      if (id.isEmpty) continue;
      final song = Map<String, dynamic>.from(entry);
      final privilege = privileges[id];
      if (privilege != null) song['privilege'] = privilege;
      details[id] = song;
    }
    return details;
  }

  /// 按 [trackIds] 顺序组装曲目：保留同曲多份拷贝，跳过详情缺失的曲目。
  static List<MusicItem> wySongsFromDetails(
    List<String> trackIds,
    Map<String, Map<String, dynamic>> details,
  ) {
    final songs = <MusicItem>[];
    for (final id in trackIds) {
      final detail = details[id];
      if (detail == null) continue;
      songs.add(wyToMusicItem(detail));
    }
    return songs;
  }

  /// 把网易云 song/detail 的原始条目转成 [MusicItem]。
  /// 原始字段整体保留在 meta 中，自定义音源仍可读取 fee / privilege 等版权信息。
  static MusicItem wyToMusicItem(Map<String, dynamic> song) {
    final id = '${song['id'] ?? ''}';
    final ar = song['ar'] as List? ?? const [];
    final al = song['al'] is Map
        ? Map<String, dynamic>.from(song['al'] as Map)
        : <String, dynamic>{};
    final dt = int.tryParse('${song['dt'] ?? 0}') ?? 0;
    final privilege = song['privilege'] is Map
        ? Map<String, dynamic>.from(song['privilege'] as Map)
        : null;
    final singers = ar
        .map((a) => a is Map ? '${a['name'] ?? ''}'.trim() : '')
        .where((s) => s.isNotEmpty)
        .join('、');

    final meta = Map<String, dynamic>.from(song)
      ..['source'] = 'wy'
      ..['songmid'] = id
      ..['types'] = wyTypesFromPrivilege(privilege);

    return MusicItem(
      id: id,
      name: '${song['name'] ?? ''}'.trim(),
      singer: singers.isEmpty ? '未知歌手' : singers,
      album: '${al['name'] ?? ''}'.trim(),
      duration: Duration(milliseconds: dt),
      source: 'wy',
      platform: 'wy',
      songmid: id,
      hash: id,
      artwork: normalizeNeteaseArtwork(al['picUrl']),
      meta: meta,
    );
  }

  /// 由 privilege 的 maxbr 推断曲目可获取的音质，供自定义音源与降级播放使用。
  static List<String> wyTypesFromPrivilege(Map<String, dynamic>? privilege) {
    if (privilege == null) return const ['320k', '128k'];

    final maxbr = int.tryParse('${privilege['maxbr'] ?? 0}') ?? 0;
    final playable = int.tryParse('${privilege['pl'] ?? 0}') ?? 0;
    final br = maxbr > 0 ? maxbr : playable;

    return [
      if (br >= 1999000) 'flac24bit',
      if (br >= 900000) 'flac',
      if (br >= 320000) '320k',
      '128k',
    ];
  }
}
