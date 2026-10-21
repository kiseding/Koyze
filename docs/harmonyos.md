# 鸿蒙（HarmonyOS 7.0 / API 26）构建说明

本文档记录 Koyze 的鸿蒙平台接入方式、工具链版本与插件适配现状。

> 状态：**工程骨架已接入，构建链路未打通**。`ohos/` 目录按 Flutter
> 3.47.7-ohos 的官方应用模板生成，目标 SDK 为 API 26（HarmonyOS 7.0）。
> 音频链路的鸿蒙实现**已有现成方案**（见第 4 节），但版本尚未对齐到 3.47/API 26。

## 1. 版本矩阵

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | `3.47.7-ohos-1.0.0` | 上游 3.47.7 + 鸿蒙适配，Dart 3.13.3 |
| DevEco Studio | `26.0.0` | 自带 HarmonyOS SDK 26.0.0（API 26） |
| compatibleSdkVersion | `26.0.0` | `ohos/build-profile.json5` |
| targetSdkVersion | `26.0.0` | 同上 |
| bundleName | `com.koyze.app` | 与 Android applicationId、iOS bundle id 一致 |

上游 `openharmony-sig/flutter_flutter` 已停更（最后提交 2025-02，最高 3.22），
现行仓库是 <https://atomgit.com/oh-flutter/flutter_flutter>，3.47 之后按上游版本列车跟进。

## 2. 环境准备（Windows）

1. 安装 DevEco Studio 26.0.0，记下 SDK 路径（默认 `<DevEco>/sdk/default`，
   内含 `openharmony/` 与 `hms/`）。
2. 拉取鸿蒙 Flutter SDK（本体约 540MB，建议放非系统盘）：

   ```bash
   git clone --depth 1 -b 3.47.7-ohos-1.0.0 \
     https://atomgit.com/oh-flutter/flutter_flutter.git flutter_ohos
   export PATH="$PWD/flutter_ohos/bin:$PATH"
   ```

3. 环境变量：

   ```bash
   export HOS_SDK_HOME="<DevEco>/sdk/default"
   export PUB_HOSTED_URL=https://pub.flutter-io.cn   # 可选，加速 pub
   ```

   **不要设置** `FLUTTER_STORAGE_BASE_URL`。设成鸿蒙 OBS 镜像会让
   `engine_stamp.json` 404（该镜像不托管上游工具本体），`flutter --version`
   报 `Unable to create dart snapshot for flutter tool`。默认官方源可用时留空。

4. 引擎工件：`bin/internal/dart-sdk-url.ohos` 里 11 个附件全部指向 atomgit Release。
   这些附件**匿名下载返回 401**，需要登录 atomgit 后从
   <https://atomgit.com/oh-flutter/flutter_flutter/releases/tag/3.47.7-ohos-1.0.0>
   手工下载并放进 `flutter_ohos/bin/cache/`。

## 3. 构建

```bash
flutter pub get
flutter build hap --debug --target-platform ohos-arm64
flutter build hap --release --target-platform ohos-arm64
```

产物在 `ohos/entry/build/default/outputs/default/`，用 `hdc install <hap>` 安装。
签名：`ohos/build-profile.json5` 的 `signingConfigs` 为空，本地用 DevEco 的
「自动签名」即可；CI 需要单独证书，因此仓库暂未添加鸿蒙构建工作流
（GitHub 托管 runner 也没有 HarmonyOS SDK 与许可）。

## 4. 插件适配

鸿蒙侧有三套来源：pub 上的 `*_harmonyos` / `*_ohos` 包、gitcode 上的 TPC
移植仓库、以及确实没有实现的。

### 4.1 pub 上直接可用

| 依赖 | 鸿蒙包 |
| --- | --- |
| `shared_preferences` | `shared_preferences_harmonyos` |
| `path_provider` | `path_provider_harmonyos` |
| `connectivity_plus` | `connectivity_plus_harmonyos` |
| `permission_handler` | `permission_handler_ohos` |
| `file_picker` | `file_picker_ohos` |
| `flutter_secure_storage` | `flutter_secure_storage_ohos` |
| `flutter_js` | `flutter_js_ohos` |

`*_harmonyos` 系列普遍是 `0.0.1`、2025-08 ~ 2025-11 发布，SDK 约束
`>=3.6.2 <4.0.0`，可用但版本号还在早期。

### 4.2 音频链路（gitcode TPC 移植，用 dependency_overrides 覆盖）

`just_audio` / `audio_service` / `audio_session` 在 pub 上的官方包都没有
ohos 实现，但社区 TPC 仓库提供了完整移植，做法是**整体覆盖原包**而不是新增
独立包：

```yaml
dependency_overrides:
  just_audio:
    git:
      url: https://gitcode.com/openharmony-sig/fluttertpc_just_audio.git
      path: just_audio
  audio_service:
    git:
      url: https://gitcode.com/openharmony-sig/fluttertpc_audio_service.git
      path: audio_service
  audio_session:
    git:
      url: https://gitcode.com/openharmony-sig/flutter_audio_session.git
```

分支按上游版本选择：

| 上游 | just_audio 移植 | audio_service 移植 |
| --- | --- | --- |
| 0.9.37 | `br_0.9.37_ohos` | — |
| 0.9.41 | `br_just_audio-v0.9.41_ohos` | — |
| 0.10.4 / 0.10.5 | `br_v0.10.4_ohos` / `br_v0.10.5_ohos` | — |
| audio_service 0.18.18 | — | `br_v0.18.18_ohos` |
| Flutter 3.41+ | `br_3.41_dev` | `br_3.41_dev`（0.18.19） |

`audio_service` 的鸿蒙实现（`ohos/src/main/ets/AudioService.ets`，588 行）用的是：

- `@kit.AVSessionKit`：`createAVSession` + `setAVMetadata` + `activate`，
  并监听 `play` / `pause` / `stop` / `playNext` / `playPrevious` /
  `fastForward` / `rewind` —— 这就是 MediaSession 的等价物，锁屏与播控中心都走它。
- `@kit.BackgroundTasksKit`：`startBackgroundRunning(..., AUDIO_PLAYBACK)`，
  对应后台播放。
- `@kit.AbilityKit` 的 `WantAgent`：通知点击回到 App。
- `pubspec.yaml` 里已声明 `ohos: pluginClass: AudioServicePlugin`，属于可插拔的
  平台实现。

Dart 侧无需改：`AudioService.init` / `BaseAudioHandler` / `MediaItem` /
`PlaybackState` 的 API 与 0.18.17 一致。

### 4.3 仍然没有鸿蒙实现

| 依赖 | 现状 | 处理 |
| --- | --- | --- |
| `audio_metadata_reader` | 依赖 dart:ffi 读本地音频标签，无 ohos ABI 产物 | 鸿蒙侧暂不读本地元数据，或自行交叉编译 |
| `just_audio_windows` / `home_widget` / `live_activities` / `flutter_app_group_directory` | 桌面 / iOS 专用 | HAP 构建时自然跳过，不影响打包 |

## 5. 可以参考的开源实现

| 仓库 | 做法 |
| --- | --- |
| `Aloereed/aloeplayer_ohos` | 同时 override `just_audio` 与 `audio_service`，是当前最完整的 Flutter 鸿蒙播放器参考 |
| `bmbxwbh/fu_sheng_music_ohos` | 只用 `just_audio_harmonyos`，没有接 audio_service，等于只有前台播放 |
| `AnmSleepalone/bujuan-harmony` | `pubspec.lock` 内含 `fluttertpc_audio_service` |

## 6. 尚未完成 / 风险

1. **引擎工件下载**：atomgit Release 匿名 401，本机尚未跑通 `flutter build hap`。
2. **版本对齐**：TPC 移植的验证上限是 Flutter 3.35 + SDK 6.0.1（API 21），
   本项目是 3.47.7 + API 26，需要实测；优先试 `br_3.41_dev`。
3. **签名与发布渠道**。
4. **真机矩阵**：社区目前只在 API 26 模拟器与 ALN-AL00 上有验证记录。
