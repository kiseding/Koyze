import 'dart:io';

import 'package:flutter/services.dart';

class SecurityScopedDirectory {
  static const _channel = MethodChannel('koyze/security_scoped_directory');

  static Future<String?> select() async {
    if (!Platform.isIOS) return null;
    return _channel.invokeMethod<String>('selectDirectory');
  }

  static Future<List<String>> restore() async {
    if (!Platform.isIOS) return const [];
    final paths = await _channel.invokeMethod<List<dynamic>>(
      'restoreDirectories',
    );
    return paths?.whereType<String>().toList(growable: false) ?? const [];
  }
}
