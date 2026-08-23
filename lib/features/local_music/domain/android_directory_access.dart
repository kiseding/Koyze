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
