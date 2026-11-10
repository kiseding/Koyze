import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_notification.dart';
import '../../../core/widgets/gradient_bar_backgrounds.dart';
import '../../../core/widgets/origo_chrome.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/fx_switch.dart';
import '../../../core/widgets/koyze_modal.dart';
import '../../nas/domain/nas_client.dart';
import '../../nas/domain/nas_config.dart';
import '../../nas/domain/nas_kind.dart';
import '../../nas/domain/webdav_client.dart';
import '../../nas/presentation/plex_pin_dialog.dart';
import '../../nas/presentation/webdav_directory_picker.dart';
import '../../nas/domain/nas_url.dart';
import '../../nas/domain/self_hosted_kind.dart';
import '../../nas/presentation/nas_provider.dart';
import '../domain/subsonic_config.dart';
import '../domain/subsonic_url.dart';
import 'subsonic_provider.dart';
import '../../../core/widgets/loading_widget.dart';

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
  final _rootPathController = TextEditingController();
  final _urlFocus = FocusNode();
  bool _legacyAuth = false;
  bool _obscurePassword = true;
  bool _busy = false;
  bool _hydrated = false;
  SelfHostedKind? _hydratedKind;
  SelfHostedKind? _seededKind;
  NasAuthMethod _webDavAuth = NasAuthMethod.basic;
  String? _plexClientId;

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
    _rootPathController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  SelfHostedKind get _kind => ref.read(selfHostedKindProvider);

  bool get _isWebDav => _kind == SelfHostedKind.webdav;

  /// WebDAV 与群晖只吐静态文件，压码率这档对它们没有意义。
  bool get _supportsTranscoding {
    final nasKind = _kind.nasKind;
    if (nasKind == null) return true;
    return nasKind != NasKind.webdav && nasKind != NasKind.audiostation;
  }

  String _qualityLabel(BuildContext context, String quality) {
    if (quality == kNasQualityOriginal) return S.of(context).qualityOriginal;
    final kbps = quality.replaceAll('k', '');
    return '$kbps kbps';
  }

  Future<void> _setQuality(String quality) async {
    final nasKind = _kind.nasKind;
    try {
      if (nasKind == null) {
        await setSubsonicStreamQuality(ref, quality);
      } else {
        await setNasStreamQuality(ref, nasKind, quality);
      }
    } catch (error) {
      if (!mounted) return;
      showAppNotification('$error', type: AppNotificationType.error);
    }
  }

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
    _rootPathController.text = config.rootPath;
    _webDavAuth = config.authMethod;
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
      showAppNotification(
        S.of(context).enterUsername,
        type: AppNotificationType.error,
      );
      return;
    }
    if (password.isEmpty) {
      showAppNotification(
        S.of(context).enterPassword,
        type: AppNotificationType.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(subsonicServiceProvider)
          .connect(
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
    final isWebDav = nasKind == NasKind.webdav;
    final bearer = isWebDav && _webDavAuth == NasAuthMethod.bearer;
    String? rootPath;
    try {
      validateNasServiceUrl(url);
      if (isWebDav) {
        rootPath = normalizeNasRootPath(_rootPathController.text);
      }
    } catch (error) {
      showAppNotification(
        error is ArgumentError ? error.message ?? '$error' : '$error',
        type: AppNotificationType.error,
      );
      return;
    }
    if (!bearer && nasKind != NasKind.plex && username.isEmpty) {
      showAppNotification(
        S.of(context).enterUsername,
        type: AppNotificationType.error,
      );
      return;
    }
    if (password.isEmpty) {
      showAppNotification(
        bearer
            ? S.of(context).webDavTokenHint
            : nasKind == NasKind.plex
            ? S.of(context).enterPasswordOrToken
            : S.of(context).enterPassword,
        type: AppNotificationType.error,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(nasServiceProvider(nasKind))
          .connect(
            baseUrl: url,
            username: username,
            password: password,
            rootPath: rootPath,
            authMethod: isWebDav ? _webDavAuth : null,
            deviceId: nasKind == NasKind.plex ? _plexClientId : null,
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

  /// Plex 开了两步验证之后密码登录走不通，改用登录码：
  /// 先跟 plex.tv 换一个 4 位码，用户在 plex.tv/link 里授权，再回来拿 token。
  Future<void> _loginWithPlex() async {
    final client = ref.read(nasServiceProvider(NasKind.plex)).plexClient;
    if (client == null) return;
    final result = await showPlexPinDialog(
      context,
      client: client,
      clientId: client.clientId,
    );
    if (result == null || !mounted) return;
    setState(() {
      _passwordController.text = result.token;
      _plexClientId = result.clientId;
    });
    await _connectNas(NasKind.plex);
  }

  Future<void> _selectServer(String baseUrl) async {
    final nasKind = _kind.nasKind;
    setState(() => _busy = true);
    try {
      if (nasKind == null) {
        await switchSubsonicServer(ref, baseUrl);
      } else {
        await switchNasServer(ref, nasKind, baseUrl);
      }
      if (!mounted) return;
      setState(() {
        // 让 build 里的 hydrate 重新把新服务器的配置灌进表单。
        _hydrated = false;
        _passwordController.clear();
        _plexClientId = null;
      });
    } catch (error) {
      if (!mounted) return;
      showAppNotification('$error', type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteServer(_SavedServer server) async {
    final s = S.of(context);
    final confirmed = await showKoyzeDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.deleteServer),
        content: Text(s.deleteServerConfirm(server.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(s.deleteServer),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final nasKind = _kind.nasKind;
    setState(() => _busy = true);
    try {
      if (nasKind == null) {
        await removeSubsonicServer(ref, server.baseUrl);
      } else {
        await removeNasServer(ref, nasKind, server.baseUrl);
      }
      if (!mounted) return;
      setState(() {
        _hydrated = false;
        _passwordController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      showAppNotification('$error', type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 清空表单，从「再加一台」开始填。
  void _addServer() {
    setState(() {
      _hydrated = true;
      _hydratedKind = _kind;
      _urlController.clear();
      _usernameController.clear();
      _passwordController.clear();
      _rootPathController.clear();
      _webDavAuth = NasAuthMethod.basic;
      _plexClientId = null;
    });
  }

  Widget _serverTile(
    BuildContext context,
    _SavedServer server,
    String currentBaseUrl,
  ) {
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    final accent = AppColors.accentOf(context);
    final selected = server.baseUrl == currentBaseUrl;
    return InkWell(
      onTap: _busy || selected ? null : () => _selectServer(server.baseUrl),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? accent : muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (server.username.isNotEmpty)
                    Text(
                      server.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                ],
              ),
            ),
            FxIconButton(
              tooltip: S.of(context).deleteServer,
              icon: Icon(Icons.delete_outline, size: 16, color: muted),
              onPressed: _busy ? null : () => _deleteServer(server),
            ),
          ],
        ),
      ),
    );
  }

  /// 手打 `/volume1/music` 太容易出错，直接列目录让人挑。
  Future<void> _browseWebDavRoot() async {
    final typedPassword = _passwordController.text;
    final bearer = _webDavAuth == NasAuthMethod.bearer;
    WebDavNasClient? tempClient;
    Future<List<WebDavDirectory>> Function(String) loader;
    try {
      final baseUrl = validateNasServiceUrl(_urlController.text.trim());
      if (typedPassword.isNotEmpty) {
        final client = tempClient = WebDavNasClient();
        final config = NasConfig(
          kind: NasKind.webdav,
          baseUrl: baseUrl,
          username: _usernameController.text.trim(),
          authMethod: _webDavAuth,
        );
        final secrets = bearer
            ? NasSecrets(token: typedPassword)
            : NasSecrets(password: typedPassword);
        loader = (path) => client.listDirectories(config, secrets, path);
      } else {
        final service = ref.read(nasServiceProvider(NasKind.webdav));
        await service.init();
        loader = service.listDirectories;
      }
    } catch (error) {
      showAppNotification(
        error is ArgumentError ? error.message ?? '$error' : '$error',
        type: AppNotificationType.error,
      );
      return;
    }
    if (!mounted) {
      tempClient?.dispose();
      return;
    }
    final picked = await showWebDavDirectoryPicker(
      context,
      load: loader,
      onDispose: tempClient?.dispose,
      initialPath: _rootPathController.text.trim().isEmpty
          ? '/'
          : _rootPathController.text.trim(),
    );
    if (picked != null && mounted) {
      setState(() => _rootPathController.text = picked);
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
      showAppNotification(
        S.of(context).disconnected(kind.title),
        type: AppNotificationType.info,
      );
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
    final nasConnected = nasKind == null
        ? false
        : ref.watch(nasConnectedProvider(nasKind));
    if (nasKind == null) {
      _hydrateSubsonic(subsonicConfig);
    } else {
      _hydrateNas(nasConfig!, kind);
    }
    final savedServers = nasKind == null
        ? [
            for (final server in ref.watch(subsonicServersProvider))
              _SavedServer(
                baseUrl: server.baseUrl,
                label: server.hostLabel,
                username: server.username,
              ),
          ]
        : [
            for (final server in ref.watch(nasServersProvider(nasKind)))
              _SavedServer(
                baseUrl: server.baseUrl,
                label: server.hostLabel,
                username: server.username,
              ),
          ];
    final currentBaseUrl = nasKind == null
        ? subsonicConfig.baseUrl
        : nasConfig!.baseUrl;
    final currentQuality = nasKind == null
        ? ref.watch(subsonicStreamQualityProvider)
        : ref.watch(nasStreamQualityProvider(nasKind));
    final connected = nasKind == null ? subsonicConnected : nasConnected;
    final hostLabel = nasKind == null
        ? subsonicConfig.hostLabel
        : nasConfig!.hostLabel;
    final username = nasKind == null
        ? subsonicConfig.username
        : nasConfig!.username;
    final on = AppColors.onScaffold(context);
    final muted = AppColors.mutedText(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        flexibleSpace: GradientAppBarBackground(
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
        leading: FxIconButton(
          tooltip: S.of(context).back,
          icon: Icon(Icons.arrow_back, color: on),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.of(context).nasServerTitle,
          style: TextStyle(
            color: on,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: ListView(
        padding: koyzeAppBarContentPadding(context, bottom: 32),
        children: [
          GlassSurface(
            style: AppGlassStyle.regular,
            borderRadius: BorderRadius.circular(18),
            border: Border.fromBorderSide(
              AppGlass.hairline(context, emphasized: false),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in SelfHostedKind.values)
                      KoyzeChoicePill(
                        label: option.chipLabel,
                        icon: option.icon,
                        selected: kind == option,
                        onPressed: _busy ? null : () => _selectKind(option),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  kind.intro,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.of(context).savedServers,
                        style: TextStyle(
                          color: muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _addServer,
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(
                        S.of(context).addServer,
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                if (savedServers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      S.of(context).noServersYet,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                else
                  for (final server in savedServers)
                    _serverTile(context, server, currentBaseUrl),
                const SizedBox(height: 12),
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
                if (_isWebDav) ...[
                  _field(
                    label: S.of(context).webDavRootPath,
                    child: TextField(
                      controller: _rootPathController,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: TextStyle(color: on, fontSize: 14),
                      decoration: _decoration(
                        hint: S.of(context).webDavRootPathHint,
                      ).copyWith(
                        suffixIcon: TextButton.icon(
                          onPressed: _busy ? null : _browseWebDavRoot,
                          icon: const Icon(Icons.folder_open_outlined, size: 16),
                          label: Text(S.of(context).browseDirectory),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentOf(context),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    label: S.of(context).webDavAuthMethod,
                    child: SegmentedButton<NasAuthMethod>(
                      segments: [
                        ButtonSegment(
                          value: NasAuthMethod.basic,
                          label: Text(S.of(context).webDavBasicAuth),
                          icon: const Icon(Icons.password_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: NasAuthMethod.bearer,
                          label: Text(S.of(context).webDavBearerAuth),
                          icon: const Icon(Icons.key_outlined, size: 16),
                        ),
                      ],
                      selected: {_webDavAuth},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) =>
                                setState(() => _webDavAuth = selection.first),
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 12, color: on),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_isWebDav || _webDavAuth == NasAuthMethod.basic) ...[
                  _field(
                    label: kind == SelfHostedKind.plex
                        ? S.of(context).usernameOptional
                        : S.of(context).username,
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
                ],
                _field(
                  label: _isWebDav && _webDavAuth == NasAuthMethod.bearer
                      ? S.of(context).webDavBearerAuth
                      : kind == SelfHostedKind.plex
                      ? S.of(context).passwordOrToken
                      : S.of(context).password,
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
                              : _isWebDav && _webDavAuth == NasAuthMethod.bearer
                              ? S.of(context).webDavTokenHint
                              : kind == SelfHostedKind.plex
                              ? S.of(context).passwordOrPlexToken
                              : S.of(context).serverPassword,
                        ).copyWith(
                          suffixIcon: FxIconButton(
                            tooltip: _obscurePassword
                                ? S.of(context).showPassword
                                : S.of(context).hidePassword,
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                              color: muted,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                  ),
                ),
                if (kind == SelfHostedKind.plex) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _loginWithPlex,
                      icon: const Icon(Icons.login_outlined, size: 16),
                      label: Text(
                        S.of(context).plexPinLogin,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
                if (kind == SelfHostedKind.subsonic) ...[
                  const SizedBox(height: 8),
                  GlassSurface(
                    style: AppGlassStyle.regular,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.fromBorderSide(
                      AppGlass.hairline(context, emphasized: false),
                    ),
                    padding: const EdgeInsets.all(12),
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
                if (_supportsTranscoding) ...[
                  const SizedBox(height: 12),
                  _field(
                    label: S.of(context).streamQuality,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final quality in kNasQualityOptions)
                          KoyzeChoicePill(
                            label: _qualityLabel(context, quality),
                            selected: currentQuality == quality,
                            onPressed: _busy
                                ? null
                                : () => _setQuality(quality),
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
                          child: AppLoadingIndicator(strokeWidth: 2),
                        )
                      : Text(
                          connected
                              ? S.of(context).reconnect
                              : S.of(context).connect,
                        ),
                ),
                if (connected) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _disconnect,
                    child: Text(S.of(context).disconnect),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    S
                        .of(context)
                        .currentConnection(
                          kind.title,
                          hostLabel,
                          username.isEmpty ? null : username,
                        ),
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  if (_isWebDav) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${S.of(context).webDavRootPath}: ${nasConfig?.rootPath ?? '/'}'
                      ' · ${S.of(context).webDavAuthMethod}: '
                      '${(nasConfig?.authMethod ?? NasAuthMethod.basic) == NasAuthMethod.bearer ? S.of(context).webDavBearerAuth : S.of(context).webDavBasicAuth}',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ],
            ),
          ),
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
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: AppGlass.hairline(context, emphasized: false),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: AppGlass.hairline(context, emphasized: true),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.mutedText(context), fontSize: 13),
      filled: true,
      fillColor: AppGlass.fill(context, style: AppGlassStyle.chrome),
      border: border,
      enabledBorder: border,
      focusedBorder: focusedBorder,
      disabledBorder: border,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

class _SavedServer {
  const _SavedServer({
    required this.baseUrl,
    required this.label,
    required this.username,
  });

  final String baseUrl;
  final String label;
  final String username;
}
