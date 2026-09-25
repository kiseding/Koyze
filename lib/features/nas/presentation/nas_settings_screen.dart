import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../domain/nas_config.dart';
import '../domain/nas_kind.dart';
import '../domain/nas_url.dart';
import 'nas_provider.dart';

class NasSettingsScreen extends ConsumerStatefulWidget {
  const NasSettingsScreen({super.key, required this.kind});

  final NasKind kind;

  @override
  ConsumerState<NasSettingsScreen> createState() => _NasSettingsScreenState();
}

class _NasSettingsScreenState extends ConsumerState<NasSettingsScreen> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlFocus = FocusNode();
  bool _obscurePassword = true;
  bool _busy = false;
  bool _hydrated = false;

  NasKind get _kind => widget.kind;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _hydrate(NasConfig config) {
    if (_hydrated) return;
    _hydrated = true;
    _urlController.text = config.baseUrl;
    _usernameController.text = config.username;
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    try {
      validateNasServiceUrl(url);
    } catch (error) {
      showAppNotification(
        error is ArgumentError ? error.message ?? '$error' : '$error',
        type: AppNotificationType.error,
      );
      return;
    }
    if (_kind != NasKind.plex && username.isEmpty) {
      showAppNotification(S.of(context).enterUsername, type: AppNotificationType.error);
      return;
    }
    if (password.isEmpty) {
      showAppNotification(
        _kind == NasKind.plex ? S.of(context).enterPasswordOrToken : S.of(context).enterPassword,
        type: AppNotificationType.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(nasServiceProvider(_kind))
          .connect(baseUrl: url, username: username, password: password);
      if (!mounted) return;
      if (result.ok) {
        _passwordController.clear();
        final type = result.serverType ?? _kind.title;
        final version = result.serverVersion;
        showAppNotification(
          S.of(context).connectedType(type, version),
          type: AppNotificationType.success,
        );
      } else {
        showAppNotification(
          result.error ?? S.of(context).connectFailed,
          type: AppNotificationType.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showAppNotification('$error', type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await ref.read(nasServiceProvider(_kind)).disconnect();
      if (!mounted) return;
      _passwordController.clear();
      showAppNotification(S.of(context).disconnected(_kind.title), type: AppNotificationType.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(nasConfigProvider(_kind));
    final connected = ref.watch(nasConnectedProvider(_kind));
    _hydrate(config);
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _kind.settingsTitle,
          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            _kind.intro,
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          _field(
            label: S.of(context).serverAddress,
            child: TextField(
              controller: _urlController,
              focusNode: _urlFocus,
              enabled: !_busy,
              keyboardType: desktopSafeKeyboardType(TextInputType.url),
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: on, fontSize: 14),
              decoration: _decoration(hint: _kind.urlHint),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: _kind == NasKind.plex ? S.of(context).usernameOptional : S.of(context).username,
            child: TextField(
              controller: _usernameController,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: on, fontSize: 14),
              decoration: _decoration(
                hint: _kind == NasKind.plex
                    ? S.of(context).plexAccountHint
                    : S.of(context).serverLoginName,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: _kind == NasKind.plex ? S.of(context).passwordOrToken : S.of(context).password,
            child: TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: on, fontSize: 14),
              decoration:
                  _decoration(
                    hint: connected
                        ? S.of(context).passwordSaved
                        : _kind == NasKind.plex
                        ? S.of(context).passwordOrPlexToken
                        : S.of(context).serverPassword,
                  ).copyWith(
                    suffixIcon: FxIconButton(
                      tooltip: _obscurePassword ? S.of(context).showPassword : S.of(context).hidePassword,
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: muted,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(connected ? S.of(context).reconnect : S.of(context).connect),
          ),
          if (connected) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _disconnect,
              child: Text(S.of(context).disconnect),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).currentConnection(
                _kind.title,
                config.hostLabel,
                config.username.isEmpty ? null : config.username,
              ),
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.mutedText(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _decoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.mutedText(context), fontSize: 13),
      filled: true,
      fillColor: AppColors.miniBar(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
