import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyric/presentation/lyric_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../presentation/player_provider.dart';

const androidFloatingPlayerChannel = MethodChannel('koyze/floating_player');

bool get androidFloatingPlayerSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool floatingPlayerFollowsDarkTheme({
  required ThemeMode mode,
  required Brightness platformBrightness,
}) {
  return switch (mode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => platformBrightness == Brightness.dark,
  };
}

bool shouldShowAndroidFloatingPlayer({
  required bool enabled,
  required bool permissionGranted,
  required bool inBackground,
  required bool hasTrack,
  required bool dismissed,
}) {
  return enabled && permissionGranted && inBackground && hasTrack && !dismissed;
}

class AndroidFloatingPlayer {
  const AndroidFloatingPlayer();

  static bool permissionRequested = false;

  Future<bool> canDrawOverlays() async {
    if (!androidFloatingPlayerSupported) return false;
    final allowed = await androidFloatingPlayerChannel.invokeMethod<bool>(
      'canDrawOverlays',
    );
    return allowed ?? false;
  }

  Future<void> requestPermission() async {
    if (!androidFloatingPlayerSupported) return;
    permissionRequested = true;
    await androidFloatingPlayerChannel.invokeMethod<void>('requestPermission');
  }

  Future<bool> show() async {
    if (!androidFloatingPlayerSupported) return false;
    final shown = await androidFloatingPlayerChannel.invokeMethod<bool>('show');
    return shown ?? false;
  }

  Future<void> hide() async {
    if (!androidFloatingPlayerSupported) return;
    await androidFloatingPlayerChannel.invokeMethod<void>('hide');
  }

  Future<void> update(Map<String, Object?> payload) async {
    if (!androidFloatingPlayerSupported) return;
    await androidFloatingPlayerChannel.invokeMethod<void>('update', payload);
  }

  void bind(Future<void> Function(String action) onAction) {
    if (!androidFloatingPlayerSupported) return;
    androidFloatingPlayerChannel.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      final action = call.arguments;
      if (action is String) await onAction(action);
    });
  }
}

class AndroidFloatingPlayerHost extends ConsumerStatefulWidget {
  const AndroidFloatingPlayerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AndroidFloatingPlayerHost> createState() =>
      _AndroidFloatingPlayerHostState();
}

class _AndroidFloatingPlayerHostState
    extends ConsumerState<AndroidFloatingPlayerHost>
    with WidgetsBindingObserver {
  final AndroidFloatingPlayer _player = const AndroidFloatingPlayer();
  bool _backgrounded = false;
  bool _dismissed = false;
  bool _visible = false;
  bool _syncing = false;
  bool _syncQueued = false;
  DateTime? _lastProgressPush;
  int? _lastPositionMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!androidFloatingPlayerSupported) return;
    _player.bind(_onAction);
    ref.listenManual(androidFloatingPlayerProvider, (_, _) => _sync());
    ref.listenManual(currentMusicProvider, (_, _) => _sync(immediate: true));
    ref.listenManual(currentLyricProvider, (_, _) => _sync(immediate: true));
    ref.listenManual(
      currentLineIndexProvider,
      (_, _) => _sync(immediate: true),
    );
    ref.listenManual(playerPositionProvider, (_, _) => _sync());
    ref.listenManual(durationProvider, (_, _) => _sync());
    ref.listenManual(playbackStateProvider, (_, _) => _sync(immediate: true));
    ref.listenManual(themeModeProvider, (_, _) => _sync(immediate: true));
  }

  @override
  void didChangePlatformBrightness() {
    _sync(immediate: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!androidFloatingPlayerSupported) return;
    final backgrounded =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      _dismissed = false;
      unawaited(_completePermissionRequest());
    } else if (backgrounded) {
      _backgrounded = true;
    }
    _sync(immediate: true);
  }

  Future<void> _completePermissionRequest() async {
    if (!AndroidFloatingPlayer.permissionRequested) return;
    AndroidFloatingPlayer.permissionRequested = false;
    if (!await _player.canDrawOverlays()) return;
    await ref.read(androidFloatingPlayerProvider.notifier).setEnabled(true);
  }

  Future<void> _onAction(String action) async {
    final service = ref.read(playerServiceProvider);
    switch (action) {
      case 'previous':
        await service.previous();
      case 'next':
        await service.next();
      case 'toggle':
        await service.togglePlay();
      case 'dismiss':
        _dismissed = true;
        _sync(immediate: true);
      case 'open':
        break;
    }
  }

  void _sync({bool immediate = false}) {
    if (!androidFloatingPlayerSupported || !mounted) return;
    final positionMs = ref.read(playerPositionProvider).inMilliseconds;
    final now = DateTime.now();
    final progressDue =
        _lastProgressPush == null ||
        now.difference(_lastProgressPush!) >=
            const Duration(milliseconds: 250) ||
        _lastPositionMs == null ||
        (positionMs - _lastPositionMs!).abs() >= 1000;
    if (!immediate && !progressDue) return;
    _syncQueued = true;
    if (_syncing) return;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    _syncing = true;
    try {
      while (_syncQueued && mounted) {
        _syncQueued = false;
        await _push();
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final enabled = ref.read(androidFloatingPlayerProvider);
    final music = ref.read(currentMusicProvider);
    final allowed = enabled ? await _player.canDrawOverlays() : false;
    final show = shouldShowAndroidFloatingPlayer(
      enabled: enabled,
      permissionGranted: allowed,
      inBackground: _backgrounded,
      hasTrack: music != null,
      dismissed: _dismissed,
    );
    if (!show) {
      if (_visible) {
        _visible = false;
        await _player.hide();
      }
      return;
    }
    if (!_visible) {
      _visible = await _player.show();
      if (!_visible) return;
    }
    final lyrics = ref.read(currentLyricProvider);
    final lineIndex = ref.read(currentLineIndexProvider);
    final line = lineIndex >= 0 && lineIndex < lyrics.lines.length
        ? lyrics.lines[lineIndex].text
        : '';
    final position = ref.read(playerPositionProvider);
    final duration = ref.read(durationProvider).value ?? music!.duration;
    final playing = ref.read(playbackStateProvider).value?.playing ?? false;
    _lastProgressPush = DateTime.now();
    _lastPositionMs = position.inMilliseconds;
    await _player.update({
      'title': '${music!.name} · ${music.singer}',
      'lyric': line,
      'positionMs': position.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'playing': playing,
      'artwork': music.artwork ?? '',
      'dark': floatingPlayerFollowsDarkTheme(
        mode: ref.read(themeModeProvider),
        platformBrightness: MediaQuery.platformBrightnessOf(context),
      ),
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
