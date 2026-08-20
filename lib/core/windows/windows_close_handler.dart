import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _WindowsCloseAction { tray, exit }

class WindowsCloseHandler extends StatefulWidget {
  const WindowsCloseHandler({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<WindowsCloseHandler> createState() => _WindowsCloseHandlerState();
}

class _WindowsCloseHandlerState extends State<WindowsCloseHandler> {
  static const _channel = MethodChannel('koyze/window');
  static const _preferenceKey = 'windows_close_action';
  bool _handlingClose = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _channel.setMethodCallHandler(_handleNativeCall);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'closeRequested' || _handlingClose) return;
    _handlingClose = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_preferenceKey);
      final savedAction = _WindowsCloseAction.values
          .where((action) => action.name == saved)
          .firstOrNull;
      if (savedAction != null) {
        await _performWithFallback(savedAction, preferences, remembered: true);
        return;
      }
      final dialogContext = widget.navigatorKey.currentContext;
      if (!mounted || dialogContext == null || !dialogContext.mounted) return;
      final selection = await showDialog<_CloseSelection>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (context) => const _WindowsCloseDialog(),
      );
      if (selection == null) return;
      if (selection.remember) {
        await preferences.setString(_preferenceKey, selection.action.name);
      }
      await _performWithFallback(
        selection.action,
        preferences,
        remembered: selection.remember,
      );
    } finally {
      _handlingClose = false;
    }
  }

  Future<void> _perform(_WindowsCloseAction action) {
    return _channel.invokeMethod<void>(
      action == _WindowsCloseAction.tray ? 'hideToTray' : 'exitApplication',
    );
  }

  Future<void> _performWithFallback(
    _WindowsCloseAction action,
    SharedPreferences preferences, {
    required bool remembered,
  }) async {
    try {
      await _perform(action);
    } on PlatformException {
      if (remembered) await preferences.remove(_preferenceKey);
      final dialogContext = widget.navigatorKey.currentContext;
      if (!mounted || dialogContext == null || !dialogContext.mounted) return;
      await showDialog<void>(
        context: dialogContext,
        builder: (context) => AlertDialog(
          title: const Text('无法最小化到托盘'),
          content: const Text('系统托盘暂时不可用，Koyze 将保持打开。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _CloseSelection {
  const _CloseSelection(this.action, this.remember);

  final _WindowsCloseAction action;
  final bool remember;
}

class _WindowsCloseDialog extends StatefulWidget {
  const _WindowsCloseDialog();

  @override
  State<_WindowsCloseDialog> createState() => _WindowsCloseDialogState();
}

class _WindowsCloseDialogState extends State<_WindowsCloseDialog> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.music_note_rounded, color: colors.primary, size: 30),
      title: const Text('关闭 Koyze？'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('你可以让音乐继续在后台播放，或完全退出应用。'),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _remember,
              onChanged: (value) => setState(() => _remember = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('下次不再询问'),
              dense: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _CloseSelection(_WindowsCloseAction.exit, _remember),
          ),
          icon: const Icon(Icons.power_settings_new_rounded),
          label: const Text('退出'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _CloseSelection(_WindowsCloseAction.tray, _remember),
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          label: const Text('最小化到托盘'),
        ),
      ],
    );
  }
}
