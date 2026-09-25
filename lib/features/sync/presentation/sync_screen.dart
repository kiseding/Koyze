import 'package:flutter/material.dart';
import 'package:koyze/l10n/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../cloud/presentation/cloud_provider.dart';
import '../../cloud/domain/cloud_api_client.dart';
import 'cloud_sync_provider.dart';
import '../../../core/widgets/auto_text_input.dart';
import '../../../core/widgets/fx_icon_button.dart';
import '../../../core/widgets/koyze_sheet.dart';

/// 同步页：对接 workers 云端（账号 + 歌单），不再强制首次启动登录。
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  bool _isLoginMode = true;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  CloudApiClient get _api => ref.read(cloudApiProvider);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(cloudSessionProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          S.of(context).syncTitle,
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        iconTheme: IconThemeData(color: AppColors.onScaffold(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined, color: AppColors.amber),
              title: Text(
                S.of(context).workersServer,
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              subtitle: Text(
                session.baseUrl ?? S.of(context).workersUnset,
                style: TextStyle(
                  color: session.baseUrl != null
                      ? AppColors.mutedText(context)
                      : AppColors.error,
                  fontSize: 12,
                ),
              ),
              trailing: Icon(
                Icons.edit,
                color: AppColors.mutedText(context),
                size: 18,
              ),
              onTap: _editServerUrl,
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: ListTile(
              leading: AnimatedIconSwitch(
                icon: session.loggedIn ? Icons.cloud_done : Icons.cloud_off,
                keyValue: session.loggedIn ? Icons.cloud_done : Icons.cloud_off,
                color: session.loggedIn
                    ? AppColors.success
                    : AppColors.mutedText(context),
              ),
              title: Text(
                session.loggedIn ? S.of(context).loggedInAs(session.username ?? '') : S.of(context).notLoggedIn,
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              subtitle: Text(
                session.loggedIn
                    ? S.of(context).roleLine(session.role ?? 'user')
                    : S.of(context).loginToSync,
                style: TextStyle(
                  color: AppColors.mutedText(context),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.fill(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: AppColors.secondaryText(context),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
          if (ref.watch(cloudSyncProvider).phase == CloudSyncPhase.syncing) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.fill(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ref.watch(cloudSyncProvider).message ?? S.of(context).syncing,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(minHeight: 4),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!session.loggedIn) _buildAuth(),
          if (session.loggedIn) ...[
            _buildLoggedInActions(session),
            if (session.role == 'admin') ...[
              const SizedBox(height: 16),
              _buildAdminSection(),
            ],
          ],
          const SizedBox(height: 24),
          if (session.loggedIn) ...[_buildLogout(), const SizedBox(height: 16)],
          Text(
            S.of(context).syncExplainer,
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder(context)),
      ),
      child: child,
    );
  }

  Widget _buildAuth() {
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 账号图标 + 模式切换（分段控件更贴近系统设置风格）
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_circle_rounded,
                    color: AppColors.amber,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(S.of(context).login),
                        icon: const Icon(Icons.login_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(S.of(context).register),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      ),
                    ],
                    selected: {_isLoginMode},
                    onSelectionChanged: (v) =>
                        setState(() => _isLoginMode = v.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.amber.withValues(alpha: 0.18)
                            : null,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? AppColors.amber
                            : AppColors.mutedText(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
              decoration: InputDecoration(
                labelText: S.of(context).username,
                prefixIcon: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.mutedText(context),
                  size: 20,
                ),
                labelStyle: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              focusNode: _passFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _submitAuth();
              },
              obscureText: true,
              enableInteractiveSelection: true,
              contextMenuBuilder: (context, state) =>
                  AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: state,
                  ),
              style: TextStyle(color: AppColors.onScaffold(context)),
              decoration: InputDecoration(
                labelText: S.of(context).password,
                prefixIcon: Icon(
                  Icons.lock_outline_rounded,
                  color: AppColors.mutedText(context),
                  size: 20,
                ),
                labelStyle: TextStyle(color: AppColors.mutedText(context)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _busy ? null : _submitAuth,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isLoginMode
                          ? Icons.login_rounded
                          : Icons.person_add_alt_1_rounded,
                      size: 18,
                    ),
              label: Text(_busy ? S.of(context).pleaseWait : (_isLoginMode ? S.of(context).login : S.of(context).register)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInActions(CloudSessionState session) {
    final sync = ref.watch(cloudSyncProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.of(context).eventSync,
          style: TextStyle(
            color: AppColors.secondaryText(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _card(
          child: ListTile(
            leading: Icon(
              Icons.sync,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              S.of(context).syncNow,
              style: TextStyle(color: AppColors.onScaffold(context)),
            ),
            subtitle: Text(
              sync.phase == CloudSyncPhase.syncing
                  ? S.of(context).mergingEvents
                  : S.of(context).syncDoesNotOverwrite,
              style: TextStyle(
                color: AppColors.mutedText(context),
                fontSize: 12,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              color: AppColors.mutedText(context),
            ),
            onTap: _busy ? null : _runSync,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          sync.message ?? S.of(context).offlineUntilNetwork,
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
        ),
        if (sync.report case final report?) ...[
          const SizedBox(height: 8),
          Text(
            S.of(context).deviceLine(report.deviceId),
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 11),
          ),
          Text(
            S.of(context).timeLine('${report.completedAt.toLocal()}'),
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 11),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in report.counts.entries)
                Chip(label: Text('${entry.key} ${entry.value}')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLogout() {
    return _card(
      child: ListTile(
        leading: const Icon(Icons.logout, color: AppColors.error),
        title: Text(S.of(context).logOut, style: TextStyle(color: AppColors.error)),
        subtitle: Text(
          S.of(context).logOutHint,
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
        ),
        onTap: _busy
            ? null
            : () async {
                await ref.read(cloudSessionProvider.notifier).logout();
                if (!mounted) return;
                setState(() => _message = S.of(context).loggedOut);
              },
      ),
    );
  }

  Widget _buildAdminSection() {
    return _card(
      child: ListTile(
        leading: const Icon(Icons.admin_panel_settings, color: AppColors.amber),
        title: Text(
          S.of(context).userAdmin,
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        subtitle: Text(
          S.of(context).userAdminHint,
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: AppColors.mutedText(context),
        ),
        onTap: _openAdminUsers,
      ),
    );
  }

  Future<void> _editServerUrl() async {
    final ctrl = TextEditingController(
      text: ref.read(cloudSessionProvider).baseUrl ?? '',
    );
    final urlFocus = FocusNode();
    final url =
        await showDialog<String>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              backgroundColor: AppColors.dialogBg(context),
              title: Text(
                S.of(context).workersAddress,
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              content: SingleChildScrollView(
                child: TextField(
                  controller: ctrl,
                  focusNode: urlFocus,
                  keyboardType: desktopSafeKeyboardType(TextInputType.url),
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableInteractiveSelection: true,
                  contextMenuBuilder: (context, state) =>
                      AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: state,
                      ),
                  style: TextStyle(color: AppColors.onScaffold(context)),
                  decoration: InputDecoration(
                    hintText: 'https://lx-music-api.xxx.workers.dev',
                    hintStyle: TextStyle(color: AppColors.mutedText(context)),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(S.of(context).cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: Text(
                    S.of(context).save,
                    style: TextStyle(color: AppColors.amber),
                  ),
                ),
              ],
            );
          },
        ).whenComplete(() {
          ctrl.dispose();
          urlFocus.dispose();
        });
    if (url != null) {
      try {
        await ref.read(cloudSessionProvider.notifier).setBaseUrl(url);
        final alive = await _api.ping();
        if (!mounted) return;
        setState(() => _message = alive ? S.of(context).serverReachable : S.of(context).savedHealthFailed);
      } on ArgumentError catch (error) {
        if (!mounted) return;
        setState(
          () => _message = error.message?.toString() ?? S.of(context).httpsRequired,
        );
      }
    }
  }

  Future<void> _submitAuth() async {
    if ((ref.read(cloudSessionProvider).baseUrl ?? '').isEmpty) {
      setState(() => _message = S.of(context).enterServerFirst);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final ok = _isLoginMode
        ? await ref.read(cloudSessionProvider.notifier).login(user, pass)
        : await ref.read(cloudSessionProvider.notifier).register(user, pass);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? S.of(context).loginSucceeded : (ref.read(cloudSessionProvider).error ?? S.of(context).failed);
    });
  }

  Future<void> _runSync() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(cloudSyncProvider.notifier).sync();
      if (!mounted) return;
      final sync = ref.read(cloudSyncProvider);
      setState(() => _message = sync.message ?? S.of(context).syncFinished);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = S.of(context).syncFailed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAdminUsers() async {
    setState(() => _busy = true);
    try {
      final users = await _api.adminListUsers();
      if (!mounted) return;
      await showKoyzeSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.people_alt_rounded,
                            color: AppColors.amber,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            S.of(context).userList,
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: S.of(context).close,
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.mutedText(context),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 0.5,
                    color: AppColors.cardBorder(context),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        final role = u['role']?.toString() ?? 'user';
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: role == 'admin'
                                ? AppColors.amber.withValues(alpha: 0.2)
                                : AppColors.fill(context),
                            child: Icon(
                              role == 'admin'
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.person_rounded,
                              size: 20,
                              color: role == 'admin'
                                  ? AppColors.amber
                                  : AppColors.mutedText(context),
                            ),
                          ),
                          title: Text(
                            '${u['username']}',
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            role == 'admin'
                                ? S.of(context).adminUser('${u['id']}')
                                : S.of(context).normalUser('${u['id']}'),
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                              fontSize: 12,
                            ),
                          ),
                          trailing: FxIconButton(
                            tooltip: S.of(context).deleteUser('${u['username']}'),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            onPressed: () async {
                              try {
                                await _api.adminDeleteUser(
                                  int.parse(u['id'].toString()),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (!mounted) return;
                                setState(
                                  () => _message = S.of(context).deletedUser('${u['username']}'),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setState(() => _message = '${S.of(context).deleteFailed}: $e');
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                      ),
                      onPressed: () async {
                        final u = TextEditingController();
                        final p = TextEditingController();
                        final userFocus = FocusNode();
                        final passFocus = FocusNode();
                        final credentials =
                            await showDialog<List<String>>(
                              context: ctx,
                              builder: (d) {
                                return AlertDialog(
                                  backgroundColor: AppColors.dialogBg(context),
                                  title: Text(
                                    S.of(context).newUser,
                                    style: TextStyle(
                                      color: AppColors.onScaffold(context),
                                    ),
                                  ),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          controller: u,
                                          focusNode: userFocus,
                                          textInputAction: TextInputAction.next,
                                          onSubmitted: (_) =>
                                              passFocus.requestFocus(),
                                          style: TextStyle(
                                            color: AppColors.onScaffold(
                                              context,
                                            ),
                                          ),
                                          decoration: InputDecoration(
                                            labelText: S.of(context).username,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextField(
                                          controller: p,
                                          focusNode: passFocus,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => Navigator.pop(d, [
                                            u.text.trim(),
                                            p.text,
                                          ]),
                                          obscureText: true,
                                          style: TextStyle(
                                            color: AppColors.onScaffold(
                                              context,
                                            ),
                                          ),
                                          decoration: InputDecoration(
                                            labelText: S.of(context).password,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d),
                                      child: Text(S.of(context).cancel),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, [
                                        u.text.trim(),
                                        p.text,
                                      ]),
                                      child: Text(
                                        S.of(context).create,
                                        style: TextStyle(
                                          color: AppColors.amber,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ).whenComplete(() {
                              u.dispose();
                              p.dispose();
                              userFocus.dispose();
                              passFocus.dispose();
                            });
                        if (credentials != null) {
                          try {
                            await _api.adminCreateUser(
                              credentials[0],
                              credentials[1],
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (!mounted) return;
                            setState(() => _message = S.of(context).userCreated);
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _message = '${S.of(context).createFailed}: $e');
                          }
                        }
                      },
                      child: Text(S.of(context).newUser),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = S.of(context).usersLoadFailed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
