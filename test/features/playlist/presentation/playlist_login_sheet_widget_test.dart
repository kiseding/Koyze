import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/features/playlist/domain/playlist_login.dart';
import 'package:koyze/features/playlist/domain/playlist_login_service.dart';
import 'package:koyze/features/playlist/presentation/playlist_login_sheet.dart';
import 'package:koyze/l10n/generated/app_localizations.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 登录面板只依赖服务的四个动作，测试里换成固定回答即可，
/// 不必真去扫一次码。
class _FakeService extends PlaylistLoginService {
  _FakeService({
    this.account,
    this.playlists = const [],
    this.ticket,
    this.pollResult = const PlatformQrPoll(PlatformQrState.waiting),
  }) : super(store: _NoopStore());

  LinkedPlatformAccount? account;
  final List<MyPlaylistSummary> playlists;
  final PlatformQrTicket? ticket;
  PlatformQrPoll pollResult;

  int qrRequests = 0;
  int pollCalls = 0;
  int cancelled = 0;
  int loggedOut = 0;

  @override
  Future<LinkedPlatformAccount?> current(String source) async => account;

  @override
  Future<List<MyPlaylistSummary>> myPlaylists(
    LinkedPlatformAccount account,
  ) async => playlists;

  @override
  Future<PlatformQrTicket> createQr(String source) async {
    qrRequests++;
    return ticket!;
  }

  @override
  Future<PlatformQrPoll> poll(String source, PlatformQrTicket ticket) async {
    pollCalls++;
    return pollResult;
  }

  @override
  Future<void> cancelQr(String source) async {
    cancelled++;
  }

  @override
  Future<void> logout(String source) async {
    loggedOut++;
    account = null;
  }
}

class _NoopStore implements PlaylistAccountStore {
  @override
  Future<LinkedPlatformAccount?> read(String source) async => null;

  @override
  Future<void> write(LinkedPlatformAccount account) async {}

  @override
  Future<void> clear(String source) async {}
}

const _qrTicket = PlatformQrTicket(
  source: 'wy',
  key: 'unikey-1',
  appName: '网易云音乐',
  content: 'https://music.163.com/login?codekey=unikey-1',
);

/// 1x1 的透明 PNG：QQ 的 ptqrshow 直接下发图片，这里只验证走的是
/// Image.memory 而不是本地画码，给个能解码的最小图即可。
final _qqImageTicket = PlatformQrTicket(
  source: 'tx',
  key: 'qrsig-1',
  appName: 'QQ 音乐',
  image: Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
      'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  ),
);

Future<void> _openSheet(
  WidgetTester tester,
  _FakeService service, {
  String source = 'wy',
  Future<bool> Function(MyPlaylistSummary playlist)? onImport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showPlaylistLoginSheet(
                context,
                source: source,
                service: service,
                onImport: onImport ?? (_) async => true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  // 弹层入场的位移与透明度动画走完，但不要 pumpAndSettle：
  // 面板在等待扫码时每 2 秒会重建一次，settle 永远等不到静止。
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('未登录时渲染二维码，并提示用哪个 App 扫码', (tester) async {
    final service = _FakeService(ticket: _qrTicket);
    await _openSheet(tester, service);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('网易云音乐'), findsWidgets);
    expect(service.qrRequests, 1);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('平台给的是图片码时直接用图片，不再本地画', (tester) async {
    final service = _FakeService(ticket: _qqImageTicket);
    await _openSheet(tester, service, source: 'tx');

    expect(find.byType(Image), findsWidgets);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('二维码过期后出现刷新按钮，点一下重新取码', (tester) async {
    final service = _FakeService(
      ticket: _qrTicket,
      pollResult: const PlatformQrPoll(PlatformQrState.expired),
    );
    await _openSheet(tester, service);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    expect(service.qrRequests, 2);
  });

  testWidgets('已登录时列出我的歌单，点一个就触发导入', (tester) async {
    final imported = <String>[];
    final service = _FakeService(
      account: const LinkedPlatformAccount(
        source: 'wy',
        userId: '42',
        nickname: '听歌的人',
      ),
      playlists: const [
        MyPlaylistSummary(id: '1', name: '我喜欢的音乐', isFavorites: true),
        MyPlaylistSummary(id: '2', name: '通勤', trackCount: 12),
      ],
      ticket: _qrTicket,
    );
    await _openSheet(
      tester,
      service,
      onImport: (playlist) async {
        imported.add(playlist.id);
        return true;
      },
    );

    expect(find.text('听歌的人'), findsOneWidget);
    expect(find.text('通勤'), findsOneWidget);
    expect(service.qrRequests, 0);

    await tester.tap(find.text('通勤'));
    await tester.pump();

    expect(imported, ['2']);
  });

  testWidgets('导入失败时留在面板里，可以再点别的歌单', (tester) async {
    final service = _FakeService(
      account: const LinkedPlatformAccount(
        source: 'wy',
        userId: '42',
        nickname: '听歌的人',
      ),
      playlists: const [MyPlaylistSummary(id: '2', name: '通勤')],
    );
    await _openSheet(tester, service, onImport: (_) async => false);

    await tester.tap(find.text('通勤'));
    await tester.pump();

    expect(find.text('通勤'), findsOneWidget);
  });

  testWidgets('退出登录后回到取码状态，并清掉歌单列表', (tester) async {
    final service = _FakeService(
      account: const LinkedPlatformAccount(
        source: 'wy',
        userId: '42',
        nickname: '听歌的人',
      ),
      playlists: const [MyPlaylistSummary(id: '2', name: '通勤')],
      ticket: _qrTicket,
    );
    await _openSheet(tester, service);

    await tester.tap(find.text('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.loggedOut, 1);
    expect(find.text('通勤'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(service.qrRequests, 1);
  });

  testWidgets('酷我没有扫码：给 Cookie 输入框，不画二维码', (tester) async {
    final service = _FakeService(ticket: _qrTicket);
    await _openSheet(tester, service, source: 'kw');

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(service.qrRequests, 0);
  });

  testWidgets('关闭面板会释放平台侧票据', (tester) async {
    final service = _FakeService(ticket: _qrTicket);
    await _openSheet(tester, service);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(service.cancelled, 1);
  });
}
