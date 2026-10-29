import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import 'app_notification.dart';
import '../../features/player/presentation/player_provider.dart';
import '../../l10n/app_strings.dart';
import '../../../core/widgets/koyze_sheet.dart';

/// 睡眠定时弹窗（设置页与首页快捷入口共用）。
///
/// 和选项面板同一套排版：把手 + 大标题 + 关闭键 + 图标块行，倒计时直接
/// 挂在标题下面，运行时多一行"取消定时"。
void showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  showKoyzeSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(sleepTimerProvider);
        final s = S.of(context);
        final accent = AppColors.accentOf(context);
        final running = state is SleepTimerRunning;
        final untilTrackEnd = state is SleepTimerUntilTrackEnd;
        final fadeOut = ref.watch(sleepTimerFadeProvider);
        const options = [10, 15, 30, 60, 90];
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const KoyzeSheetGrabber(),
              KoyzeSheetTitle(
                title: s.sleepTimer,
                subtitleWidget: running ? _TickingSubtitle(state: state) : null,
                subtitle: running
                    ? null
                    : sleepTimerSubtitle(
                        state,
                        locale: Localizations.localeOf(context),
                      ),
                onClose: () => Navigator.pop(context),
              ),
              KoyzeSheetAction(
                icon: Icons.music_note_rounded,
                label: s.untilTrackEnd,
                trailing: untilTrackEnd
                    ? Icon(Icons.check_rounded, size: 20, color: accent)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(sleepTimerProvider.notifier)
                      .startUntilTrackEnd(fadeOut: fadeOut);
                  showAppNotification(
                    s.untilTrackEndNote,
                    type: AppNotificationType.success,
                  );
                },
              ),
              for (final minutes in options)
                KoyzeSheetAction(
                  icon: Icons.timer_outlined,
                  label: s.minutes(minutes),
                  trailing:
                      state is SleepTimerRunning &&
                          state.duration == Duration(minutes: minutes)
                      ? Icon(Icons.check_rounded, size: 20, color: accent)
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    ref
                        .read(sleepTimerProvider.notifier)
                        .startTimer(
                          Duration(minutes: minutes),
                          fadeOut: fadeOut,
                        );
                    showAppNotification(
                      s.stopsInMinutes(minutes),
                      type: AppNotificationType.success,
                    );
                  },
                ),
              SwitchListTile.adaptive(
                dense: true,
                value: fadeOut,
                onChanged: (value) =>
                    ref.read(sleepTimerFadeProvider.notifier).state = value,
                title: Text(
                  s.fadeOutBeforeStop,
                  style: TextStyle(
                    color: AppColors.onScaffold(context),
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  s.fadeOutBeforeStopHint,
                  style: TextStyle(
                    color: AppColors.mutedText(context),
                    fontSize: 12,
                  ),
                ),
              ),
              if (running || untilTrackEnd)
                KoyzeSheetAction(
                  icon: Icons.timer_off_outlined,
                  label: s.cancelSleepTimer,
                  danger: true,
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(sleepTimerProvider.notifier).cancelTimer();
                  },
                ),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    ),
  );
}

/// 睡眠定时状态文案。
String sleepTimerSubtitle(SleepTimerState state, {Locale? locale}) {
  final en = locale?.languageCode == 'en';
  if (state case SleepTimerRunning(:final scheduledEndTime)) {
    final remaining = scheduledEndTime.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return en ? 'Stopping soon' : '即将停止播放';
    }
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds.remainder(60);
    if (minutes <= 0) {
      return en ? 'Stops in $seconds s' : '$seconds 秒后停止播放';
    }
    return en
        ? 'Stops in ${minutes}m ${seconds}s'
        : '$minutes 分$seconds 秒后停止播放';
  }
  if (state is SleepTimerUntilTrackEnd) {
    return en ? 'Stops after this track' : '播完当前歌曲后停止';
  }
  if (state case SleepTimerFailed()) {
    return en ? 'Last stop failed' : '上次停止播放失败';
  }
  return en ? 'Off' : '未开启';
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
      sleepTimerSubtitle(widget.state, locale: Localizations.localeOf(context)),
      style: TextStyle(color: AppColors.mutedText(context), fontSize: 12),
    );
  }
}
