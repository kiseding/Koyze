import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/storage/secure_token_store.dart';
import 'package:koyze/features/playlist/domain/playlist_login.dart';
import 'package:koyze/features/playlist/domain/playlist_login_service.dart';

/// 按顺序回放响应，并记下每次请求的 URL 与头。
///
/// 酷我的扫码登录是「一个请求接一个请求」的状态机：取码 → 轮询 → 回调链，
/// 每一步都依赖上一步的结果，所以测试要能断言请求顺序，而不只是最终值。
class _StepAdapter implements HttpClientAdapter {
  _StepAdapter(this.steps);

  final List<_Step> steps;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final index = requests.length - 1;
    if (index >= steps.length) {
      throw StateError('第 ${index + 1} 个请求没有准备响应：${options.uri}');
    }
    final step = steps[index];
    return ResponseBody.fromBytes(
      step.bytes ?? Uint8List.fromList(utf8.encode(step.body)),
      step.status,
      headers: {
        if (step.location != null) 'location': [step.location!],
        if (step.cookies.isNotEmpty) 'set-cookie': step.cookies,
        Headers.contentTypeHeader: [
          step.json ? Headers.jsonContentType : 'text/html; charset=utf-8',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Step {
  _Step({
    this.body = '',
    this.bytes,
    this.status = 200,
    this.location,
    this.cookies = const [],
    this.json = false,
  });

  final String body;
  final List<int>? bytes;
  final int status;
  final String? location;
  final List<String> cookies;
  final bool json;
}

/// 内存版安全存储：只看序列化结果，不碰系统钥匙串。
class _MemoryTokenStore implements SecureTokenStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _kwQrHtml =
    '<script>var uuid=051NxDhA2PdUkl2B;'
    'window.QRLogin.uuid = "051NxDhA2PdUkl2B";</script>';

PlaylistLoginService _serviceWith(
  _StepAdapter adapter, {
  _MemoryTokenStore? store,
}) {
  final dio = Dio()
    ..httpClientAdapter = adapter
    // 生产环境的 dio 由 AppHttpClient 建，validateStatus 放行 5xx 以下的一
    // 切状态码——回调链正是靠 302 的 Location 往下走，测试要还原这一点。
    ..options = BaseOptions(
      validateStatus: (status) => status != null && status < 500,
    );
  return PlaylistLoginService(
    dio: dio,
    store: PlaylistAccountStore(tokenStore: store ?? _MemoryTokenStore()),
  );
}

const _ticket = PlatformQrTicket(source: 'kw', key: 'uuid', appName: '微信');

void main() {
  group('酷我微信扫码登录', () {
    test('取码：走网页版同款 appid，并下载微信二维码图片', () async {
      final adapter = _StepAdapter([
        _Step(body: _kwQrHtml),
        _Step(bytes: List<int>.filled(64, 7)),
      ]);
      final ticket = await _serviceWith(adapter).createQr('kw');

      expect(ticket.source, 'kw');
      expect(ticket.key, '051NxDhA2PdUkl2B');
      expect(ticket.appName, '微信');
      // 图片码优先于本地重绘，避免自己画的码与网页版不一致。
      expect(ticket.image, isNotNull);
      expect(ticket.image!.length, 64);

      final qrRequest = adapter.requests.first;
      expect(qrRequest.uri.path, contains('qrconnect'));
      expect(
        qrRequest.uri.queryParameters['appid'],
        'wx41c1275bb3e28427',
        reason: 'appid 必须与酷我网页版一致，否则扫码后回调不到酷我',
      );
      expect(
        qrRequest.uri.queryParameters['redirect_uri'],
        contains('kuwo.cn'),
      );
      expect(
        adapter.requests[1].uri.toString(),
        contains('/connect/qrcode/051NxDhA2PdUkl2B'),
      );
    });

    test('轮询把微信状态码映射成四种界面状态', () async {
      Future<PlatformQrPoll> pollWith(String code) async {
        final adapter = _StepAdapter([
          _Step(json: true, body: '{"wx_errcode":$code,"wx_code":""}'),
        ]);
        return _serviceWith(adapter).poll('kw', _ticket);
      }

      expect((await pollWith('408')).state, PlatformQrState.waiting);
      expect((await pollWith('404')).state, PlatformQrState.scanned);
      expect((await pollWith('402')).state, PlatformQrState.expired);
      await expectLater(pollWith('403'), throwsA(isA<Exception>()));
    });

    test('确认后走酷我回调链，把 kw_token 与 userid 换成本地凭据', () async {
      final adapter = _StepAdapter([
        // 轮询：405 表示手机上已确认，带回微信授权码。
        _Step(json: true, body: '{"wx_errcode":405,"wx_code":"CODE1"}'),
        // 中转页：先给 JSESSIONID，再 302 到真正的兑换页。
        _Step(
          status: 302,
          location:
              'http://i.kuwo.cn/US_NEW/kuwo/login_by_weixin_web?code=CODE1',
          cookies: ['JSESSIONID=abc.tomcat1; Path=/US_NEW/; HttpOnly'],
        ),
        // 兑换页：302 到网页回调，并下发登录凭据。
        _Step(
          status: 302,
          location: 'http://www.kuwo.cn/callback?res=TICKET&param=',
          cookies: ['kw_token=TOKEN1; Path=/', 'userid=9527; Path=/'],
        ),
        // 资料接口：昵称头像不是必需信息，给个正常响应。
        _Step(
          json: true,
          body: '{"success":true,"data":{"nickname":"酷我用户","pic":"a.jpg"}}',
        ),
      ]);
      final store = _MemoryTokenStore();
      final poll = await _serviceWith(
        adapter,
        store: store,
      ).poll('kw', _ticket);

      expect(poll.state, PlatformQrState.confirmed);
      final account = poll.account!;
      expect(account.source, 'kw');
      expect(account.userId, '9527');
      expect(account.nickname, '酷我用户');
      expect(account.credentials['kw_token'], 'TOKEN1');

      // 中转页拿到的 JSESSIONID 必须带回给同一台 i.kuwo.cn 机器，
      // 否则兑换页会当成另一个会话，拿不到凭据。
      expect(adapter.requests[2].headers['Cookie'], contains('JSESSIONID='));
      expect(store.values.keys, contains('playlist_account_kw'));
    });

    test('回调链没换到凭据时报错，不会存下半截 Cookie', () async {
      final adapter = _StepAdapter([
        _Step(json: true, body: '{"wx_errcode":405,"wx_code":"BAD"}'),
        _Step(status: 200, body: '<html></html>'),
      ]);
      final store = _MemoryTokenStore();
      final service = _serviceWith(adapter, store: store);

      await expectLater(service.poll('kw', _ticket), throwsA(isA<Exception>()));
      expect(store.values, isEmpty);
    });
  });
}
