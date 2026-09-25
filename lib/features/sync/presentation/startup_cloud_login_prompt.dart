import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../cloud/presentation/cloud_provider.dart';

const startupCloudLoginPromptSeenKey = 'startup_cloud_login_prompt_seen';

/// 首次启动门控：未登录且从未跳过时，第一屏显示全屏登录页；
/// 登录成功或点击跳过后进入主界面。
class StartupCloudLoginPrompt extends ConsumerStatefulWidget {
  const StartupCloudLoginPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupCloudLoginPrompt> createState() =>
      _StartupCloudLoginPromptState();
}

class _StartupCloudLoginPromptState
    extends ConsumerState<StartupCloudLoginPrompt> {
  bool? _showLogin;

  @override
  void initState() {
    super.initState();
    _loadGate();
  }

  Future<void> _loadGate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var seen = prefs.getBool(startupCloudLoginPromptSeenKey) == true;
    var session = ref.read(cloudSessionProvider);
    if (!session.loaded) {
      // Avoid treating a still-restoring session as logged-out first launch.
      for (var i = 0; i < 40 && mounted && !session.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        session = ref.read(cloudSessionProvider);
      }
    }
    if (!mounted) return;
    if (session.loggedIn && !seen) {
      await prefs.setBool(startupCloudLoginPromptSeenKey, true);
      seen = true;
    }
    if (!mounted) return;
    setState(() => _showLogin = !seen && !session.loggedIn);
  }

  Future<void> _finish({required bool completed}) async {
    if (completed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(startupCloudLoginPromptSeenKey, true);
    }
    if (!mounted) return;
    setState(() => _showLogin = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin == true) {
      return _StartupCloudLoginPage(onDone: () => _finish(completed: true));
    }
    return widget.child;
  }
}

class _StartupCloudLoginPage extends ConsumerStatefulWidget {
  const _StartupCloudLoginPage({required this.onDone});

  final Future<void> Function() onDone;

  @override
  ConsumerState<_StartupCloudLoginPage> createState() =>
      _StartupCloudLoginPageState();
}

class _StartupCloudLoginPageState
    extends ConsumerState<_StartupCloudLoginPage> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _serverFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _serverFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final server = _serverCtrl.text.trim();
    final username = _userCtrl.text.trim();
    if (server.isEmpty || username.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = S.of(context).fillServerLogin);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(cloudSessionProvider.notifier);
      await session.setBaseUrl(server);
      final ok = _register
          ? await session.register(username, _passCtrl.text)
          : await session.login(username, _passCtrl.text);
      if (!mounted) return;
      if (ok) {
        await widget.onDone();
      } else {
        setState(() => _error = ref.read(cloudSessionProvider).error ?? S.of(context).loginFailed);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.cloud_sync_rounded,
                    color: AppColors.amber,
                    size: 56,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    S.of(context).welcome,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    S.of(context).welcomeBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _serverCtrl,
                    focusNode: _serverFocus,
                    keyboardType: desktopSafeKeyboardType(TextInputType.url),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    onSubmitted: (_) => _userFocus.requestFocus(),
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration(
                      S.of(context).serverAddress,
                      'https://your-worker.example',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _userCtrl,
                    focusNode: _userFocus,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passFocus.requestFocus(),
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration(S.of(context).username, S.of(context).syncUsernameHint),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    focusNode: _passFocus,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_busy) _submit();
                    },
                    obscureText: true,
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration(S.of(context).password, S.of(context).syncPasswordHint),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: Icon(
                      _register ? Icons.person_add_alt_1 : Icons.login,
                    ),
                    label: Text(
                      _busy ? S.of(context).pleaseWait : (_register ? S.of(context).registerAndSync : S.of(context).loginAndSync),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: theme.colorScheme.onPrimary,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _register = !_register),
                    child: Text(_register ? S.of(context).backToLogin : S.of(context).needAccount),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _busy ? null : () => widget.onDone(),
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(S.of(context).skipStep),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.mutedText(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.of(context).skipStepHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.mutedText(context),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(color: AppColors.mutedText(context)),
      hintStyle: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
      filled: true,
      fillColor: AppColors.fill(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.cardBorder(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.cardBorder(context)),
      ),
    );
  }
}
