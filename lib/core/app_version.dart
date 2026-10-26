// Copyright 2024 Koyze Contributors
// Licensed under the Apache License, Version 2.0

/// 应用版本号的唯一来源。
///
/// 发布新版本时只需要改这里（以及 `pubspec.yaml` / `pubspec_ohos.yaml` 的
/// `version:` 和 `ohos/AppScope/app.json5` 的 `versionCode`、`versionName`；
/// 那几处由构建系统读取，Dart 侧不会有其它副本）。
///
/// 之前设置页和 NAS 客户端各自硬编码了一份字符串，发版时容易漏掉其中一处，
/// 界面上就会出现「设置页显示 v4.1.0、Plex 上报 4.0.3」这种不一致。
const String kAppVersion = '4.1.1';

/// 带 `v` 前缀的展示用版本号。
const String kAppVersionLabel = 'v$kAppVersion';
