import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:koyze/core/theme/app_theme.dart';
import 'package:koyze/core/widgets/app_notification.dart';
import 'package:koyze/router/app_router.dart';
import 'package:koyze/features/settings/presentation/settings_provider.dart';
import 'package:koyze/features/player/presentation/player_provider.dart';
import 'package:koyze/features/stats/presentation/play_history_provider.dart';
import 'package:koyze/core/windows/windows_close_handler.dart';
import 'package:koyze/features/sync/presentation/cloud_sync_provider.dart';
import 'package:koyze/features/sync/presentation/sync_phase1_provider.dart';
import 'package:koyze/features/playlist/presentation/playlist_provider.dart';
import 'package:koyze/features/custom_source/presentation/custom_source_provider.dart';
import 'package:koyze/features/sync/presentation/startup_cloud_login_prompt.dart';

class PlayerMessageListener extends ConsumerStatefulWidget {
  const PlayerMessageListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlayerMessageListener> createState() =>
      _PlayerMessageListenerState();
}

class _PlayerMessageListenerState extends ConsumerState<PlayerMessageListener> {
  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(
      playerMessageProvider,
      (previous, next) => _deliver(next),
      fireImmediately: true,
    );
  }

  void _deliver(String? next) {
    if (next == null) return;
    final delivered = showAppNotification(
      next,
      type: AppNotificationType.error,
    );
    if (delivered && ref.read(playerMessageProvider) == next) {
      ref.read(playerMessageProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class LxMusicApp extends ConsumerWidget {
  const LxMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(playbackSessionRecorderProvider);
    ref.watch(recentPlayRecorderProvider);
    ref.watch(playHistoryRecorderProvider);
    ref.watch(ratingServiceProvider);
    // Attach every local sync target before the first Pull can run. Without
    // this, settings may sync while playlist/history/source events arrive
    // before their lazy providers are initialized.
    ref.watch(playlistServiceProvider);
    ref.watch(customSourceServiceProvider);

    return MaterialApp.router(
      title: 'Koyze',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: themeMode,
      themeAnimationDuration: const Duration(milliseconds: 300),
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: appRouter,
      builder: (context, child) => WindowsCloseHandler(
        navigatorKey: rootNavigatorKey,
        child: CloudSyncHost(
          child: AppNotificationHost(
            child: PlayerMessageListener(
              child: StartupCloudLoginPrompt(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CloudSyncHost extends ConsumerStatefulWidget {
  const CloudSyncHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CloudSyncHost> createState() => _CloudSyncHostState();
}

class _CloudSyncHostState extends ConsumerState<CloudSyncHost>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(cloudSyncProvider);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        ref.read(cloudSyncProvider.notifier).resumed();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sync = ref.read(cloudSyncProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      sync.resumed();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      sync.paused();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
