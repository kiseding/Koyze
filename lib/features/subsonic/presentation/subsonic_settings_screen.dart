import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../nas/domain/nas_config.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/domain/nas_url.dart';
import '../../nas/domain/self_hosted_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../domain/subsonic_config.dart';
import '../domain/subsonic_url.dart';
import 'subsonic_provider.dart';

class SubsonicSettingsScreen extends ConsumerStatefulWidget {
  const SubsonicSettingsScreen({super.key, this.initialKind});

  final SelfHostedKind? initialKind;

  @override
  ConsumerState<SubsonicSettingsScreen> createState() =>
      _SubsonicSettingsScreenState();
}

class _SubsonicSettingsScreenState
    extends ConsumerState<SubsonicSettingsScreen> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlFocus = FocusNode();
  bool _legacyAuth = false;
  bool _obscurePassword = true;
  bool _busy = false;
  bool _hydrated = false;
  SelfHostedKind? _hydratedKind;
  SelfHostedKind? _seededKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _seedInitialKind();
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  SelfHostedKind get _kind => ref.read(selfHostedKindProvider);

  void _selectKind(SelfHostedKind kind) {
    if (kind == _kind) return;
    setState(() {
      _hydrated = false;
      _passwordController.clear();
    });
    ref.read(selfHostedKindProvider.notifier).select(kind);
  }

  void _seedInitialKind() {
    final initial = widget.initialKind;
    if (initial == null || _seededKind == initial) return;
    _seededKind = initial;
    if (ref.read(selfHostedKindProvider) == initial) return;
    ref.read(selfHostedKindProvider.notifier).select(initial);
  }

  void _hydrateSubsonic(SubsonicConfig config) {
    if (_hydrated && _hydratedKind == SelfHostedKind.subsonic) return;
    _hydrated = true;
    _hydratedKind = SelfHostedKind.subsonic;
    _urlController.text = config.baseUrl;
    _usernameController.text = config.username;
    _legacyAuth = config.legacyAuth;
  }

  void _hydrateNas(NasConfig config, SelfHostedKind kind) {
    if (_hydrated && _hydratedKind == kind) return;
    _hydrated = true;
    _hydratedKind = kind;
    _urlController.text = config.baseUrl;
    _usernameController.text = config.username;
  }

  Future<void> _connect() async {
    final nasKind = _kind.nasKind;
    if (nasKind == null) {
      await _connectSubsonic();
    } else {
      await _connectNas(nasKind);
    }
  }

  Future<void> _connectSubsonic() async {
    final url = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    try {
      validateSubsonicServiceUrl(url);
    } catch (error) {
      showAppNotification(
        error is ArgumentError ? error.message ?? '$error' : '$error',
        type: AppNotificationType.error,
      );
      return;
    }
    if (username.isEmpty) {
      showAppNotification(S.of(context).enterUsername, type: AppNotificationType.error);
      return;
    }
    if (password.isEmpty) {
      showAppNotification(S.of(context).enterPassword, type: AppNotificationType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(subsonicServiceProvider).connect(
            baseUrl: url,
            username: username,
            password: password,
            legacyAuth: _legacyAuth,
          );
      if (!mounted) return;
      if (result.ok) {
        _passwordController.clear();
        final type = result.serverType ?? 'Subsonic';
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

  Future<void> _connectNas(NasKind nasKind) async {
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
    if (nasKind != NasKind.plex && username.isEmpty) {
      showAppNotification(S.of(context).enterUsername, type: AppNotificationType.error);
      return;
    }
    if (password.isEmpty) {
      showAppNotification(
        nasKind == NasKind.plex ? S.of(context).enterPasswordOrToken : S.of(context).enterPassword,
        type: AppNotificationType.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(nasServiceProvider(nasKind)).connect(
            baseUrl: url,
            username: username,
            password: password,
          );
      if (!mounted) return;
      if (result.ok) {
        _passwordController.clear();
        final type = result.serverType ?? nasKind.title;
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
      final kind = _kind;
      final nasKind = kind.nasKind;
      if (nasKind == null) {
        await ref.read(subsonicServiceProvider).disconnect();
      } else {
        await ref.read(nasServiceProvider(nasKind)).disconnect();
      }
      if (!mounted) return;
      _passwordController.clear();
      showAppNotification(S.of(context).disconnected(kind.title), type: AppNotificationType.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _seedInitialKind();
    final kind = ref.watch(selfHostedKindProvider);
    final nasKind = kind.nasKind;
    final subsonicConfig = ref.watch(subsonicConfigProvider);
    final subsonicConnected = ref.watch(subsonicConnectedProvider);
    final nasConfig = nasKind == null
        ? null
        : ref.watch(nasConfigProvider(nasKind));
    final nasConnected =
        nasKind == null ? false : ref.watch(nasConnectedProvider(nasKind));
    if (nasKind == null) {
      _hydrateSubsonic(subsonicConfig);
    } else {
      _hydrateNas(nasConfig!, kind);
    }
    final connected = nasKind == null ? subsonicConnected : nasConnected;
    final hostLabel = nasKind == null
        ? subsonicConfig.hostLabel
        : nasConfig!.hostLabel;
    final username = nasKind == null
        ? subsonicConfig.username
        : nasConfig!.username;
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);

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
          S.of(context).nasServerTitle,
          style: TextStyle(color: on, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in SelfHostedKind.values)
                ChoiceChip(
                  label: Text(option.chipLabel),
                  selected: kind == option,
                  onSelected: _busy ? null : (_) => _selectKind(option),
                  selectedColor: accent.withAlpha(40),
                  labelStyle: TextStyle(
                    color: kind == option ? accent : on,
                    fontSize: 13,
                    fontWeight:
                        kind == option ? FontWeight.w600 : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: kind == option
                        ? accent
                        : AppColors.cardBorder(context),
                  ),
                  backgroundColor: AppColors.miniBar(context),
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            kind.intro,
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
              decoration: _decoration(hint: kind.urlHint),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: kind == SelfHostedKind.plex ? S.of(context).usernameOptional : S.of(context).username,
            child: TextField(
              controller: _usernameController,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: on, fontSize: 14),
              decoration: _decoration(
                hint: kind == SelfHostedKind.plex
                    ? S.of(context).plexAccountHint
                    : S.of(context).serverLoginName,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: kind == SelfHostedKind.plex ? S.of(context).passwordOrToken : S.of(context).password,
            child: TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: on, fontSize: 14),
              decoration: _decoration(
                hint: connected
                    ? S.of(context).passwordSaved
                    : kind == SelfHostedKind.plex
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
          if (kind == SelfHostedKind.subsonic) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.of(context).legacyAuth,
                          style: TextStyle(
                            color: on,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          S.of(context).legacyAuthHint,
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  FxSwitch(
                    value: _legacyAuth,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _legacyAuth = value),
                  ),
                ],
              ),
            ),
          ],
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
                kind.title,
                hostLabel,
                username.isEmpty ? null : username,
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
