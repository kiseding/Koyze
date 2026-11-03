import 'dart:async';

import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/loading_widget.dart';
import '../domain/plex_client.dart';

class PlexPinResult {
  const PlexPinResult({required this.token, required this.clientId});

  final String token;
  final String clientId;
}

/// Plex 的「用账号登录」：生成登录码后轮询 plex.tv，拿到 token 就返回。
Future<PlexPinResult?> showPlexPinDialog(
  BuildContext context, {
  required PlexNasClient client,
  required String clientId,
}) {
  return showDialog<PlexPinResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PlexPinDialog(client: client, clientId: clientId),
  );
}

class _PlexPinDialog extends StatefulWidget {
  const _PlexPinDialog({required this.client, required this.clientId});

  final PlexNasClient client;
  final String clientId;

  @override
  State<_PlexPinDialog> createState() => _PlexPinDialogState();
}

class _PlexPinDialogState extends State<_PlexPinDialog> {
  static const _pollInterval = Duration(seconds: 2);
  static const _maxAttempts = 150;

  PlexPinSession? _session;
  Timer? _timer;
  String? _error;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _error = null;
      _attempts = 0;
    });
    try {
      final session = await widget.client.createPin(
        clientId: widget.clientId,
      );
      if (!mounted) return;
      setState(() => _session = session);
      _timer = Timer.periodic(_pollInterval, (_) => _poll());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null) return;
    if (_attempts >= _maxAttempts) {
      _timer?.cancel();
      if (mounted) {
        setState(() => _error = S.of(context).connectFailed);
      }
      return;
    }
    _attempts++;
    try {
      final token = await widget.client.fetchPinToken(session);
      if (!mounted) return;
      if (token != null && token.isNotEmpty) {
        _timer?.cancel();
        Navigator.of(context).pop(
          PlexPinResult(token: token, clientId: session.clientId),
        );
      }
    } catch (_) {
      // 网络抖动很常见，下一轮继续轮询就行。
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);
    final session = _session;

    return AlertDialog(
      title: Text(
        S.of(context).plexPinLogin,
        style: TextStyle(color: on, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Text(_error!, style: TextStyle(color: muted, fontSize: 13))
          else if (session == null)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppLoadingIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  S.of(context).loading,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            )
          else ...[
            Text(
              session.code,
              style: TextStyle(
                color: accent,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              S.of(context).plexPinWaiting(session.code),
              style: TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null)
          TextButton(
            onPressed: _start,
            child: Text(S.of(context).retry),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).cancel),
        ),
      ],
    );
  }
}
