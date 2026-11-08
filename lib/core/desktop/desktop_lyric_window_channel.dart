// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

import 'package:flutter/services.dart';

const String kDesktopLyricWindowChannelName = 'koyze/desktop_lyric';

typedef DesktopLyricWindowEventHandler =
    void Function(String event, Map<Object?, Object?> payload);

abstract interface class DesktopLyricWindowChannel {
  Future<void> invoke(String method, [Object? arguments]);
  void setEventHandler(DesktopLyricWindowEventHandler? handler);
}

final class MethodChannelDesktopLyricWindowChannel
    implements DesktopLyricWindowChannel {
  MethodChannelDesktopLyricWindowChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kDesktopLyricWindowChannelName);

  final MethodChannel _channel;
  DesktopLyricWindowEventHandler? _handler;
  bool _listening = false;

  @override
  Future<void> invoke(String method, [Object? arguments]) =>
      _channel.invokeMethod<void>(method, arguments);

  @override
  void setEventHandler(DesktopLyricWindowEventHandler? handler) {
    _handler = handler;
    if (handler != null) {
      if (_listening) return;
      _channel.setMethodCallHandler(_dispatch);
      _listening = true;
    } else if (_listening) {
      _channel.setMethodCallHandler(null);
      _listening = false;
    }
  }

  Future<Object?> _dispatch(MethodCall call) async {
    if (call.method != 'event') return null;
    final value = call.arguments;
    if (value is! Map) return null;
    final event = value['event'];
    final payload = value['payload'];
    _handler?.call(
      event is String ? event : '',
      payload is Map ? payload.cast<Object?, Object?>() : const {},
    );
    return null;
  }
}
