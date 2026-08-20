import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
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
    final seen = prefs.getBool(startupCloudLoginPromptSeenKey) == true;
    final loggedIn = ref.read(cloudSessionProvider).loggedIn;
    setState(() => _showLogin = !seen && !loggedIn);
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
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final server = _serverCtrl.text.trim();
    final username = _userCtrl.text.trim();
    if (server.isEmpty || username.isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = '请填写服务器、用户名和密码');
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
        setState(() => _error = ref.read(cloudSessionProvider).error ?? '登录失败');
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
                  Icon(
                    Icons.cloud_sync_rounded,
                    color: AppColors.amber,
                    size: 56,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '欢迎使用 Koyze',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.onScaffold(context),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '登录云端账号后，可跨设备同步收藏、歌单、设置和自定义音源。',
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
                    keyboardType: TextInputType.url,
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration(
                      '服务器地址',
                      'https://your-worker.example',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _userCtrl,
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration('用户名', '同步账号用户名'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    enableInteractiveSelection: true,
                    contextMenuBuilder: (context, state) =>
                        AdaptiveTextSelectionToolbar.editableText(
                          editableTextState: state,
                        ),
                    style: TextStyle(color: AppColors.onScaffold(context)),
                    decoration: _decoration('密码', '同步账号密码'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: Icon(
                      _register ? Icons.person_add_alt_1 : Icons.login,
                    ),
                    label: Text(
                      _busy ? '请稍候…' : (_register ? '注册并开始同步' : '登录并开始同步'),
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
                    child: Text(_register ? '已有账号，返回登录' : '还没有账号？注册一个'),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _busy ? null : () => widget.onDone(),
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('跳过这一步'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.mutedText(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '跳过后不会影响本地播放；你之后可以随时在“设置 → 同步”添加账号。',
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
