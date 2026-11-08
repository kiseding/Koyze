// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'dart:async';

import 'package:flutter/services.dart';

import '../../features/lyric/domain/lyric.dart';
import '../logging/app_log.dart';
import '../storage/storage_service.dart';
import 'desktop_lyric_window_channel.dart';

final class DesktopLyricWindowController {
  DesktopLyricWindowController({
    required DesktopLyricWindowChannel channel,
    required StorageLoader storage,
    required Lyrics Function() lyrics,
    required Duration Function() position,
    required Future<void> Function(bool enabled) onEnabledChanged,
    required Future<void> Function(int fontSize) onFontSizeChanged,
    Duration refreshInterval = const Duration(milliseconds: 200),
  }) : _channel = channel,
       _storage = storage,
       _lyrics = lyrics,
       _position = position,
       _onEnabledChanged = onEnabledChanged,
       _onFontSizeChanged = onFontSizeChanged,
       _refreshInterval = refreshInterval;

  static const String _xKey = 'desktop_lyric_x';
  static const String _yKey = 'desktop_lyric_y';
  static const int minFontSize = 16;
  static const int maxFontSize = 72;
  static const int baseFontSize = 28;

  final DesktopLyricWindowChannel _channel;
  final StorageLoader _storage;
  final Lyrics Function() _lyrics;
  final Duration Function() _position;
  final Future<void> Function(bool enabled) _onEnabledChanged;
  final Future<void> Function(int fontSize) _onFontSizeChanged;
  final Duration _refreshInterval;

  Timer? _timer;
  bool _initialized = false;
  bool _disposed = false;
  bool _enabled = false;
  bool _locked = false;
  int _fontSize = baseFontSize;
  int? _x;
  int? _y;
  int? _lastFontSize;
  String? _lastCurrent;
  String? _lastNext;
  Future<void> _tail = Future<void>.value();

  Future<void> init({
    required bool enabled,
    required bool locked,
    required int fontSize,
  }) async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _locked = locked;
    _fontSize = fontSize.clamp(minFontSize, maxFontSize);
    _lastFontSize = null;
    _channel.setEventHandler(_handleEvent);
    await _serialize(() async {
      try {
        final storage = await _storage();
        _x = storage.getInt(_xKey);
        _y = storage.getInt(_yKey);
      } on Object catch (error) {
        AppLog.instance.record(
          'desktop.lyric',
          'position restore failed: $error',
          level: AppLogLevel.warning,
        );
      }
      await _setEnabled(enabled);
    });
  }

  Future<void> setEnabled(bool enabled) =>
      _serialize(() => _setEnabled(enabled));

  Future<void> _setEnabled(bool enabled) async {
    if (_disposed || !_initialized || _enabled == enabled) return;
    _enabled = enabled;
    _timer?.cancel();
    _timer = null;
    if (!enabled) {
      await _invokeQuietly('hide');
      _lastCurrent = null;
      _lastNext = null;
      _lastFontSize = null;
      _lastLocked = null;
      return;
    }
    final args = <String, Object?>{};
    if (_x != null && _y != null) {
      args['x'] = _x;
      args['y'] = _y;
    }
    await _invokeQuietly('show', args);
    await _pushStyle();
    await _syncLyrics();
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  Future<void> updateStyle({required bool locked, required int fontSize}) =>
      _serialize(() async {
        if (_disposed) return;
        _locked = locked;
        _fontSize = fontSize.clamp(minFontSize, maxFontSize);
        if (_enabled) await _pushStyle();
      });

  Future<void> refresh() => _serialize(_syncLyrics);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _channel.setEventHandler(null);
    await _serialize(() => _invokeQuietly('hide'), allowDisposed: true);
  }

  Future<void> _serialize(
    Future<void> Function() action, {
    bool allowDisposed = false,
  }) {
    final next = _tail.then((_) async {
      if (!_disposed || allowDisposed) await action();
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _syncLyrics() async {
    if (!_enabled || _disposed) return;
    final lyrics = _lyrics();
    final index = lyrics.getCurrentLineIndex(_position());
    final current = index >= 0 && index < lyrics.lines.length
        ? lyrics.lines[index].text
        : '';
    final next = index >= 0 && index + 1 < lyrics.lines.length
        ? lyrics.lines[index + 1].text
        : '';
    if (current == _lastCurrent && next == _lastNext) return;
    _lastCurrent = current;
    _lastNext = next;
    await _invokeQuietly('update', {'current': current, 'next': next});
  }

  Future<void> _pushStyle() async {
    if (!_enabled || _disposed) return;
    final fontSize = _fontSize;
    if (_lastFontSize == fontSize && _locked == _lastLocked) return;
    _lastFontSize = fontSize;
    _lastLocked = _locked;
    await _invokeQuietly('setStyle', {
      'fontSize': fontSize,
      'opacity': 0.9,
      'locked': _locked,
    });
  }

  bool? _lastLocked;

  void _handleEvent(String event, Map<Object?, Object?> payload) {
    if (_disposed) return;
    switch (event) {
      case 'position':
        final x = _integer(payload['x']);
        final y = _integer(payload['y']);
        if (x == null || y == null) return;
        _x = x;
        _y = y;
        unawaited(_persistPosition(x, y));
      case 'style':
        final fontSize = _integer(payload['fontSize']);
        if (fontSize == null) return;
        _fontSize = fontSize.clamp(minFontSize, maxFontSize);
        _lastFontSize = _fontSize;
        unawaited(_onFontSizeChanged(_fontSize));
      case 'closed':
        if (_enabled) unawaited(_onEnabledChanged(false));
    }
  }

  Future<void> _persistPosition(int x, int y) async {
    try {
      final storage = await _storage();
      await storage.setInt(_xKey, x);
      await storage.setInt(_yKey, y);
    } on Object catch (error) {
      AppLog.instance.record(
        'desktop.lyric',
        'position save failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }

  static int? _integer(Object? value) => switch (value) {
    int v => v,
    double v => v.round(),
    _ => null,
  };

  Future<void> _invokeQuietly(String method, [Object? arguments]) async {
    try {
      await _channel.invoke(method, arguments);
    } on MissingPluginException {
      _timer?.cancel();
      _timer = null;
    } on Object catch (error) {
      AppLog.instance.record(
        'desktop.lyric',
        '$method failed: $error',
        level: AppLogLevel.warning,
      );
    }
  }
}
