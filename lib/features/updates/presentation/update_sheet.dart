import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_version.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/koyze_sheet.dart';
import '../../../l10n/app_strings.dart';
import '../domain/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// 检查更新面板。
///
/// 打开即查：这个面板的唯一用途就是查更新，再加一个"开始检查"按钮等于让用户
/// 点两次。查不到就如实说查不到——网络问题不该伪装成"已是最新"。
Future<void> showUpdateSheet(BuildContext context) {
  return showKoyzeSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const UpdateSheet(),
  );
}

class UpdateSheet extends ConsumerStatefulWidget {
  const UpdateSheet({super.key});

  @override
  ConsumerState<UpdateSheet> createState() => _UpdateSheetState();
}

enum _Phase { checking, latest, failed, available, downloading, installed }

class _UpdateSheetState extends ConsumerState<UpdateSheet> {
  _Phase _phase = _Phase.checking;
  AppUpdate? _update;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _phase = _Phase.checking);
    final result = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() {
      _update = result;
      _phase = result == null ? _Phase.latest : _Phase.available;
    });
  }

  Future<void> _downloadAndInstall() async {
    final update = _update;
    if (update == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    try {
      final path = await ref.read(updateServiceProvider).download(
        update,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );
      final ok = await ref.read(updateServiceProvider).install(path);
      if (!mounted) return;
      setState(() => _phase = ok ? _Phase.installed : _Phase.available);
      if (!ok) {
        // 没装起来通常是"未授予安装未知来源"，系统已经跳到授权页，
        // 这里只需要说明一句，不必报错。
        _snack(S.of(context).updateInstallHint);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.available);
      _snack(S.of(context).updateCheckFailed);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final accent = AppColors.accentOf(context);
    final primary = AppColors.onScaffold(context);
    final secondary = AppColors.secondaryText(context);
    final update = _update;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KoyzeSheetTitle(
          title: s.checkUpdates,
          subtitle: s.checkUpdatesSubtitle(kAppVersion),
          onClose: () => Navigator.pop(context),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              switch (_phase) {
                _Phase.checking => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2.2, color: accent),
                      const SizedBox(height: 12),
                      Text(
                        s.checkUpdates,
                        style: TextStyle(fontSize: 12.5, color: secondary),
                      ),
                    ],
                  ),
                ),
                _Phase.latest => _Message(
                  icon: Icons.check_circle_outline_rounded,
                  text: s.updateLatest,
                  color: accent,
                ),
                _Phase.failed => _Message(
                  icon: Icons.cloud_off_rounded,
                  text: s.updateCheckFailed,
                  color: secondary,
                  action: TextButton(
                    onPressed: _check,
                    child: Text(s.retry),
                  ),
                ),
                _Phase.installed => _Message(
                  icon: Icons.download_done_rounded,
                  text: s.updateInstallHint,
                  color: accent,
                ),
                _Phase.available || _Phase.downloading => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      s.updateAvailable(update?.version ?? ''),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primary,
                      ),
                    ),
                    if (update != null && update.publishedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${update.publishedAt!.year}-'
                          '${update.publishedAt!.month.toString().padLeft(2, '0')}-'
                          '${update.publishedAt!.day.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11.5, color: secondary),
                        ),
                      ),
                    if (update != null && update.notes.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        s.updateNotes,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.cardBorder(context),
                            width: 0.8,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            update.notes.trim(),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: primary.withValues(alpha: 0.86),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (_phase == _Phase.downloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _progress <= 0 ? null : _progress,
                          minHeight: 5,
                          backgroundColor: AppColors.cardBorder(context),
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.updateDownloading((_progress * 100).round()),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ] else
                      FilledButton(
                        onPressed: (update?.hasAsset ?? false)
                            ? _downloadAndInstall
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: AppColors.onAccentOf(context),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          (update?.hasAsset ?? false)
                              ? s.updateDownloadInstall
                              : s.updateNoAsset,
                        ),
                      ),
                  ],
                ),
              },
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.color,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText(context),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
