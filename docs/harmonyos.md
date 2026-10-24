# 鸿蒙（HarmonyOS 7.0 / API 26）构建说明

本文档记录 Koyze 的鸿蒙平台接入方式、工具链版本与插件适配现状。

> 状态：**HarmonyOS 双架构构建流程已接入，云端签名与实机安装仍待凭据和设备验证**。
> `ohos/` 目录基于 Flutter 3.47.7-ohos，目标 SDK 为 API 26（HarmonyOS 7.0）。
> 音频链路使用现有鸿蒙移植方案（见第 4 节），运行时仍需持续进行真机回归。

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

5. 引擎工件：在线 workflow 会把 `bin/internal/dart-sdk-url.ohos` 中的六套
   `flutter.har` 和四套 Windows `gen_snapshot` 覆盖到 HarmonyOS OBS 的对应版本目录，
   再执行 `precache --ohos` 并逐项校验。定制 Dart/patch SDK 仍按 fork 配置下载。
   self-hosted runner 需要预先准备相同版本的 Flutter 鸿蒙 SDK 和缓存工件；缺少任一
   架构或宿主机工件时，workflow 会在构建前失败。工作流还会运行 `gen_snapshot --version`
   校验：arm64 必须使用 Dart 版本一致的 ARM64 目标工件；若 x64 OBS 工件版本过旧，则自动
   改用同一 Dart SDK 自带的 Windows x64 `gen_snapshot`，避免 `expected 130, found 138`。

## 3. 构建

```bash
flutter pub get
flutter build hap --debug --no-codesign --target-platform ohos-arm64
flutter build hap --debug --no-codesign --target-platform ohos-x64
flutter build hap --release --no-codesign --target-platform ohos-arm64
flutter build hap --release --no-codesign --target-platform ohos-x64
```

`ohos-arm64` 是 ARM64 鸿蒙真机，`ohos-x64` 是 x86_64 鸿蒙模拟器。单次
`flutter build hap` 只生成一个架构，CI 像 Android 的 split-per-ABI 一样分别构建，
并将产物命名为：

```text
Koyze-4.0.1-ohos-arm64.hap
Koyze-4.0.1-ohos-x64.hap
```

产物在 `ohos/entry/build/default/outputs/default/`，用 `hdc install <hap>` 安装。
本地调试包可以是 unsigned HAP；要让下载后的 release HAP 直接安装到实机，必须用
发布证书和可在目标设备安装的 release profile 签名。签名脚本为
`scripts/ohos/sign-hap.sh`，签名后的文件名不含 `-unsigned`。

### 3.1 GitHub Actions 双架构发布

`.github/workflows/build-harmonyos-online.yml`（托管 Windows runner）和
`.github/workflows/build-harmonyos.yml`（self-hosted runner）都会分别构建：

| 产物 | 目标 | 用途 |
| --- | --- | --- |
| `Koyze-<version>-ohos-arm64.hap` | `ohos-arm64` | 鸿蒙 ARM64 真机 |
| `Koyze-<version>-ohos-x64.hap` | `ohos-x64` | 鸿蒙 x86_64 模拟器 |

release 构建要求以下仓库 Secrets 全部存在，缺少任意一个都会失败，不会上传无法
安装的 unsigned HAP；`SIGN_STORE_PWD` 为空时才回退使用 `SIGN_KEY_PWD`：

```text
SIGN_KEYSTORE_B64  # koyze.p12 的 base64
SIGN_CERT_B64      # 发布证书链 .cer 的 base64
SIGN_PROFILE_B64   # 可安装 release profile .p7b 的 base64
SIGN_KEY_PWD       # 私钥密码
SIGN_STORE_PWD     # 密钥库密码；留空时使用 SIGN_KEY_PWD
```

`SIGN_PROFILE_B64` 应对应发布证书，并且不能限制到另一台设备；否则 HAP 虽然签名
校验通过，仍会被目标设备拒绝。工作流还上传 `SHA256SUMS.txt`。下载 Artifact 或
Release 中的对应架构 HAP 后，开发者模式和 HDC 连接正常时可以直接执行：

```bash
hdc install Koyze-4.0.1-ohos-arm64.hap
# x86_64 模拟器使用：
# hdc install Koyze-4.0.1-ohos-x64.hap
```

### 3.2 CI：self-hosted 变体

`.github/workflows/build-harmonyos.yml` 仅用于带有 `self-hosted`、`harmonyos`、
`Windows`、`X64` 标签的自建 runner。当前 fork 配置的定制 Dart SDK 没有 Linux x64
及 macOS x64 工件，因此工作流固定为 Windows x64；在线构建优先使用上一节的
`build-harmonyos-online.yml`。

自建机器需要：DevEco Studio（API 26）、鸿蒙 Flutter SDK，以及该 SDK 对应的
arm64/x64 debug、profile、release HAR 与 Windows profile/release AOT 工件。仓库变量
（Settings → Variables）可配置 `FLUTTER_OHOS_HOME`、`HOS_SDK_HOME`、`CLT_HOME`；
Windows runner 不填时使用 workflow 中的默认路径。

workflow 会在构建前检查 `default/sdk-pkg.json`、六套 `flutter.har` 和四套
`gen_snapshot.exe` 是否就位，缺失即失败。两种 CI 都先以 `--no-codesign` 构建，
然后由签名脚本完成 release 签名与校验；没有完整签名 Secrets 时不会上传 release HAP。
上传前还会解包检查 arm64 HAP 的 `libs/arm64-v8a/libapp.so` 和 x64 HAP 的
`libs/x86_64/libapp.so`，并校验 ELF machine 分别为 AArch64 与 x86_64。

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

### 4.2 音频链路（TPC 移植与本地覆盖）

`just_audio` / `audio_service` / `audio_session` 在 pub 上的官方包都没有
ohos 实现。社区 TPC 仓库提供完整移植；`just_audio` 已 vendor 到
`third_party/just_audio`，并通过本地依赖覆盖，便于维护 AVPlayer 专项修复。

```yaml
dependencies:
  just_audio_ohos:
    path: third_party/just_audio/ohos

dependency_overrides:
  # Vendored from fluttertpc_just_audio br_just_audio-v0.9.41_ohos
  # at a873331a9ac59588ea4b3741566873051439ae91, with local playback fixes.
  just_audio:
    path: third_party/just_audio
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

当前工作区的验证状态：

| 步骤 | 结果 |
| --- | --- |
| `git diff --check` | ✅ 通过 |
| ArkTS / HAP 编译 | ⏳ 未执行：本机已有 Flutter 鸿蒙 SDK 和双架构引擎缓存，但缺少可识别的 DevEco SDK/Hvigor 与签名工具 |
| `flutter pub get` | ⏳ 本轮未在主仓库重跑；现有 `pubspec.lock` 仍是此前上游配置生成的 hosted 锁定结果 |
| `flutter analyze` / `flutter test` | ⏳ 本轮未重跑主仓库分析和测试 |
| 设备播放回归 | ◐ 隔离工程已在 x86_64 模拟器完成启动和本地音频扫描；主仓库 release HAP、AVSession 与完整播放回归仍待完成 |

仍未完成：

1. **运行时验证**：AVSession 播控、后台保活、通知都在 ArkTS 侧，仍应在真机和
   x86_64 模拟器上跑一遍；本轮已完成模拟器启动与本地音频扫描回归。
2. **版本风险**：移植的验证上限是 Flutter 3.35 + SDK 6.0.1（API 21），本项目是
   3.47.7 + API 26。`flutter analyze` 通过说明 API 面对得上，但运行时行为仍需持续观察。
3. **签名与发布渠道**：GitHub release 需要配置 `SIGN_*` secrets，配置前不会生成可
   直接安装的 release HAP。
4. `audio_metadata_reader`（FFI）仍无 ohos 产物。
