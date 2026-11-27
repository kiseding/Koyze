import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/artwork_image.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/playlist_login.dart';
import '../domain/playlist_login_service.dart';

/// 打开导入歌单里的「登录」面板。
///
/// 面板自己完成取码、轮询、读歌单，选一个歌单后回调 [onImport]；
/// 回调返回 true 表示导入成功，面板随之关闭。
///
/// [service] 只给测试注入假实现用，正式调用不传。
Future<void> showPlaylistLoginSheet(
  BuildContext context, {
  required String source,
  required Future<bool> Function(MyPlaylistSummary playlist) onImport,
  PlaylistLoginService? service,
}) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _PlaylistLoginSheet(
      source: source,
      onImport: onImport,
      service: service,
    ),
  );
}

class _PlaylistLoginSheet extends StatefulWidget {
  const _PlaylistLoginSheet({
    required this.source,
    required this.onImport,
    this.service,
  });

  final String source;
  final Future<bool> Function(MyPlaylistSummary playlist) onImport;
  final PlaylistLoginService? service;

  @override
  State<_PlaylistLoginSheet> createState() => _PlaylistLoginSheetState();
}

class _PlaylistLoginSheetState extends State<_PlaylistLoginSheet> {
  late final PlaylistLoginService _service =
      widget.service ?? PlaylistLoginService();
  final TextEditingController _cookieCtrl = TextEditingController();

  LinkedPlatformAccount? _account;
  bool _loadingAccount = true;

  PlatformQrTicket? _ticket;
  PlatformQrState _state = PlatformQrState.waiting;
  String? _error;
  Timer? _poll;
  int _failures = 0;
  int _request = 0;

  /// 酷我的扫码依赖网页版的微信回调链，官方随时可能改。这里留一个
  /// 显式开关：扫码失败时用户还能退回粘贴 Cookie，不至于整个入口不可用。
  bool _cookieFallback = false;

  List<MyPlaylistSummary> _playlists = const [];
  bool _loadingPlaylists = false;
  String? _playlistError;

  bool _cookieBusy = false;
  String? _importingId;

  String get _source => widget.source;

  static const Map<String, String> _platformNames = {
    'tx': 'QQ 音乐',
    'wy': '网易云音乐',
    'kg': '酷狗音乐',
    'kw': '酷我音乐',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _request++;
    _service.cancelQr(_source);
    _cookieCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final account = await _service.current(_source);
    if (!mounted) return;
    setState(() {
      _account = account;
      _loadingAccount = false;
    });
    if (account != null) {
      await _loadPlaylists(account);
    } else if (PlaylistLoginService.supportsQr(_source)) {
      await _createQr();
    }
  }

  Future<void> _loadPlaylists(LinkedPlatformAccount account) async {
    setState(() {
      _loadingPlaylists = true;
      _playlistError = null;
    });
    try {
      final list = await _service.myPlaylists(account);
      if (!mounted) return;
      setState(() {
        _playlists = list;
        _loadingPlaylists = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPlaylists = false;
        _playlists = const [];
        _playlistError = _clean(error);
      });
    }
  }

  Future<void> _createQr() async {
    final request = ++_request;
    _poll?.cancel();
    _failures = 0;
    setState(() {
      _ticket = null;
      _error = null;
      _state = PlatformQrState.waiting;
    });
    try {
      final ticket = await _service.createQr(_source);
      if (!mounted || request != _request) return;
      setState(() => _ticket = ticket);
      var busy = false;
      late final Timer timer;
      timer = _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        // 上一次查询还没回来就跳过：确认后要连着换几个接口才拿得到凭据，
        // 重叠的查询会拿同一张码再查一次，反而把一次性授权用掉。
        if (busy || !mounted || _poll != timer) return;
        busy = true;
        try {
          final result = await _service.poll(_source, ticket);
          if (!mounted || _poll != timer) return;
          setState(() => _state = result.state);
          _failures = 0;
          if (result.state == PlatformQrState.confirmed &&
              result.account != null) {
            timer.cancel();
            final account = result.account!;
            setState(() => _account = account);
            await _loadPlaylists(account);
          } else if (result.state == PlatformQrState.expired) {
            timer.cancel();
          }
        } catch (error) {
          if (!mounted || _poll != timer) return;
          // 已扫码之后出错基本是「换凭据」失败，原因要显示出来；
          // 还在等扫码时连续失败三次才判定为错误，避免网络抖动就打断。
          if (_state == PlatformQrState.scanned || ++_failures >= 3) {
            timer.cancel();
            setState(() => _error = _clean(error));
          }
        } finally {
          busy = false;
        }
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _clean(error));
      }
    }
  }

  Future<void> _loginWithCookie() async {
    final text = _cookieCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _cookieBusy = true;
      _error = null;
    });
    try {
      final account = await _service.loginWithCookie(_source, text);
      if (!mounted) return;
      setState(() {
        _account = account;
        _cookieBusy = false;
      });
      _cookieCtrl.clear();
      await _loadPlaylists(account);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cookieBusy = false;
        _error = _clean(error);
      });
    }
  }

  Future<void> _logout() async {
    _poll?.cancel();
    _request++;
    await _service.logout(_source);
    if (!mounted) return;
    setState(() {
      _account = null;
      _playlists = const [];
      _playlistError = null;
      _ticket = null;
      _error = null;
      _state = PlatformQrState.waiting;
    });
    if (PlaylistLoginService.supportsQr(_source)) {
      await _createQr();
    }
  }

  Future<void> _import(MyPlaylistSummary playlist) async {
    if (_importingId != null) return;
    setState(() => _importingId = playlist.id);
    final ok = await widget.onImport(playlist);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _importingId = null);
    }
  }

  static String _clean(Object error) {
    final text = '$error';
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : text;
  }

  String _statusText(S s) {
    if (_error != null) return _error!;
    return switch (_state) {
      PlatformQrState.waiting => s.playlistLoginQrWaiting,
      PlatformQrState.scanned => s.playlistLoginQrScanned,
      PlatformQrState.expired => s.playlistLoginQrExpired,
      PlatformQrState.confirmed => s.loginSucceeded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final name = _platformNames[_source] ?? _source;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KoyzeSheetTitle(
            title: '$name · ${s.login}',
            subtitle: s.playlistLoginIntro,
            onClose: () => Navigator.pop(context),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: _loadingAccount
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ]
                  : _account == null
                  ? _loggedOutBody(s)
                  : _loggedInBody(s, _account!),
            ),
          ),
        ],
      ),
    );
  }

  // ── 未登录 ─────────────────────────────────────────────

  List<Widget> _loggedOutBody(S s) {
    if (_cookieFallback || !PlaylistLoginService.supportsQr(_source)) {
      return _cookieBody(s);
    }
    final ticket = _ticket;
    return [
      Center(
        child: Container(
          width: 220,
          height: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6E6E73),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                )
              : ticket == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Opacity(
                  opacity: _state == PlatformQrState.expired ? 0.22 : 1,
                  child: ticket.image != null
                      ? Image.memory(
                          ticket.image!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          gaplessPlayback: true,
                        )
                      : QrImageView(
                          data: ticket.content,
                          padding: EdgeInsets.zero,
                          // 方形码点与定位框：圆点样式部分扫码器识别不出来。
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        _statusText(s),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _error != null
              ? AppColors.error
              : AppColors.onScaffold(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        s.playlistLoginQrHint(ticket?.appName ?? _platformNames[_source] ?? ''),
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
      ),
      if (_state == PlatformQrState.expired || _error != null) ...[
        const SizedBox(height: 14),
        Center(
          child: FilledButton.icon(
            onPressed: _createQr,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(s.refresh),
          ),
        ),
      ],
      /** 扫码链路失败时的保底入口：酷我的登录凭据最终仍以网页 Cookie 为准。 */
      if (_source == 'kw') ...[
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _cookieFallback = true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.mutedText(context),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(s.playlistLoginCookieAction),
          ),
        ),
      ],
    ];
  }

  List<Widget> _cookieBody(S s) => [
    Text(
      s.playlistLoginCookieIntro,
      style: TextStyle(
        color: AppColors.secondaryText(context),
        fontSize: 13,
        height: 1.5,
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _cookieCtrl,
      minLines: 3,
      maxLines: 5,
      autocorrect: false,
      enabled: !_cookieBusy,
      style: TextStyle(color: AppColors.onScaffold(context), fontSize: 13),
      decoration: InputDecoration(
        hintText: s.playlistLoginCookieField,
        alignLabelWithHint: true,
      ).applyDefaults(Theme.of(context).inputDecorationTheme),
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: _cookieBusy ? null : _loginWithCookie,
      icon: _cookieBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.key_rounded),
      label: Text(s.playlistLoginCookieAction),
    ),
    if (_error != null) ...[
      const SizedBox(height: 10),
      Text(
        _error!,
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
    ],
    if (_source == 'kw' &&
        _cookieFallback &&
        PlaylistLoginService.supportsQr(_source)) ...[
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: () {
            setState(() {
              _cookieFallback = false;
              _error = null;
            });
            _createQr();
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.mutedText(context),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(s.playlistLoginUseQr),
        ),
      ),
    ],
  ];

  // ── 已登录 ─────────────────────────────────────────────

  List<Widget> _loggedInBody(S s, LinkedPlatformAccount account) => [
    Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.fill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder(context)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 38,
              height: 38,
              child: account.avatar.isEmpty
                  ? _avatarFallback()
                  : ArtworkImage(
                      account.avatar,
                      width: 38,
                      height: 38,
                      placeholder: _avatarFallback(),
                      errorBuilder: (_, _, _) => _avatarFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.nickname.isEmpty
                      ? (account.userId.isEmpty ? s.login : account.userId)
                      : account.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.loggedInAs(account.userId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.mutedText(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _logout,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(s.logOut),
          ),
        ],
      ),
    ),
    const SizedBox(height: 16),
    Row(
      children: [
        Expanded(
          child: Text(
            s.playlistLoginMyPlaylists,
            style: TextStyle(
              color: AppColors.secondaryText(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (_loadingPlaylists)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    ),
    const SizedBox(height: 6),
    if (_playlistError != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          _playlistError!,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      )
    else if (!_loadingPlaylists && _playlists.isEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          s.playlistLoginNoPlaylists,
          style: TextStyle(
            color: AppColors.mutedText(context),
            fontSize: 12,
            height: 1.45,
          ),
        ),
      )
    else
      ..._playlists.map(_playlistRow),
  ];

  Widget _avatarFallback() => Container(
    color: AppColors.fill(context),
    alignment: Alignment.center,
    child: Icon(
      Icons.person_rounded,
      size: 20,
      color: AppColors.mutedText(context),
    ),
  );

  Widget _playlistRow(MyPlaylistSummary playlist) {
    final importing = _importingId == playlist.id;
    final busyOther = _importingId != null && !importing;
    return Opacity(
      opacity: busyOther ? 0.5 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busyOther || _importingId != null
              ? null
              : () => _import(playlist),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: playlist.cover.isEmpty
                        ? _avatarFallback()
                        : ArtworkImage(
                            playlist.cover,
                            width: 42,
                            height: 42,
                            placeholder: _avatarFallback(),
                            errorBuilder: (_, _, _) => _avatarFallback(),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 13.5,
                        ),
                      ),
                      if (playlist.trackCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${playlist.trackCount}',
                          style: TextStyle(
                            color: AppColors.mutedText(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.download_rounded,
                        size: 18,
                        color: AppColors.accentOf(context),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
