import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/animations/micro_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../../cloud/presentation/cloud_provider.dart';
import '../../cloud/domain/cloud_api_client.dart';
import 'cloud_sync_provider.dart';
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
          '同步 / 云端账号',
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
                'Workers 服务器',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              subtitle: Text(
                session.baseUrl ?? '未配置（例如 https://xxx.workers.dev）',
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
                session.loggedIn ? '已登录：${session.username}' : '未登录',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              subtitle: Text(
                session.loggedIn
                    ? '角色：${session.role ?? 'user'}'
                    : '登录后可同步云端歌单',
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
                            ref.watch(cloudSyncProvider).message ?? '同步中…',
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
            '说明：在此配置并登录 workers 后端。搜歌/播放仍在本机完成，云端负责账号、歌单、设置与音源。',
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
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('登录'),
                        icon: Icon(Icons.login_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('注册'),
                        icon: Icon(Icons.person_add_alt_1_rounded, size: 18),
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
                labelText: '用户名',
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
                labelText: '密码',
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
              label: Text(_busy ? '请稍候…' : (_isLoginMode ? '登录' : '注册')),
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
          '事件同步',
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
              '立即同步',
              style: TextStyle(color: AppColors.onScaffold(context)),
            ),
            subtitle: Text(
              sync.phase == CloudSyncPhase.syncing
                  ? '正在安全合并本地与云端事件…'
                  : '只上传本地变更并拉取其他设备变更，不覆盖数据',
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
          sync.message ?? '数据保存在本地，网络恢复后自动同步',
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
        ),
        if (sync.report case final report?) ...[
          const SizedBox(height: 8),
          Text(
            '设备：${report.deviceId}',
            style: TextStyle(color: AppColors.mutedText(context), fontSize: 11),
          ),
          Text(
            '时间：${report.completedAt.toLocal()}',
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
        title: const Text('退出登录', style: TextStyle(color: AppColors.error)),
        subtitle: Text(
          '退出后保留收藏、歌单、评分、播放历史、下载与缓存，仅清除登录状态',
          style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
        ),
        onTap: _busy
            ? null
            : () async {
                await ref.read(cloudSessionProvider.notifier).logout();
                if (!mounted) return;
                setState(() => _message = '已退出登录');
              },
      ),
    );
  }

  Widget _buildAdminSection() {
    return _card(
      child: ListTile(
        leading: const Icon(Icons.admin_panel_settings, color: AppColors.amber),
        title: Text(
          '用户管理（管理员）',
          style: TextStyle(color: AppColors.onScaffold(context)),
        ),
        subtitle: Text(
          '创建 / 删除 / 重置密码',
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
                'Workers 地址',
                style: TextStyle(color: AppColors.onScaffold(context)),
              ),
              content: SingleChildScrollView(
                child: TextField(
                  controller: ctrl,
                  focusNode: urlFocus,
                  keyboardType: TextInputType.url,
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
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  child: const Text(
                    '保存',
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
        setState(() => _message = alive ? '服务器可达' : '保存成功，但健康检查失败（部署后重试）');
      } on ArgumentError catch (error) {
        if (!mounted) return;
        setState(
          () => _message = error.message?.toString() ?? '服务器地址必须使用 HTTPS',
        );
      }
    }
  }

  Future<void> _submitAuth() async {
    if ((ref.read(cloudSessionProvider).baseUrl ?? '').isEmpty) {
      setState(() => _message = '请先填写服务器地址');
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
      _message = ok ? '登录成功' : (ref.read(cloudSessionProvider).error ?? '失败');
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
      setState(() => _message = sync.message ?? '同步完成');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '同步失败：$e');
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
        backgroundColor: AppColors.dialogBg(context),
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
                            '用户列表',
                            style: TextStyle(
                              color: AppColors.onScaffold(context),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
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
                                ? '管理员 · id=${u['id']}'
                                : '普通用户 · id=${u['id']}',
                            style: TextStyle(
                              color: AppColors.mutedText(context),
                              fontSize: 12,
                            ),
                          ),
                          trailing: FxIconButton(
                            tooltip: '删除 ${u['username']}',
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
                                  () => _message = '已删除 ${u['username']}',
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setState(() => _message = '删除失败: $e');
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
                                    '新建用户',
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
                                          decoration: const InputDecoration(
                                            labelText: '用户名',
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
                                          decoration: const InputDecoration(
                                            labelText: '密码',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(d),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(d, [
                                        u.text.trim(),
                                        p.text,
                                      ]),
                                      child: const Text(
                                        '创建',
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
                            setState(() => _message = '已创建用户');
                          } catch (e) {
                            if (!mounted) return;
                            setState(() => _message = '创建失败: $e');
                          }
                        }
                      },
                      child: const Text('新建用户'),
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
      setState(() => _message = '加载用户失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
