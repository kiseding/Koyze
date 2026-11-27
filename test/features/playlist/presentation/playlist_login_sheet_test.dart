import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「导入歌单 → 登录」这条链路的接线检查。
///
/// 扫码登录涉及四家平台的网络协议，单元测试没法真连；这里守住两件最容易
/// 回归的事：导入弹窗真的把入口接到了登录面板（而不是又退回占位文案），
/// 以及面板本身走的是统一的面板组件与方点二维码。
void main() {
  late String screen;
  late String sheet;

  setUpAll(() {
    screen = File(
      'lib/features/playlist/presentation/playlist_screen.dart',
    ).readAsStringSync();
    sheet = File(
      'lib/features/playlist/presentation/playlist_login_sheet.dart',
    ).readAsStringSync();
  });

  group('导入弹窗的登录页', () {
    test('登录入口接到扫码面板，不再是「暂未接入」的禁用按钮', () {
      expect(screen, contains('showPlaylistLoginSheet('));
      expect(screen, isNot(contains('platformLoginUnavailableAction')));
      expect(screen, isNot(contains('importPlatformLoginIntro')));
      expect(screen, isNot(contains('Icons.lock_outline_rounded')));
    });

    test('面板里点选歌单后用登录凭据拉取曲目', () {
      expect(screen, contains('importAccountPlaylist'));
      expect(screen, contains('importAccountPlaylist'));
      expect(screen, contains('account: linked'));
      expect(screen, contains('summary: summary'));
      // 刚扫码登录时弹窗里的 account 还是 null，必须回读一次安全存储。
      expect(
        screen,
        contains('account ?? await loginService.current(platform)'),
      );
    });

    test('账号状态按平台分次读取，切换平台不会显示上一个平台的账号', () {
      expect(screen, contains('PlaylistLoginService()'));
      expect(screen, contains('accountRequest'));
      expect(screen, contains('accountChecked = false'));
      expect(screen, contains('checkingAccount'));
    });

    test('已登录展示账号摘要，按钮文案随平台能力变化', () {
      expect(screen, contains('_ImportAccountCard('));
      expect(screen, contains('PlaylistLoginService.supportsQr(platform)'));
      expect(screen, contains('playlistLoginCookieAction'));
      expect(screen, contains('playlistLoginMyPlaylists'));
    });

    test('链接导入与账号导入共用同一个确认步骤', () {
      expect(screen, contains('_confirmImport('));
      expect(screen, contains('confirmImport(imported.songs.length)'));
    });

    test('导入成功后只关一次对话框，避免重复 pop 掉歌单页', () {
      expect(screen, contains('importedFromAccount'));
      // 面板在自己收起前不会让外层也 pop，靠这个标记判断。
      expect(screen, contains('if (imported != null) {'));
    });
  });

  group('登录面板', () {
    test('走统一的面板标题，没有抓手', () {
      expect(sheet, contains('KoyzeSheetTitle('));
      expect(sheet, isNot(contains('KoyzeSheetGrabber')));
    });

    test('二维码用方点方框渲染，保证扫码器能识别', () {
      expect(sheet, contains('QrImageView('));
      expect(sheet, contains('QrEyeShape.square'));
      expect(sheet, contains('QrDataModuleShape.square'));
    });

    test('平台直接下发图片码时优先用图片（QQ 的 ptqrshow 返回 PNG）', () {
      expect(sheet, contains('ticket.image != null'));
      expect(sheet, contains('Image.memory('));
    });

    test('轮询按 2 秒一次且串行，确认后拿到账号就停下', () {
      expect(sheet, contains('Timer.periodic(const Duration(seconds: 2)'));
      expect(
        sheet,
        contains('if (busy || !mounted || _poll != timer) return;'),
      );
      expect(sheet, contains('result.state == PlatformQrState.confirmed'));
    });

    test('离开面板会取消轮询并释放平台侧票据', () {
      expect(sheet, contains('_poll?.cancel()'));
      expect(sheet, contains('_service.cancelQr('));
    });

    test('酷我没有扫码，回落到 Cookie 输入', () {
      expect(sheet, contains('!PlaylistLoginService.supportsQr(_source)'));
      expect(sheet, contains('_cookieBody'));
      expect(sheet, contains('playlistLoginCookieAction'));
    });

    test('已登录时列出我的歌单，点一个就回调导入', () {
      expect(sheet, contains('playlistLoginMyPlaylists'));
      expect(sheet, contains('_playlists.map(_playlistRow)'));
      expect(sheet, contains('await widget.onImport(playlist)'));
    });

    test('退出登录后重新取码，不用手动重进面板', () {
      expect(sheet, contains('_service.logout(_source)'));
      expect(
        sheet,
        contains('if (PlaylistLoginService.supportsQr(_source)) {'),
      );
    });
  });
}
