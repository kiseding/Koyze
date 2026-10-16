import 'dart:io';

import 'package:flutter/services.dart';

class AndroidDirectoryAccess {
  static const _channel = MethodChannel('koyze/android_file_access');

  static Future<String?> select() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('selectDirectory');
  }

  static Future<List<Map<String, dynamic>>> scanMediaStore() async {
    if (!Platform.isAndroid) return const [];
    return _invokeTrackList('scanMediaStore');
  }

  static Future<List<Map<String, dynamic>>> scanSelectedDirectory() async {
    if (!Platform.isAndroid) return const [];
    return _invokeTrackList('scanSelectedDirectory');
  }

  static Future<String?> externalStorageRoot() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('externalStorageRoot');
  }

  static Future<bool> isExternalStorageManager() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isExternalStorageManager') ??
        false;
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>(
          'isIgnoringBatteryOptimizations',
        ) ??
        false;
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  static Future<Map<String, dynamic>?> pendingImportedAudio() async {
    if (!Platform.isAndroid) return null;
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pendingImportedAudio',
    );
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  static Future<List<Map<String, dynamic>>> _invokeTrackList(
    String method,
  ) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(method);
    return (raw ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }
}
