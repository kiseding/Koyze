import 'dart:io';

import 'package:flutter/services.dart';

class AndroidDirectoryAccess {
  static const _channel = MethodChannel('koyze/android_file_access');

  static Future<String?> select() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('selectDirectory');
  }
}
