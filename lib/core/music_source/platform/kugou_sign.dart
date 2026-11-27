import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// 酷狗网关的请求签名。
///
/// 规则是把参数按名排序后拼成 `k=v` 串，前后各套一次密钥再取 md5：
/// `md5(key + joined + body + key)`。登录、取歌单、取歌单曲目都要用同一份
/// 算法，抽在这里免得几处各写一遍后悄悄跑偏。
String kugouSign(String key, Map<String, String> params, [String body = '']) {
  final keys = params.keys.where((name) => name != 'signature').toList()
    ..sort();
  final joined = keys.map((name) => '$name=${params[name]}').join();
  return md5.convert(utf8.encode('$key$joined$body$key')).toString();
}

/// 未注册设备用的 mid。
///
/// 酷狗只要求这一串在同一会话里稳定，不要求真机注册；随机 md5 就够用。
String kugouDeviceMid() {
  final seed =
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextDouble()}';
  return md5.convert(utf8.encode(seed)).toString();
}
