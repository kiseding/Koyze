import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import 'app_notification.dart';
import '../../features/player/presentation/player_provider.dart';
import '../../../core/widgets/koyze_sheet.dart';

/// 睡眠定时弹窗（设置页与首页快捷入口共用）。
void showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  showKoyzeSheet(
    context: context,
    backgroundColor: AppColors.dialogBg(context),
    builder: (context) => SafeArea(
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(sleepTimerProvider);
          const options = [10, 15, 30, 60, 90];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.mutedText(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bedtime_outlined,
                      color: AppColors.accentOf(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '睡眠定时',
                        style: TextStyle(
                          color: AppColors.onScaffold(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (state case SleepTimerRunning())
                      _TickingSubtitle(state: state),
                  ],
                ),
              ),
              Divider(color: AppColors.cardBorder(context), height: 1),
              for (final minutes in options)
                ListTile(
                  leading: Icon(
                    Icons.timer_outlined,
                    color: AppColors.onScaffold(context),
                  ),
                  title: Text(
                    '$minutes 分钟',
                    style: TextStyle(color: AppColors.onScaffold(context)),
                  ),
                  trailing:
                      state is SleepTimerRunning &&
                          state.duration == Duration(minutes: minutes)
                      ? Icon(Icons.check, color: AppColors.accentOf(context))
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    ref
                        .read(sleepTimerProvider.notifier)
                        .startTimer(Duration(minutes: minutes));
                    showAppNotification(
                      '$minutes 分钟后停止播放',
                      type: AppNotificationType.success,
                    );
                  },
                ),
              if (state case SleepTimerRunning())
                ListTile(
                  leading: Icon(
                    Icons.timer_off_outlined,
                    color: AppColors.onScaffold(context),
                  ),
                  title: Text(
                    '取消睡眠定时',
                    style: TextStyle(color: AppColors.onScaffold(context)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(sleepTimerProvider.notifier).cancelTimer();
                  },
                ),
            ],
          );
        },
      ),
    ),
  );
}

/// 睡眠定时状态文案。
String sleepTimerSubtitle(SleepTimerState state) {
  if (state case SleepTimerRunning(:final scheduledEndTime)) {
    final remaining = scheduledEndTime.difference(DateTime.now());
    if (remaining <= Duration.zero) return '即将停止播放';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    if (minutes <= 0) return '$seconds 秒后停止播放';
    return '$minutes 分$seconds 秒后停止播放';
  }
  if (state case SleepTimerFailed()) return '上次停止播放失败';
  return '未开启';
}

/// 弹窗内每秒刷新倒计时，避免剩余时间停留在打开瞬间。
class _TickingSubtitle extends StatefulWidget {
  const _TickingSubtitle({required this.state});

  final SleepTimerState state;

  @override
  State<_TickingSubtitle> createState() => _TickingSubtitleState();
}

class _TickingSubtitleState extends State<_TickingSubtitle> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      sleepTimerSubtitle(widget.state),
      style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
    );
  }
}
