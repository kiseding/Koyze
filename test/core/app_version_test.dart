import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koyze/core/app_version.dart';

/// 版本号散落在四处：Dart 常量、pubspec、鸿蒙 pubspec、app.json5。
/// 发版时漏改任意一处，产物里的版本就会互相打架（比如设置页显示 4.1.0
/// 但 HAP 的 versionCode 还是旧的），这里把它们钉在一起。
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// 从 `version: 4.1.0+410` 里取出版本名与构建号。
  (String, int) parsePubspecVersion(String yaml) {
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(yaml);
    expect(match, isNotNull, reason: 'pubspec 缺少 version: x.y.z+build');
    return (match!.group(1)!, int.parse(match.group(2)!));
  }

  test('Dart 常量与 pubspec.yaml 一致', () {
    final (name, build) = parsePubspecVersion(read('pubspec.yaml'));
    expect(kAppVersion, name);
    expect(build, greaterThan(0));
  });

  test('鸿蒙 pubspec 与主 pubspec 一致', () {
    final (main, mainBuild) = parsePubspecVersion(read('pubspec.yaml'));
    final (ohos, ohosBuild) = parsePubspecVersion(read('pubspec_ohos.yaml'));
    expect(ohos, main);
    expect(ohosBuild, mainBuild);
  });

  test('app.json5 的 versionName 与 versionCode 同步', () {
    final json5 = read('ohos/AppScope/app.json5');
    final (name, _) = parsePubspecVersion(read('pubspec.yaml'));

    final nameMatch = RegExp(r'"versionName":\s*"([^"]+)"').firstMatch(json5);
    final codeMatch = RegExp(r'"versionCode":\s*([0-9]+)').firstMatch(json5);
    expect(nameMatch?[1], name);
    expect(codeMatch, isNotNull);

    // versionCode 编码为 major*1e6 + minor*1e3 + patch，必须是递增的整数，
    // 且与 versionName 语义对应，否则鸿蒙侧会拒绝升级安装。
    final parts = name.split('.').map(int.parse).toList();
    final expectedCode = parts[0] * 1000000 + parts[1] * 1000 + parts[2];
    expect(int.parse(codeMatch![1]!), expectedCode);
  });

  test('展示用版本号带 v 前缀', () {
    expect(kAppVersionLabel, 'v$kAppVersion');
  });
}
