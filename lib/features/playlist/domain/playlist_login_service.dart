import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/music_source/platform/kugou_sign.dart';
import '../../../core/music_source/platform/wy_source.dart';
import '../../../core/network/app_http_client.dart';
import 'playlist_login.dart';

/// 导入歌单用的平台登录。
///
/// 四家的能力不一样，这里按平台分别实现，对上层只暴露四个动作：
/// [createQr] 取二维码、[poll] 查扫码状态、[myPlaylists] 取账号歌单、
/// [loginWithCookie] 用网页 Cookie 登录（酷我，以及酷狗的兜底）。
///
/// 流程参考 Marginal-Z/YUNYIN（Dart，第三方音乐客户端）的扫码登录实现：
/// - 网易云：weapi `/login/qrcode/unikey` 取 unikey，轮询
///   `/login/qrcode/client/login`，803 时从 Set-Cookie 取 MUSIC_U。
/// - QQ：ptqrshow 取图与 qrsig，ptqrlogin 轮询（65/66/67/0），确认后走
///   check_sig → graph.qq.com authorize → QQLogin 换 musickey。
/// - 酷狗：`login-user.kugou.com/v2/qrcode` 取码，`get_userinfo_qrcode` 轮询，
///   状态 4 时拿到 token 与 userid。
/// - 酷我：没有自家的扫码接口，网页版的第三方登录走微信开放平台扫码
///   （appid `wx41c1275bb3e28427`，redirect 到酷我的 WeixinCallback）。
///   扫完确认后酷我服务端把登录态写进回调链的 Set-Cookie，整条链路和
///   网页版一致，不需要任何人肉复制 Cookie。
class PlaylistLoginService {
  PlaylistLoginService({Dio? dio, PlaylistAccountStore? store})
    : _dio =
          dio ??
          AppHttpClient.create(
            options: BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              // 登录流程要靠 302 的 Location 取授权码，不能让 dio 自己跟到底。
              validateStatus: (status) => status != null && status < 500,
            ),
          ),
      _store = store ?? PlaylistAccountStore();

  final Dio _dio;
  final PlaylistAccountStore _store;
  final WySource _wy = WySource();

  // ── 会话内状态 ─────────────────────────────────────────

  /// 网易云扫码过程中收到的 Cookie。
  final Map<String, String> _wyCookies = {};

  /// QQ 扫码过程中各域名下发的 Cookie，键为 `域名|名称`。
  final Map<String, String> _qqJar = {};
  String? _qqQrKey;
  Future<LinkedPlatformAccount>? _qqFinishing;
  String? _qqFinishingKey;

  /// 酷我微信扫码过程中各域名下发的 Cookie，键为 `域名|名称`。
  /// 回调链会把 `kw_token` / `userid` 写进这里；不含它时回调页只发一个
  /// 反爬 Cookie，所以整条链必须复用同一个 jar。
  final Map<String, String> _kwJar = {};

  /// 酷狗的设备标识。扫码登录只需要 mid；dfid 注册要走 RSA 加密的设备注册，
  /// 这里按未注册设备（`-`）请求，取不到歌单时由上层提示手动链接导入。
  late final String _kgMid = kugouDeviceMid();

  static const _qqAppId = '716027609';
  static const _qqThirdAid = '100497308';
  static const _qqApi = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

  static const _kgWebKey = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const _kgAppId = 1005;
  static const _kgClientVer = 20489;

  /// 酷我网页版用的微信开放平台网站应用。扫码页、二维码与长轮询都在
  /// open.weixin.qq.com，网页版就是这套参数，改不了也不该改。
  static const _kwWxAppId = 'wx41c1275bb3e28427';

  /// 微信回调先打到酷我的中转页，再由它 302 到网页回调页。
  /// 中转页支持 HTTPS，走 https 既符合项目的出网策略，也省一次协议升级跳转。
  static const _kwWxCallback =
      'https://i.kuwo.cn/US/platform/WeixinCallback.jsp?f=web'
      '&callbackUrl=https%3A%2F%2Fwww.kuwo.cn%2Fcallback';

  static const _kwWxQrPage = 'https://open.weixin.qq.com/connect/qrconnect';
  static const _kwWxLongPoll =
      'https://long.open.weixin.qq.com/connect/l/qrconnect';

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // ── 对外接口 ───────────────────────────────────────────

  /// 该平台是否支持扫码登录。四家现在都有扫码入口：酷我走微信开放平台。
  static bool supportsQr(String source) =>
      source == 'wy' || source == 'tx' || source == 'kg' || source == 'kw';

  Future<PlatformQrTicket> createQr(String source) {
    return switch (source) {
      'wy' => _createWyQr(),
      'tx' => _createTxQr(),
      'kg' => _createKgQr(),
      'kw' => _createKwQr(),
      _ => Future.error(UnsupportedError('该平台不支持扫码登录')),
    };
  }

  Future<PlatformQrPoll> poll(String source, PlatformQrTicket ticket) {
    return switch (source) {
      'wy' => _pollWyQr(ticket),
      'tx' => _pollTxQr(ticket),
      'kg' => _pollKgQr(ticket),
      'kw' => _pollKwQr(ticket),
      _ => Future.error(UnsupportedError('该平台不支持扫码登录')),
    };
  }

  /// 取消进行中的扫码，丢掉本轮的临时 Cookie。
  void cancelQr(String source) {
    switch (source) {
      case 'wy':
        _wyCookies.clear();
      case 'tx':
        _qqJar.clear();
        _qqQrKey = null;
        _qqFinishing = null;
        _qqFinishingKey = null;
      case 'kw':
        _kwJar.clear();
      default:
        break;
    }
  }

  Future<LinkedPlatformAccount?> current(String source) => _store.read(source);

  Future<void> logout(String source) async {
    cancelQr(source);
    await _store.clear(source);
  }

  /// 用网页 Cookie 登录。酷我扫码偶有被网页改版打断的时候，这是它的兜底路径。
  Future<LinkedPlatformAccount> loginWithCookie(
    String source,
    String rawCookie,
  ) async {
    final cookie = _parseCookieString(rawCookie);
    if (cookie.isEmpty) {
      throw Exception('没有识别到 Cookie，请复制完整的一整行');
    }
    final userId =
        cookie['userid'] ??
        cookie['KugooID'] ??
        cookie['uid'] ??
        cookie['kw_id'] ??
        '';
    if (source == 'kg' && (cookie['KugooID'] ?? '').isEmpty) {
      throw Exception('酷狗 Cookie 里缺少 KuGoo（KugooID），请重新复制完整 Cookie');
    }
    var account = LinkedPlatformAccount(
      source: source,
      userId: userId,
      nickname: source == 'kg' ? '酷狗账号' : '酷我账号',
      credentials: cookie,
      extra: {if (source == 'kg') 'mid': _kgMid},
    );
    // 酷狗歌单接口还依赖设备注册，取不到歌单不等于 Cookie 无效，所以只在
    // 酷我上做一次连通性校验，避免把网络问题误报成「Cookie 已过期」。
    if (source == 'kw') {
      final playlists = await _safePlaylists(account);
      if (playlists == null) {
        throw Exception('Cookie 无效或已过期，请重新登录网页版后再复制');
      }
    }
    if (source == 'kg') {
      final nickname = await _kgNickname(account);
      if (nickname.isNotEmpty) {
        account = account.copyWith(nickname: nickname);
      }
    }
    await _store.write(account);
    return account;
  }

  Future<List<MyPlaylistSummary>> myPlaylists(
    LinkedPlatformAccount account,
  ) async {
    final list = await _safePlaylists(account);
    if (list == null) {
      throw Exception('登录已失效，请退出后重新登录');
    }
    return list;
  }

  /// 校验并取歌单：失败返回 null，由调用方决定是提示还是当作 Cookie 无效。
  Future<List<MyPlaylistSummary>?> _safePlaylists(
    LinkedPlatformAccount account,
  ) async {
    try {
      return switch (account.source) {
        'wy' => _wyPlaylists(account),
        'tx' => _txPlaylists(account),
        'kg' => _kgPlaylists(account),
        'kw' => _kwPlaylists(account),
        _ => const <MyPlaylistSummary>[],
      };
    } catch (_) {
      return null;
    }
  }

  // ── 网易云 ─────────────────────────────────────────────

  Future<PlatformQrTicket> _createWyQr() async {
    _wyCookies.clear();
    final body = await _wyPost(
      'https://music.163.com/weapi/login/qrcode/unikey',
      {'type': 1},
    );
    final key = '${body['unikey'] ?? ''}'.trim();
    if (key.isEmpty) {
      throw Exception('网易云没有返回二维码，请稍后重试');
    }
    return PlatformQrTicket(
      source: 'wy',
      key: key,
      appName: '网易云音乐 App',
      content: 'https://music.163.com/login?codekey=$key',
    );
  }

  Future<PlatformQrPoll> _pollWyQr(PlatformQrTicket ticket) async {
    final body = await _wyPost(
      'https://music.163.com/weapi/login/qrcode/client/login',
      {'key': ticket.key, 'type': 1},
    );
    switch (int.tryParse('${body['code']}') ?? 0) {
      case 800:
        return const PlatformQrPoll(PlatformQrState.expired);
      case 802:
        return const PlatformQrPoll(PlatformQrState.scanned);
      case 803:
        // 网页版接口的凭据在 Set-Cookie 里，JSON 的 cookie 字段经常是空的。
        final inline = body['cookie'];
        if (inline is String && inline.isNotEmpty) {
          _wyCookies.addAll(_parseCookieString(inline));
        }
        if ((_wyCookies['MUSIC_U'] ?? '').isEmpty) {
          throw Exception('已在手机上确认，但网易云没有返回登录凭据，请刷新二维码重试');
        }
        _wyCookies.remove('MUSIC_A');
        final account = await _wyAccount();
        _wyCookies.clear();
        await _store.write(account);
        return PlatformQrPoll(PlatformQrState.confirmed, account);
      default:
        return const PlatformQrPoll(PlatformQrState.waiting);
    }
  }

  Future<LinkedPlatformAccount> _wyAccount() async {
    final body = await _wyPost(
      'https://music.163.com/weapi/w/nuser/account/get',
      {'csrf_token': _wyCookies['__csrf'] ?? ''},
      cookie: _wyCookieHeader(),
    );
    final account = body['account'];
    final profile = body['profile'];
    final id = account is Map ? '${account['id'] ?? ''}' : '';
    if (id.isEmpty) {
      throw Exception('登录没有生效（网易云没有返回账号信息），请刷新二维码重试');
    }
    final map = profile is Map ? profile : const {};
    return LinkedPlatformAccount(
      source: 'wy',
      userId: id,
      nickname: '${map['nickname'] ?? '网易云用户'}',
      avatar: '${map['avatarUrl'] ?? ''}',
      credentials: Map<String, String>.from(_wyCookies),
      extra: {if (map['vipType'] != null) 'vipType': '${map['vipType']}'},
    );
  }

  Future<List<MyPlaylistSummary>> _wyPlaylists(
    LinkedPlatformAccount account,
  ) async {
    final body = await _wyPost('https://music.163.com/weapi/user/playlist', {
      'uid': account.userId,
      'limit': 1000,
      'offset': 0,
      'includeVideo': true,
    }, cookie: account.cookieHeader);
    final raw = body['playlist'];
    if (raw is! List) return const [];
    final out = <MyPlaylistSummary>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['id'] ?? ''}';
      if (id.isEmpty) continue;
      out.add(
        MyPlaylistSummary(
          id: id,
          name: '${entry['name'] ?? ''}'.trim().isEmpty
              ? '网易云歌单 $id'
              : '${entry['name']}'.trim(),
          cover: '${entry['coverImgUrl'] ?? ''}',
          trackCount: int.tryParse('${entry['trackCount'] ?? 0}') ?? 0,
          isFavorites: '${entry['specialType'] ?? 0}' == '5',
        ),
      );
    }
    // 「我喜欢的音乐」置顶，其余保持平台顺序。
    out.sort((a, b) {
      if (a.isFavorites == b.isFavorites) return 0;
      return a.isFavorites ? -1 : 1;
    });
    return out;
  }

  Map<String, String> _wyHeaders(String? cookie) => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 '
        'NeteaseMusicDesktop/2.10.2.200154',
    'Referer': 'https://music.163.com/',
    'Origin': 'https://music.163.com',
    if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
  };

  String _wyCookieHeader() => _wyCookies.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  Future<Map<String, dynamic>> _wyPost(
    String url,
    Map<String, dynamic> payload, {
    String? cookie,
  }) async {
    final params = _wy.weapi(payload);
    final response = await _dio.post<String>(
      url,
      data: params,
      options: Options(
        headers: _wyHeaders(cookie),
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
      ),
    );
    for (final raw in response.headers['set-cookie'] ?? const <String>[]) {
      _wyCookies.addAll(_parseCookieString(raw));
    }
    final body = _decodeJson(response.data);
    return body ?? const {};
  }

  // ── QQ 音乐 ────────────────────────────────────────────

  Future<PlatformQrTicket> _createTxQr() async {
    cancelQr('tx');
    final response = await _dio.get<List<int>>(
      'https://ssl.ptlogin2.qq.com/ptqrshow',
      queryParameters: {
        'appid': _qqAppId,
        'e': 2,
        'l': 'M',
        's': 3,
        'd': 72,
        'v': 4,
        't': math.Random().nextDouble(),
        'daid': 383,
        'pt_3rd_aid': _qqThirdAid,
      },
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Referer': 'https://xui.ptlogin2.qq.com/'},
      ),
    );
    _absorbCookies(
      response.headers,
      Uri.parse('https://ssl.ptlogin2.qq.com/ptqrshow'),
      _qqJar,
    );
    final qrsig = _qqJarValue('qrsig') ?? '';
    final image = response.data;
    if (qrsig.isEmpty || image == null || image.isEmpty) {
      throw Exception('QQ 没有返回登录二维码，请稍后重试');
    }
    _qqQrKey = qrsig;
    return PlatformQrTicket(
      source: 'tx',
      key: qrsig,
      appName: 'QQ 或 TIM',
      image: Uint8List.fromList(image),
    );
  }

  Future<PlatformQrPoll> _pollTxQr(PlatformQrTicket ticket) async {
    if (_qqQrKey != null && _qqQrKey != ticket.key) {
      throw StateError('二维码已失效，请重新扫码');
    }
    final uri = Uri.https('ssl.ptlogin2.qq.com', '/ptqrlogin');
    final response = await _dio.get<String>(
      uri.toString(),
      queryParameters: {
        'u1': 'https://graph.qq.com/oauth2.0/login_jump',
        'ptqrtoken': '${_hash33(ticket.key)}',
        'ptredirect': 0,
        'h': 1,
        't': 1,
        'g': 1,
        'from_ui': 1,
        'ptlang': 2052,
        'action': '0-0-${DateTime.now().millisecondsSinceEpoch}',
        'js_ver': 20102616,
        'js_type': 1,
        'pt_uistyle': 40,
        'aid': _qqAppId,
        'daid': 383,
        'pt_3rd_aid': _qqThirdAid,
        'has_onekey': 1,
      },
      options: Options(
        headers: {
          'Referer': 'https://xui.ptlogin2.qq.com/',
          'Cookie': [
            _qqCookiesFor(uri),
            'qrsig=${ticket.key}',
          ].where((part) => part.isNotEmpty).join('; '),
        },
      ),
    );
    _absorbCookies(response.headers, uri, _qqJar);
    final args = RegExp(
      r"'([^']*)'",
    ).allMatches(response.data ?? '').map((m) => m[1] ?? '').toList();
    final code = args.isEmpty ? '' : args.first;
    switch (code) {
      case '66':
        return const PlatformQrPoll(PlatformQrState.waiting);
      case '67':
        return const PlatformQrPoll(PlatformQrState.scanned);
      case '65':
        return const PlatformQrPoll(PlatformQrState.expired);
      case '0':
        final checkSig = args.length > 2 ? args[2] : '';
        // 同一张二维码只换一次凭据：pp 换到的结果缓存住，重复轮询直接复用。
        if (_qqFinishing != null && _qqFinishingKey == ticket.key) {
          return PlatformQrPoll(PlatformQrState.confirmed, await _qqFinishing!);
        }
        final future = _qqFinishLogin(checkSig);
        _qqFinishing = future;
        _qqFinishingKey = ticket.key;
        try {
          final account = await future;
          await _store.write(account);
          return PlatformQrPoll(PlatformQrState.confirmed, account);
        } catch (_) {
          if (identical(_qqFinishing, future)) {
            _qqFinishing = null;
            _qqFinishingKey = null;
          }
          rethrow;
        }
      default:
        throw Exception(
          args.length > 4 && args[4].isNotEmpty ? args[4] : 'QQ 登录失败（$code）',
        );
    }
  }

  Future<LinkedPlatformAccount> _qqFinishLogin(String checkSig) async {
    final callback = _qqTrustedUri(Uri.tryParse(checkSig));
    final query = callback.queryParameters;
    if (callback.path != '/check_sig' ||
        (query['uin'] ?? '').isEmpty ||
        (query['ptsigx'] ?? '').isEmpty) {
      throw Exception('QQ 没有返回完整的扫码授权凭据，请重新扫码');
    }
    var current = Uri.https('ssl.ptlogin2.graph.qq.com', '/check_sig', {
      'uin': query['uin']!,
      'ptsigx': query['ptsigx']!,
      'pttype': '1',
      'service': 'ptqrlogin',
      'nodirect': '0',
      's_url': 'https://graph.qq.com/oauth2.0/login_jump',
      'ptlang': '2052',
      'ptredirect': '100',
      'aid': _qqAppId,
      'daid': '383',
      'j_later': '0',
      'low_login_hour': '0',
      'regmaster': '0',
      'pt_login_type': '3',
      'pt_aid': '0',
      'pt_aaid': '16',
      'pt_light': '0',
      'pt_3rd_aid': _qqThirdAid,
    });
    // check_sig 会连跳几跳，每跳都可能下发新的 Cookie，手动跟到 p_skey 为止。
    for (var hop = 0; hop < 6; hop++) {
      final response = await _dio.get<String>(
        current.toString(),
        options: Options(
          followRedirects: false,
          headers: {
            'Cookie': _qqAllCookies(),
            'Referer': 'https://xui.ptlogin2.qq.com/',
            'User-Agent': _desktopUa,
          },
        ),
      );
      _absorbCookies(response.headers, current, _qqJar);
      if ((_qqJarValue('p_skey') ?? '').isNotEmpty) break;
      final location = response.headers.value('location');
      final status = response.statusCode ?? 0;
      if (status < 300 ||
          status >= 400 ||
          location == null ||
          location.isEmpty) {
        break;
      }
      current = _qqTrustedUri(current.resolve(location));
    }
    final pSkey = _qqJarValue('p_skey');
    if (pSkey == null || pSkey.isEmpty) {
      throw Exception('登录失败：没有获得 QQ 互联授权凭据（p_skey），请重新扫码');
    }
    // 授权码只能用一次，两种已知可用的交换方式各取一个新码试一次。
    final failures = <String>[];
    for (final scoped in const [true, false]) {
      final code = await _qqAuthorizeCode(pSkey);
      if (code == null) {
        failures.add('授权码（${scoped ? '按域' : '全部'} Cookie）');
        continue;
      }
      final login = await _dio.post<String>(
        _qqApi,
        data: jsonEncode({
          'comm': {
            'g_tk': 5381,
            'platform': 'yqq',
            'ct': 24,
            'cv': 0,
            if (scoped) 'tmeLoginType': 2,
          },
          'req': {
            'module': 'QQConnectLogin.LoginServer',
            'method': 'QQLogin',
            'param': {'code': code},
          },
        }),
        options: Options(
          headers: {
            'Cookie': scoped
                ? _qqCookiesFor(Uri.parse(_qqApi))
                : _qqAllCookies(),
            'Referer': 'https://y.qq.com/',
            'User-Agent': _desktopUa,
            'Content-Type': 'application/json',
          },
        ),
      );
      _absorbCookies(login.headers, Uri.parse(_qqApi), _qqJar);
      final body = _decodeJson(login.data);
      final req = body?['req'];
      final rawCode = req is Map ? (req['code'] ?? body?['code']) : null;
      final resultCode = int.tryParse('${rawCode ?? -1}') ?? -1;
      if (resultCode != 0) {
        final reason = req is Map
            ? '${req['msg'] ?? req['message'] ?? ''}'.trim()
            : '';
        failures.add('$resultCode${reason.isEmpty ? '' : '：$reason'}');
        continue;
      }
      final data = req is Map && req['data'] is Map
          ? Map<String, dynamic>.from(req['data'] as Map)
          : const <String, dynamic>{};
      var uin = '${data['musicid'] ?? data['uin'] ?? ''}'.replaceAll(
        RegExp(r'^0+$'),
        '',
      );
      if (uin.isEmpty) {
        uin = (_qqJarValue('uin') ?? '').replaceFirst(RegExp(r'^o0*'), '');
      }
      var key = '${data['musickey'] ?? ''}';
      if (key.isEmpty) {
        key = _qqJarValue('qqmusic_key') ?? _qqJarValue('qm_keyst') ?? '';
      }
      if (uin.isEmpty || key.isEmpty) {
        failures.add('QQ 音乐没有返回 musickey');
        continue;
      }
      final account = await _qqProfile(uin, key);
      _qqJar.clear();
      _qqQrKey = null;
      _qqFinishing = null;
      _qqFinishingKey = null;
      return account;
    }
    throw Exception('QQ 音乐凭据交换失败（${failures.join('；')}），请重新扫码');
  }

  Future<String?> _qqAuthorizeCode(String pSkey) async {
    final response = await _dio.post<String>(
      'https://graph.qq.com/oauth2.0/authorize',
      data: {
        'response_type': 'code',
        'client_id': _qqThirdAid,
        'redirect_uri':
            'https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/',
        'scope': 'get_user_info,get_app_friends',
        'state': 'state',
        'switch': '',
        'from_ptlogin': 1,
        'src': 1,
        'update_auth': 1,
        'openapi': '1010_1030',
        'g_tk': '${_hash33(pSkey, 5381)}',
        'auth_time': '${DateTime.now().millisecondsSinceEpoch}',
        'ui': _randomUuid(),
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        headers: {
          'Cookie': _qqAllCookies(),
          'Referer': 'https://graph.qq.com/',
          'Origin': 'https://graph.qq.com',
          'User-Agent': _desktopUa,
        },
      ),
    );
    _absorbCookies(
      response.headers,
      Uri.parse('https://graph.qq.com/oauth2.0/authorize'),
      _qqJar,
    );
    final location = response.headers.value('location') ?? '';
    final code = Uri.tryParse(location)?.queryParameters['code'] ?? '';
    return code.isEmpty ? null : code;
  }

  Future<LinkedPlatformAccount> _qqProfile(String uin, String key) async {
    var nickname = 'QQ 用户 $uin';
    var avatar = '';
    try {
      final response = await _dio.get<String>(
        'https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg',
        queryParameters: {
          'cid': 205360838,
          'userid': uin,
          'reqfrom': 1,
          'format': 'json',
          'g_tk': '${_hash33(key, 5381)}',
        },
        options: Options(
          headers: {
            'Cookie': _qqCookieHeader(uin, key),
            'Referer': 'https://y.qq.com/',
            'User-Agent': _desktopUa,
          },
        ),
      );
      final body = _decodeJson(response.data);
      final data = body?['data'];
      final creator = data is Map ? data['creator'] : null;
      if (creator is Map) {
        final nick = '${creator['nick'] ?? creator['nickname'] ?? ''}'.trim();
        if (nick.isNotEmpty) nickname = nick;
        avatar = '${creator['headpic'] ?? creator['avatarUrl'] ?? ''}';
      }
    } catch (_) {
      // 昵称取不到不影响导入歌单，保留默认昵称。
    }
    return LinkedPlatformAccount(
      source: 'tx',
      userId: uin,
      nickname: nickname,
      avatar: avatar,
      credentials: {
        'uin': uin,
        'qqmusic_uin': uin,
        'qqmusic_key': key,
        'qm_keyst': key,
        'tmeLoginType': '2',
      },
    );
  }

  Future<List<MyPlaylistSummary>> _txPlaylists(
    LinkedPlatformAccount account,
  ) async {
    final uin = account.userId;
    final key =
        account.credential('qqmusic_key') ??
        account.credential('qm_keyst') ??
        '';
    final response = await _dio.post<String>(
      _qqApi,
      data: jsonEncode({
        'comm': {
          'ct': 24,
          'cv': 0,
          'uin': uin,
          'format': 'json',
          'g_tk': _hash33(key, 5381),
        },
        'req': {
          'module': 'music.musicasset.PlaylistBaseRead',
          'method': 'GetPlaylistByUin',
          'param': {'uin': uin},
        },
      }),
      options: Options(
        headers: {
          'Cookie': account.cookieHeader,
          'Referer': 'https://y.qq.com/',
          'User-Agent': _desktopUa,
          'Content-Type': 'application/json',
        },
      ),
    );
    final body = _decodeJson(response.data);
    final req = body?['req'];
    if (req is! Map) return const [];
    if ('${req['code'] ?? ''}' != '0') {
      throw Exception('QQ 音乐没有返回歌单（${req['code']}）');
    }
    final data = req['data'];
    final raw = data is Map ? data['v_playlist'] : null;
    if (raw is! List) return const [];
    final out = <MyPlaylistSummary>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['dissid'] ?? entry['tid'] ?? ''}';
      if (id.isEmpty || id == '0') continue;
      out.add(
        MyPlaylistSummary(
          id: id,
          name: '${entry['dissname'] ?? entry['title'] ?? ''}'.trim().isEmpty
              ? 'QQ 歌单 $id'
              : '${entry['dissname'] ?? entry['title']}'.trim(),
          cover: '${entry['logo'] ?? ''}',
          trackCount:
              int.tryParse('${entry['song_cnt'] ?? entry['songnum'] ?? 0}') ??
              0,
        ),
      );
    }
    return out;
  }

  // ── 酷狗 ───────────────────────────────────────────────

  Future<PlatformQrTicket> _createKgQr() async {
    final params = <String, String>{
      'dfid': '-',
      'mid': _kgMid,
      'uuid': '-',
      'clientver': '$_kgClientVer',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'appid': '1001',
      'type': '1',
      'plat': '4',
      'qrcode_txt':
          'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=$_kgAppId&',
      'srcappid': '2919',
    };
    params['signature'] = kugouSign(_kgWebKey, params);
    final body = await _kgGet('https://login-user.kugou.com/v2/qrcode', params);
    final data = body['data'];
    final key = data is Map ? '${data['qrcode'] ?? ''}'.trim() : '';
    if ('${body['status']}' != '1' || key.isEmpty) {
      throw Exception('酷狗没有返回登录二维码${_kgWhy(body)}');
    }
    return PlatformQrTicket(
      source: 'kg',
      key: key,
      appName: '酷狗音乐 App',
      content:
          'https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=$key',
    );
  }

  Future<PlatformQrPoll> _pollKgQr(PlatformQrTicket ticket) async {
    final params = <String, String>{
      'dfid': '-',
      'mid': _kgMid,
      'uuid': '-',
      'clientver': '$_kgClientVer',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'plat': '4',
      'appid': '$_kgAppId',
      'srcappid': '2919',
      'qrcode': ticket.key,
    };
    params['signature'] = kugouSign(_kgWebKey, params);
    final body = await _kgGet(
      'https://login-user.kugou.com/v2/get_userinfo_qrcode',
      params,
    );
    if ('${body['status']}' != '1') {
      throw Exception('查询酷狗扫码状态失败${_kgWhy(body)}');
    }
    final data = body['data'];
    final map = data is Map ? data : const {};
    switch ('${map['status']}') {
      case '0':
        return const PlatformQrPoll(PlatformQrState.expired);
      case '1':
        return const PlatformQrPoll(PlatformQrState.waiting);
      case '2':
        return const PlatformQrPoll(PlatformQrState.scanned);
      case '4':
        final token = '${map['token'] ?? ''}'.trim();
        final userId = '${map['userid'] ?? ''}'.trim();
        if (token.isEmpty || userId.isEmpty || userId == '0') {
          throw Exception('酷狗没有返回登录凭据，请重新扫码');
        }
        final account = LinkedPlatformAccount(
          source: 'kg',
          userId: userId,
          nickname: '${map['nickname'] ?? ''}'.trim().isEmpty
              ? '酷狗用户 $userId'
              : '${map['nickname']}'.trim(),
          avatar: '${map['pic'] ?? ''}',
          credentials: {'token': token},
          extra: {'mid': _kgMid},
        );
        await _store.write(account);
        return PlatformQrPoll(PlatformQrState.confirmed, account);
      default:
        throw Exception('酷狗扫码登录失败（状态 ${map['status']}）');
    }
  }

  /// 账号歌单：酷狗客户端的云歌单接口。
  ///
  /// 未注册设备（dfid 为 `-`）时酷狗可能拒绝，这里让异常冒到 [_safePlaylists]，
  /// 由界面提示改用链接导入。
  Future<List<MyPlaylistSummary>> _kgPlaylists(
    LinkedPlatformAccount account,
  ) async {
    final token = account.credential('token') ?? '';
    final mid = account.extra['mid'] ?? _kgMid;
    final params = <String, String>{
      'dfid': '-',
      'mid': mid,
      'uuid': '-',
      'appid': '$_kgAppId',
      'clientver': '$_kgClientVer',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'token': token,
      'userid': account.userId,
      'plat': '1',
    };
    final body = <String, dynamic>{
      'userid': int.tryParse(account.userId) ?? 0,
      'token': token,
      'total_ver': 979,
      'type': 2,
      'page': 1,
      'pagesize': 300,
    };
    final payload = jsonEncode(body);
    params['signature'] = kugouSign(
      'OIlwieks28dk2k092lksi2UIkp',
      params,
      payload,
    );
    final response = await _dio.post<String>(
      'https://gateway.kugou.com/v7/get_all_list',
      queryParameters: params,
      data: payload,
      options: Options(
        headers: {
          'User-Agent': 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi',
          'dfid': '-',
          'mid': mid,
          'clienttime': params['clienttime'],
          'x-router': 'cloudlist.service.kugou.com',
          'Content-Type': 'application/json',
        },
      ),
    );
    final decoded = _decodeJson(response.data);
    if (decoded == null || '${decoded['status']}' != '1') {
      throw Exception('酷狗账号接口没有返回歌单${_kgWhy(decoded ?? const {})}');
    }
    final data = decoded['data'];
    final raw = data is Map ? data['info'] : null;
    if (raw is! List) return const [];
    final out = <MyPlaylistSummary>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      // 带 authors 的是收藏的专辑，不算歌单。
      if (entry['authors'] != null) continue;
      final gid = '${entry['list_create_gid'] ?? ''}'.trim().isNotEmpty
          ? '${entry['list_create_gid']}'
          : '${entry['global_collection_id'] ?? ''}';
      if (gid.trim().isEmpty) continue;
      final name = '${entry['name'] ?? ''}'.trim();
      out.add(
        MyPlaylistSummary(
          id: gid,
          name: name == '我喜欢' ? '我喜欢的音乐' : (name.isEmpty ? '酷狗歌单' : name),
          cover: '${entry['pic'] ?? ''}',
          trackCount: int.tryParse('${entry['count'] ?? 0}') ?? 0,
          isFavorites: name == '我喜欢',
        ),
      );
    }
    out.sort((a, b) {
      if (a.isFavorites == b.isFavorites) return 0;
      return a.isFavorites ? -1 : 1;
    });
    return out;
  }

  Future<String> _kgNickname(LinkedPlatformAccount account) async {
    try {
      final token = account.credential('token') ?? '';
      final mid = account.extra['mid'] ?? _kgMid;
      final params = <String, String>{
        'dfid': '-',
        'mid': mid,
        'uuid': '-',
        'appid': '$_kgAppId',
        'clientver': '$_kgClientVer',
        'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'token': token,
        'userid': account.userId,
      };
      final body = jsonEncode({'userid': int.tryParse(account.userId) ?? 0});
      params['signature'] = kugouSign(
        'OIlwieks28dk2k092lksi2UIkp',
        params,
        body,
      );
      final response = await _dio.post<String>(
        'https://gateway.kugou.com/v1/get_user_info',
        queryParameters: params,
        data: body,
        options: Options(
          headers: {
            'User-Agent':
                'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi',
            'dfid': '-',
            'mid': mid,
            'clienttime': params['clienttime'],
            'Content-Type': 'application/json',
          },
        ),
      );
      final decoded = _decodeJson(response.data);
      final data = decoded?['data'];
      if (data is Map) {
        return '${data['nickname'] ?? data['nick_name'] ?? ''}'.trim();
      }
    } catch (_) {
      // 昵称不是必需信息。
    }
    return '';
  }

  Future<Map<String, dynamic>> _kgGet(
    String url,
    Map<String, String> params,
  ) async {
    final response = await _dio.get<String>(
      url,
      queryParameters: params,
      options: Options(
        headers: {
          'User-Agent': _desktopUa,
          'Referer': 'https://www.kugou.com/',
        },
      ),
    );
    return _decodeJson(response.data) ?? const {};
  }

  static String _kgWhy(Map body) {
    final code = body['error_code'] ?? body['errcode'] ?? body['err_code'];
    final msg = '${body['error_msg'] ?? body['error'] ?? body['msg'] ?? ''}'
        .trim();
    final parts = [
      if (code != null && '$code' != '0') '错误码 $code',
      if (msg.isNotEmpty) msg,
    ];
    return parts.isEmpty ? '' : '（${parts.join('，')}）';
  }

  // ── 酷我 ───────────────────────────────────────────────

  /// 取一张微信扫码票。
  ///
  /// 酷我没有自家 App 的扫码接口，网页版的「扫码登录」用的是微信开放
  /// 平台网站应用：扫码页本身返回一个 uuid，二维码图片直接由
  /// `open.weixin.qq.com/connect/qrcode/<uuid>` 下发，长轮询也在微信侧。
  /// 这三步都不需要登录，只要 appid 与 redirect 与网页版一致。
  Future<PlatformQrTicket> _createKwQr() async {
    _kwJar.clear();
    final redirect = Uri.encodeComponent(_kwWxCallback);
    final page = Uri.parse(_kwWxQrPage).replace(
      queryParameters: {
        'appid': _kwWxAppId,
        'response_type': 'code',
        'scope': 'snsapi_login',
        'redirect_uri': redirect,
      },
    );
    final response = await _dio.get<String>(
      page.toString(),
      options: Options(
        headers: {'User-Agent': _desktopUa, 'Referer': 'https://www.kuwo.cn/'},
      ),
    );
    _absorbCookies(response.headers, page, _kwJar);
    final html = response.data ?? '';
    final uuid = _kwWxUuidOf(html);
    if (uuid.isEmpty) {
      throw Exception('微信没有返回登录二维码，请稍后重试');
    }
    final image = await _kwWxQrImage(uuid);
    return PlatformQrTicket(
      source: 'kw',
      key: uuid,
      appName: '微信',
      // 二维码用微信下发的 JPEG，本地不再重绘：这枚码里的 url 带 uuid，
      // 自己画的二维码与网页版可能不一致。
      image: image,
    );
  }

  /// 微信的二维码图片接口，返回 JPEG 字节。
  Future<Uint8List> _kwWxQrImage(String uuid) async {
    final response = await _dio.get<List<int>>(
      'https://open.weixin.qq.com/connect/qrcode/$uuid',
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent': _desktopUa,
          'Referer': 'https://open.weixin.qq.com/',
        },
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('微信二维码图片下载失败，请重新获取');
    }
    return Uint8List.fromList(bytes);
  }

  Future<PlatformQrPoll> _pollKwQr(PlatformQrTicket ticket) async {
    final pollUri = Uri.parse(
      _kwWxLongPoll,
    ).replace(queryParameters: {'f': 'json', 'uuid': ticket.key});
    final response = await _dio.get<String>(
      pollUri.toString(),
      options: Options(
        headers: {
          'User-Agent': _desktopUa,
          'Referer': 'https://open.weixin.qq.com/',
        },
      ),
    );
    final body = _decodeJson(response.data) ?? const {};
    final code = '${body['wx_errcode'] ?? ''}'.trim();
    final wxCode = '${body['wx_code'] ?? ''}'.trim();
    switch (code) {
      case '408':
        return const PlatformQrPoll(PlatformQrState.waiting);
      case '404':
        return const PlatformQrPoll(PlatformQrState.scanned);
      case '402':
        return const PlatformQrPoll(PlatformQrState.expired);
      case '405':
        if (wxCode.isEmpty) {
          throw Exception('微信没有返回授权码，请重新扫码');
        }
        final account = await _kwExchange(wxCode);
        return PlatformQrPoll(PlatformQrState.confirmed, account);
      case '403':
        throw Exception('已取消微信授权');
      default:
        // 其余未知码按等待处理，避免一次抖动就判死整张码。
        return const PlatformQrPoll(PlatformQrState.waiting);
    }
  }

  /// 用微信授权码走一遍酷我网页版的回调链，把登录 Cookie 换到本地。
  ///
  /// 链路是 `WeixinCallback.jsp?code=…` → `login_by_weixin_web?code=…` →
  /// `www.kuwo.cn/callback?res=…`。三段必须共用同一个 jar：中转页会先发
  /// JSESSIONID，最后一段才把 `kw_token` / `userid` 写进来。
  Future<LinkedPlatformAccount> _kwExchange(String code) async {
    final encoded = Uri.encodeComponent(code);
    var current = Uri.parse(
      'https://i.kuwo.cn/US/platform/WeixinCallback.jsp'
      '?f=web&code=$encoded&callbackUrl=${Uri.encodeComponent('https://www.kuwo.cn/callback')}',
    );
    for (var hop = 0; hop < 6; hop++) {
      final response = await _dio.get<String>(
        current.toString(),
        options: Options(
          followRedirects: false,
          headers: {
            'User-Agent': _desktopUa,
            'Referer': 'https://open.weixin.qq.com/',
            'Cookie': _kwCookiesFor(current),
          },
        ),
      );
      _absorbCookies(response.headers, current, _kwJar);
      final token = _kwJarValue('kw_token');
      final userId = _kwJarValue('userid');
      if (token != null &&
          token.isNotEmpty &&
          userId != null &&
          userId.isNotEmpty) {
        break;
      }
      final location = response.headers.value('location');
      final status = response.statusCode ?? 0;
      if (status < 300 ||
          status >= 400 ||
          location == null ||
          location.isEmpty) {
        break;
      }
      current = _kwTrustedUri(current.resolve(location));
    }
    final token = _kwJarValue('kw_token') ?? '';
    final userId = _kwJarValue('userid') ?? '';
    if (token.isEmpty || userId.isEmpty) {
      // 酷我网页最近把登录态放在了最后一段的 200 响应里，若没拿到就明确
      // 报错，让用户退回粘贴 Cookie，而不是把半截 Cookie 存下来。
      throw Exception('没有换到酷我登录凭据，请在酷我网页版登录后改用 Cookie 登录');
    }
    final credentials = <String, String>{
      'kw_token': token,
      'userid': userId,
      if ((_kwJarValue('kw_id') ?? '').isNotEmpty)
        'kw_id': _kwJarValue('kw_id')!,
    };
    var account = LinkedPlatformAccount(
      source: 'kw',
      userId: userId,
      nickname: '酷我账号',
      credentials: credentials,
    );
    final profile = await _kwProfile(account);
    if (profile != null) {
      account = account.copyWith(
        nickname: '${profile['nickname'] ?? profile['name'] ?? ''}'.trim(),
        avatar: '${profile['pic'] ?? profile['avatar'] ?? ''}'.trim(),
      );
    }
    await _store.write(account);
    return account;
  }

  /// 从微信扫码页里取 uuid。页面把 uuid 同时写进脚本变量与若干链接，
  /// 取第一个非空即可。
  static String _kwWxUuidOf(String html) {
    final match = RegExp(r'uuid=([A-Za-z0-9_\-]{8,})').firstMatch(html);
    if (match != null) return match.group(1) ?? '';
    final alt = RegExp(
      r'/connect/qrcode/([A-Za-z0-9_\-]{8,})',
    ).firstMatch(html);
    return alt?.group(1) ?? '';
  }

  /// 读取账号资料，失败返回 null（昵称头像不是必需信息）。
  Future<Map<String, dynamic>?> _kwProfile(
    LinkedPlatformAccount account,
  ) async {
    try {
      final response = await _dio.get<String>(
        'https://www.kuwo.cn/api/www/user/userInfo',
        queryParameters: const {'httpsStatus': '1'},
        options: Options(
          headers: {
            'User-Agent': _desktopUa,
            'Referer': 'https://www.kuwo.cn/',
            'csrf': account.credential('kw_token') ?? '',
            'Cookie': account.cookieHeader,
          },
        ),
      );
      final body = _decodeJson(response.data);
      final data = body?['data'];
      return data is Map ? data.map((k, v) => MapEntry('$k', v)) : null;
    } catch (_) {
      return null;
    }
  }

  /// 账号歌单：网页版歌单接口。扫码与 Cookie 两条路径都走它，
  /// 取不到就返回空列表，界面提示改用链接导入。
  Future<List<MyPlaylistSummary>> _kwPlaylists(
    LinkedPlatformAccount account,
  ) async {
    final uid = account.userId;
    if (uid.isEmpty) return const [];
    final response = await _dio.get<String>(
      'https://nplserver.kuwo.cn/pl.svc',
      queryParameters: {
        'op': 'userplist',
        'uid': uid,
        'pn': 0,
        'rn': 200,
        'encode': 'utf8',
        'keyset': 'pl2012',
        'identity': 'kuwo',
        'pcmp4': 1,
        'vipver': 'MUSIC_9.0.5.0_W1',
        'newver': 1,
      },
      options: Options(
        headers: {'User-Agent': _desktopUa, 'Cookie': account.cookieHeader},
      ),
    );
    final body = _decodeJson(response.data);
    final raw = body?['list'] ?? body?['musiclist'];
    if (raw is! List) return const [];
    final out = <MyPlaylistSummary>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['id'] ?? entry['pid'] ?? ''}';
      if (id.isEmpty) continue;
      out.add(
        MyPlaylistSummary(
          id: id,
          name: '${entry['name'] ?? entry['title'] ?? '酷我歌单 $id'}'.trim(),
          cover: '${entry['pic'] ?? ''}',
          trackCount:
              int.tryParse('${entry['count'] ?? entry['songnum'] ?? 0}') ?? 0,
        ),
      );
    }
    return out;
  }

  // ── 通用工具 ───────────────────────────────────────────

  static Map<String, dynamic>? _decodeJson(Object? data) {
    dynamic body = data;
    if (body is String) {
      final text = body.trim();
      if (text.isEmpty) return null;
      try {
        body = jsonDecode(text);
      } catch (_) {
        return null;
      }
    }
    if (body is Map) {
      return body.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  static Map<String, String> _parseCookieString(String raw) {
    final out = <String, String>{};
    for (final part in raw.split(RegExp(r'[;\n]'))) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final name = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      if (name.toLowerCase().startsWith('path') ||
          name.toLowerCase().startsWith('domain') ||
          name.toLowerCase().startsWith('expires') ||
          name.toLowerCase() == 'max-age' ||
          name.toLowerCase() == 'samesite' ||
          name.toLowerCase() == 'httponly' ||
          name.toLowerCase() == 'secure') {
        continue;
      }
      out[name] = value;
    }
    return out;
  }

  /// 收下响应头里的 Set-Cookie，按域名存进 [jar]。
  static void _absorbCookies(
    Headers headers,
    Uri from,
    Map<String, String> jar,
  ) {
    final raw = headers['set-cookie'] ?? const <String>[];
    for (final header in raw) {
      // 一条 header 里可能有多个 Cookie，按「逗号后面紧跟 name=」切分。
      final parts = header.split(RegExp(r',(?=\s*[^;,=\s]+\s*=)'));
      for (final part in parts) {
        final segments = part.split(';');
        if (segments.isEmpty) continue;
        final pair = segments.first;
        final index = pair.indexOf('=');
        if (index <= 0) continue;
        final name = pair.substring(0, index).trim();
        final value = pair.substring(index + 1).trim();
        if (name.isEmpty) continue;
        var domain = from.host.toLowerCase();
        for (final attr in segments.skip(1)) {
          final text = attr.trim();
          if (text.toLowerCase().startsWith('domain=')) {
            domain = text
                .substring(7)
                .trim()
                .replaceFirst(RegExp(r'^\.'), '')
                .toLowerCase();
          }
        }
        final key = '$domain|$name';
        if (value.isEmpty || value == 'deleted') {
          jar.remove(key);
        } else {
          jar[key] = value;
        }
      }
    }
  }

  String _qqCookiesFor(Uri to) {
    final host = to.host.toLowerCase();
    return _qqJar.entries
        .where((entry) {
          final domain = entry.key.substring(0, entry.key.indexOf('|'));
          return host == domain || host.endsWith('.$domain');
        })
        .map(
          (entry) =>
              '${entry.key.substring(entry.key.indexOf('|') + 1)}=${entry.value}',
        )
        .join('; ');
  }

  String _qqAllCookies() => _qqJar.entries
      .map(
        (entry) =>
            '${entry.key.substring(entry.key.indexOf('|') + 1)}=${entry.value}',
      )
      .join('; ');

  String? _qqJarValue(String name) {
    for (final entry in _qqJar.entries) {
      if (entry.key.endsWith('|$name')) return entry.value;
    }
    return null;
  }

  /// 拼给 [to] 的 Cookie 头：只带上域名匹配的项，避免把 i.kuwo.cn 的
  /// JSESSIONID 发给 www.kuwo.cn（反过来也一样）。
  String _kwCookiesFor(Uri to) {
    final host = to.host.toLowerCase();
    return _kwJar.entries
        .where((entry) {
          final domain = entry.key.substring(0, entry.key.indexOf('|'));
          return host == domain || host.endsWith('.$domain');
        })
        .map(
          (entry) =>
              '${entry.key.substring(entry.key.indexOf('|') + 1)}=${entry.value}',
        )
        .join('; ');
  }

  String? _kwJarValue(String name) {
    for (final entry in _kwJar.entries) {
      if (entry.key.endsWith('|$name')) return entry.value;
    }
    return null;
  }

  /// 酷我的回调链只允许在 kuwo.cn 与 open.weixin.qq.com 之间跳转，
  /// 避免服务端被篡改时把 Cookie 带去别处。
  static Uri _kwTrustedUri(Uri uri) {
    final host = uri.host.toLowerCase();
    final trusted =
        host == 'kuwo.cn' ||
        host.endsWith('.kuwo.cn') ||
        host == 'open.weixin.qq.com' ||
        host == 'long.open.weixin.qq.com';
    if (!trusted || uri.userInfo.isNotEmpty) {
      throw const FormatException('登录失败：授权跳转地址不属于可信的酷我服务器');
    }
    // 中转页给的是 http，酷我已经全站 https，统一升上去省一次跳转。
    return uri.replace(scheme: 'https', port: 443);
  }

  static String _qqCookieHeader(String uin, String key) =>
      'uin=$uin; qqmusic_uin=$uin; qqmusic_key=$key; qm_keyst=$key; tmeLoginType=2';

  static Uri _qqTrustedUri(Uri? uri) {
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        (uri.host != 'qq.com' && !uri.host.endsWith('.qq.com')) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('登录失败：授权跳转地址不属于可信的 QQ 服务器');
    }
    return uri.replace(scheme: 'https', port: 443);
  }

  /// ptlogin 与 QQ 互联使用的 hash33 / g_tk 算法。
  static int _hash33(String value, [int seed = 0]) {
    var hash = seed;
    for (final unit in value.codeUnits) {
      hash += (hash << 5) + unit;
    }
    return hash & 0x7fffffff;
  }

  static String _randomUuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
