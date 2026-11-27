import 'dart:convert';
import 'dart:typed_data';

import '../../../core/storage/secure_token_store.dart';

/// 扫码登录所处的阶段，和平台无关。
///
/// 四家平台的轮询返回码各不相同（网易云 800/801/802/803，QQ 65/66/67/0，
/// 酷狗 0/1/2/4），统一收敛到这里，界面只按这四种状态渲染。
enum PlatformQrState {
  /// 等待扫码。
  waiting,

  /// 已扫码，等待手机上确认。
  scanned,

  /// 二维码过期，需要重新获取。
  expired,

  /// 手机上已确认，凭据已换到手。
  confirmed,
}

/// 一张待扫描的二维码。
///
/// [content] 与 [image] 二选一：[image] 是接口直接返回的图片（QQ 的
/// ptqrshow 就是 PNG），否则用 [content] 在本地渲染二维码。
class PlatformQrTicket {
  const PlatformQrTicket({
    required this.source,
    required this.key,
    required this.appName,
    this.content = '',
    this.image,
  });

  /// 平台标识：tx / wy / kg / kw。
  final String source;

  /// 平台侧的票据标识（网易云 unikey、QQ qrsig、酷狗 qrcode）。
  final String key;

  /// 提示用户用哪个 App 扫码。
  final String appName;

  /// 二维码内容，[image] 为空时用它本地渲染。
  final String content;

  /// 平台直接下发的二维码图片，非空时优先使用。
  final Uint8List? image;
}

/// 已经登录的平台账号。
///
/// [credentials] 只写进系统安全存储，不落 SharedPreferences；它可能是
/// Cookie（网易云 MUSIC_U、QQ p_skey/qm_keyst、酷我网页 Cookie）或令牌
/// （酷狗 token）。
class LinkedPlatformAccount {
  const LinkedPlatformAccount({
    required this.source,
    required this.userId,
    required this.nickname,
    this.avatar = '',
    this.credentials = const {},
    this.extra = const {},
  });

  final String source;
  final String userId;
  final String nickname;
  final String avatar;
  final Map<String, String> credentials;
  final Map<String, String> extra;

  /// 拼成 `k=v; k=v` 的 Cookie 头，网易云与 QQ 的后续请求都用它。
  String get cookieHeader => credentials.entries
      .where((e) => e.key.isNotEmpty && e.value.isNotEmpty)
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  String? credential(String name) {
    final value = credentials[name];
    return value == null || value.isEmpty ? null : value;
  }

  LinkedPlatformAccount copyWith({
    String? userId,
    String? nickname,
    String? avatar,
    Map<String, String>? credentials,
    Map<String, String>? extra,
  }) {
    return LinkedPlatformAccount(
      source: source,
      userId: userId ?? this.userId,
      nickname: nickname ?? this.nickname,
      avatar: avatar ?? this.avatar,
      credentials: credentials ?? this.credentials,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'userId': userId,
    'nickname': nickname,
    'avatar': avatar,
    'credentials': credentials,
    'extra': extra,
  };

  static LinkedPlatformAccount? fromJson(Map<String, dynamic> json) {
    final source = '${json['source'] ?? ''}';
    if (source.isEmpty) return null;
    Map<String, String> strings(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries) '${entry.key}': '${entry.value ?? ''}',
      };
    }

    return LinkedPlatformAccount(
      source: source,
      userId: '${json['userId'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      credentials: strings(json['credentials']),
      extra: strings(json['extra']),
    );
  }
}

/// 账号下的一个歌单，只保留「我的歌单」列表需要的字段。
class MyPlaylistSummary {
  const MyPlaylistSummary({
    required this.id,
    required this.name,
    this.cover = '',
    this.trackCount = 0,
    this.isFavorites = false,
  });

  final String id;
  final String name;
  final String cover;
  final int trackCount;

  /// 「我喜欢的音乐」这类默认收藏歌单，列表里排在最前。
  final bool isFavorites;
}

/// 扫码轮询的一次结果：状态 + 确认后换到的账号。
class PlatformQrPoll {
  const PlatformQrPoll(this.state, [this.account]);

  final PlatformQrState state;

  /// 只有 [state] 为 confirmed 时非空。
  final LinkedPlatformAccount? account;
}

/// 平台账号凭据的持久化。
///
/// Cookie/令牌相当于密码，统一走系统安全存储（Android Keystore、iOS
/// Keychain、Windows DPAPI 等），不写进普通偏好设置。
class PlaylistAccountStore {
  PlaylistAccountStore({SecureTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? FlutterSecureTokenStore();

  final SecureTokenStore _tokenStore;

  static String _keyOf(String source) => 'playlist_account_$source';

  Future<LinkedPlatformAccount?> read(String source) async {
    try {
      final raw = await _tokenStore.read(_keyOf(source));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return LinkedPlatformAccount.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      // 凭据损坏时当作未登录，避免整个导入面板打不开。
      return null;
    }
  }

  Future<void> write(LinkedPlatformAccount account) =>
      _tokenStore.write(_keyOf(account.source), jsonEncode(account.toJson()));

  Future<void> clear(String source) => _tokenStore.delete(_keyOf(source));
}
