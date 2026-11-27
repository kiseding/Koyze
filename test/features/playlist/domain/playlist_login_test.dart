import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/features/playlist/domain/playlist_login.dart';
import 'package:koyze/features/playlist/domain/playlist_login_service.dart';

/// 内存版安全存储：登录凭据的持久化只关心序列化，不需要真的碰钥匙串。
class _MemoryTokenStore implements SecureTokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  group('LinkedPlatformAccount', () {
    test('Cookie 头按 k=v 拼接，跳过空值', () {
      const account = LinkedPlatformAccount(
        source: 'wy',
        userId: '42',
        nickname: '听歌的人',
        credentials: {'MUSIC_U': 'abc', 'os': 'pc', 'empty': '', 'none': ''},
      );

      expect(account.cookieHeader, 'MUSIC_U=abc; os=pc');
    });

    test('credential 只返回非空值，取不到时是 null', () {
      const account = LinkedPlatformAccount(
        source: 'tx',
        userId: '100',
        nickname: '',
        credentials: {'qm_keyst': 'Q_H_L_x', 'p_skey': ''},
      );

      expect(account.credential('qm_keyst'), 'Q_H_L_x');
      expect(account.credential('p_skey'), isNull);
      expect(account.credential('missing'), isNull);
    });

    test('toJson / fromJson 往返保留凭据与附加信息', () {
      const account = LinkedPlatformAccount(
        source: 'kg',
        userId: '777',
        nickname: '酷狗用户',
        avatar: 'https://img.example/a.jpg',
        credentials: {'token': 't', 'userid': '777'},
        extra: {'t1': 'x'},
      );

      final restored = LinkedPlatformAccount.fromJson(account.toJson());

      expect(restored, isNotNull);
      expect(restored!.source, 'kg');
      expect(restored.userId, '777');
      expect(restored.nickname, '酷狗用户');
      expect(restored.avatar, 'https://img.example/a.jpg');
      expect(restored.credentials, {'token': 't', 'userid': '777'});
      expect(restored.extra, {'t1': 'x'});
    });

    test('fromJson 缺 source 时返回 null，非字符串值统一转成字符串', () {
      expect(LinkedPlatformAccount.fromJson(const {}), isNull);
      expect(LinkedPlatformAccount.fromJson(const {'source': ''}), isNull);

      final restored = LinkedPlatformAccount.fromJson(const {
        'source': 'wy',
        'userId': 12345,
        'nickname': null,
        'credentials': {'MUSIC_U': 999},
      });

      expect(restored, isNotNull);
      expect(restored!.userId, '12345');
      expect(restored.nickname, '');
      expect(restored.credentials, {'MUSIC_U': '999'});
    });

    test('copyWith 沿用 source，只替换传入的字段', () {
      const account = LinkedPlatformAccount(
        source: 'kw',
        userId: '1',
        nickname: '旧昵称',
        avatar: 'a',
      );

      final updated = account.copyWith(nickname: '新昵称');

      expect(updated.source, 'kw');
      expect(updated.nickname, '新昵称');
      expect(updated.avatar, 'a');
      expect(updated.userId, '1');
    });
  });

  group('PlaylistAccountStore', () {
    test('按平台分别存凭据，互不覆盖', () async {
      final tokens = _MemoryTokenStore();
      final store = PlaylistAccountStore(tokenStore: tokens);

      await store.write(
        const LinkedPlatformAccount(
          source: 'wy',
          userId: '1',
          nickname: '网易云',
          credentials: {'MUSIC_U': 'w'},
        ),
      );
      await store.write(
        const LinkedPlatformAccount(
          source: 'tx',
          userId: '2',
          nickname: 'QQ',
          credentials: {'qm_keyst': 'q'},
        ),
      );

      expect(await store.read('wy'), isNotNull);
      expect((await store.read('wy'))!.credentials, {'MUSIC_U': 'w'});
      expect((await store.read('tx'))!.credentials, {'qm_keyst': 'q'});
      expect(
        tokens.values.keys,
        containsAll(['playlist_account_wy', 'playlist_account_tx']),
      );
    });

    test('凭据损坏时当作未登录，不抛异常', () async {
      final tokens = _MemoryTokenStore();
      final store = PlaylistAccountStore(tokenStore: tokens);

      tokens.values['playlist_account_kg'] = 'not-json{';

      expect(await store.read('kg'), isNull);
    });

    test('未写入过的平台返回 null', () async {
      final store = PlaylistAccountStore(tokenStore: _MemoryTokenStore());

      expect(await store.read('kw'), isNull);
    });

    test('clear 只清掉指定平台', () async {
      final tokens = _MemoryTokenStore();
      final store = PlaylistAccountStore(tokenStore: tokens);

      await store.write(
        const LinkedPlatformAccount(source: 'wy', userId: '1', nickname: 'a'),
      );
      await store.write(
        const LinkedPlatformAccount(source: 'tx', userId: '2', nickname: 'b'),
      );
      await store.clear('wy');

      expect(await store.read('wy'), isNull);
      expect(await store.read('tx'), isNotNull);
    });
  });

  test('只有网易云、QQ、酷狗支持扫码，酷我走 Cookie', () {
    expect(PlaylistLoginService.supportsQr('wy'), isTrue);
    expect(PlaylistLoginService.supportsQr('tx'), isTrue);
    expect(PlaylistLoginService.supportsQr('kg'), isTrue);
    expect(PlaylistLoginService.supportsQr('kw'), isFalse);
    expect(PlaylistLoginService.supportsQr('unknown'), isFalse);
  });

  test('PlatformQrTicket 支持图片码与内容码两种形态', () {
    const contentTicket = PlatformQrTicket(
      source: 'wy',
      key: 'unikey',
      appName: '网易云音乐',
      content: 'https://music.163.com/login?codekey=unikey',
    );

    expect(contentTicket.image, isNull);
    expect(contentTicket.content, isNotEmpty);
    expect(contentTicket.appName, '网易云音乐');
  });
}
