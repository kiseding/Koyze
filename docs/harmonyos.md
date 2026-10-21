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
   # 注意是 sdk 目录，不是 sdk/default：工具会扫描该目录下含 sdk-pkg.json
   # 的子目录（devEco 是 default），读里面的 data.apiVersion 来认版本。
   export HOS_SDK_HOME="<DevEco>/sdk"
   export PUB_HOSTED_URL=https://pub.flutter-io.cn
   # 国内建议用官方 CN 镜像，直连 googleapis 只有 20KB/s
   export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   ```

   **不要**把 `FLUTTER_STORAGE_BASE_URL` 设成鸿蒙 OBS 镜像
   （`flutter-ohos.obs...`）：它不托管上游工具本体，`engine_stamp.json` 会 404，
   `flutter --version` 报 `Unable to create dart snapshot for flutter tool`。

4. `flutter pub get` 需要跳过 git-lfs：TPC 移植仓库里带了 LFS 大文件
   （`audio_service/example/assets/video2.mp4`），本机没装 git-lfs 时 checkout 会失败：

   ```bash
   printf '[filter "lfs"]\n\tprocess =\n\tsmudge =\n\tclean =\n\trequired = false\n' \
     > /tmp/gitconfig_nolfs
   export GIT_CONFIG_GLOBAL="/tmp/gitconfig_nolfs"
   ```

   我们只需要 Dart / ArkTS 源码，跳过 smudge 不影响依赖内容。

5. 引擎工件：`bin/internal/dart-sdk-url.ohos` 里 11 个附件全部指向 atomgit Release。
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
「自动签名」即可；CI 上产出的就是**未签名 HAP**。

### 3.1 CI：只跑自建 runner

`.github/workflows/build-harmonyos.yml` 的 `runs-on` 是 `[self-hosted, harmonyos]`，
不用 GitHub 托管 runner，原因有三个：

1. HarmonyOS 命令行工具要登录华为开发者账号才能下载，托管 runner 里拿不到；
   把工具包塞进仓库又有许可问题。
2. 必须用 Flutter 鸿蒙 fork，而现有五个 workflow 用的 `subosito/flutter-action`
   装的是上游 Flutter，不认识 `ohos` 平台。
3. 引擎工件在 atomgit Release 上匿名 401。

自建机器需要：DevEco Studio（API 26）、鸿蒙 Flutter SDK、以及第 2 节那 11 个
引擎工件。可选仓库变量（Settings → Variables）：`FLUTTER_OHOS_HOME`、
`HOS_SDK_HOME`；不填则用 workflow 里的默认路径。

workflow 会在构建前检查 `default/sdk-pkg.json` 的 `apiVersion` 与引擎工件是否就位，
缺了直接给出可执行的报错，不会抛出一堆 hvigor 噪音。

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
      ref: br_just_audio-v0.9.41_ohos
  audio_service:
    # vendored 在仓库里，避开上游仓库的 git-lfs（见 third_party/audio_service_ohos/VENDORED.md）
    path: third_party/audio_service_ohos
  audio_session:
    git:
      url: https://gitcode.com/openharmony-sig/flutter_audio_session.git
      ref: br_v0.1.21_ohos
```

> **这套 override 只能出现在 `pubspec_ohos.yaml`，不能写进 `pubspec.yaml`。**
> 移植包的 Dart 代码直接引用了 `TargetPlatform.ohos`，这个枚举只在鸿蒙 Flutter
> fork 里存在；上游 Flutter（Android/iOS/桌面 CI 用的 3.44.9）会报
> `Member not found: 'ohos'`，测试与构建全挂。构建 HAP 前由
> `build-harmonyos.yml` 把 `pubspec_ohos.yaml` 复制为 `pubspec.yaml` 再执行
> `pub get`。

**`audio_session` 的 ref 不能留空**（默认 master 是 0.1.18，依赖
`rxdart >=0.26.0 <0.28.0`，与本项目的 `rxdart ^0.28.0` 冲突，pub 会直接
version solving failed）。`br_v0.1.21_ohos` 与 `br_v0.2.2_ohos` 的约束是
`>=0.26.0 <0.29.0`，都可用；本项目取 0.1.21（与原 `^0.1.25` 同一小版本线）。

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

## 6. 进度与缺口

已在分支 `ohos-audio-trial` 上验证：

| 步骤 | 结果 |
| --- | --- |
| `flutter pub get` | ✅ 通过，`just_audio 0.9.41` / `audio_service 0.18.18` / `audio_session 0.1.21` 均来自 git 移植（锁文件可见 `source: git`） |
| `flutter analyze` | ✅ 0 error / 0 warning（370 条 info 全是既有 lint，分布在 test 与 third_party） |
| Dart 侧改代码 | ✅ 不需要，`AudioService.init` / `AudioHandler` / `MediaItem` 接口一致 |

仍未完成：

1. **引擎工件下载**：atomgit Release 匿名 401，`flutter build hap` 还没跑过。
   需要登录 atomgit 手工取 11 个附件。
2. **运行时验证**：AVSession 播控、后台保活、通知都在 ArkTS 侧，必须真机/模拟器
   上跑一遍才算数；社区验证记录只到 API 26 模拟器与 ALN-AL00。
3. **版本风险**：移植的验证上限是 Flutter 3.35 + SDK 6.0.1（API 21），本项目是
   3.47.7 + API 26。`flutter analyze` 通过说明 API 面对得上，但运行时行为未知。
4. **签名与发布渠道**。
5. `audio_metadata_reader`（FFI）仍无 ohos 产物。
