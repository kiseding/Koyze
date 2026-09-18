import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Subsonic REST 鉴权。独立实现，遵循官方 API 1.13+ token 规范。
///
/// 默认 token：`t = md5(password + salt)`，`s = salt`。
/// 旧服可改用明文 `p`（legacy）。
const subsonicApiVersion = '1.16.1';
const subsonicClientName = 'Koyze';

Map<String, String> subsonicAuthParams({
  required String username,
  required String password,
  bool legacy = false,
  String? salt,
  String Function()? saltGenerator,
}) {
  final params = <String, String>{
    'u': username,
    'v': subsonicApiVersion,
    'c': subsonicClientName,
    'f': 'json',
  };
  if (legacy) {
    params['p'] = password;
    return params;
  }
  final resolvedSalt = (salt == null || salt.isEmpty)
      ? (saltGenerator ?? generateSubsonicSalt)()
      : salt;
  params['t'] = md5
      .convert(utf8.encode('$password$resolvedSalt'))
      .toString();
  params['s'] = resolvedSalt;
  return params;
}

String generateSubsonicSalt([Random? random]) {
  final rng = random ?? Random.secure();
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(12, (_) => alphabet[rng.nextInt(alphabet.length)])
      .join();
}

String encodeSubsonicQuery(Map<String, String> params) {
  return params.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}
