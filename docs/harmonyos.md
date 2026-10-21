# 鸿蒙（HarmonyOS 7.0 / API 26）构建说明

本文档记录 Koyze 的鸿蒙平台接入方式、工具链版本与当前已知缺口。

> 状态：**工程骨架已接入，尚未完成真机验证**。`ohos/` 目录由
> Flutter 3.47.7-ohos 的官方应用模板生成（`flutter create --platforms ohos`），
> 目标 SDK 为 API 26（HarmonyOS 7.0）。音频链路尚未接入鸿蒙实现，见第 4 节。

## 1. 版本矩阵

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | `3.47.7-ohos-1.0.0` | 上游 3.47.7 + 鸿蒙适配，Dart 3.13.3 |
| DevEco Studio | `26.0.0` | 自带 HarmonyOS SDK 26.0.0（API 26） |
| compatibleSdkVersion | `26.0.0` | `ohos/build-profile.json5` |
| targetSdkVersion | `26.0.0` | 同上 |
| bundleName | `com.koyze.app` | 与 Android applicationId、iOS bundle id 一致 |

上游 `openharmony-sig/flutter_flutter` 已迁移，最新适配仓库是
<https://atomgit.com/oh-flutter/flutter_flutter>。3.47.7 之后上游按版本列车跟进
（3.44 滞后 4 个月，3.47 已缩短到同步批次）。

## 2. 环境准备（Windows）

1. 安装 DevEco Studio 26.0.0，记下 SDK 路径（默认 `<DevEco>/sdk/default`，
   其中含 `openharmony/` 与 `hms/`）。
2. 拉取鸿蒙 Flutter SDK（放到非系统盘，SDK 本体约 540MB）：

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

   **不要设置** `FLUTTER_STORAGE_BASE_URL`。设为鸿蒙 OBS 镜像会导致
   `engine_stamp.json` 404（该镜像不托管上游工具本体），
   `flutter --version` 会报 `Unable to create dart snapshot for flutter tool`。
   默认官方源 `storage.googleapis.com` 可用时直接留空。

4. 引擎工件：`bin/internal/dart-sdk-url.ohos` 里全部指向 atomgit 的 Release 附件
   （`flutter_patched_sdk.zip`、`ohos-arm64*-artifacts.zip`、定制 `dart-sdk-*.zip`）。
   这些附件**匿名下载返回 401**，需要：

   - 登录 atomgit 后在
     <https://atomgit.com/oh-flutter/flutter_flutter/releases/tag/3.47.7-ohos-1.0.0>
     手工下载 11 个附件；或
   - 用带凭据的下载方式，把它们放进 `flutter_ohos/bin/cache/` 对应位置。

   `flutter doctor -v` 会自检 `HarmonyOS toolchain`。

## 3. 构建

```bash
flutter pub get
flutter build hap --debug --target-platform ohos-arm64      # 调试
flutter build hap --release --target-platform ohos-arm64    # 发布
```

产物在 `ohos/entry/build/default/outputs/default/`。安装到设备用
DevEco 的 `hdc`：

```bash
hdc install entry-default-signed.hap
```

签名：`ohos/build-profile.json5` 的 `signingConfigs` 目前为空，本地调试可在
DevEco Studio 里用「自动签名」（File → Project Structure → Signing Configs）生成，
CI 上则需要单独的签名证书与 profile，因此本仓库暂未添加鸿蒙构建工作流
（GitHub 托管 runner 也没有 HarmonyOS SDK 与许可）。

## 4. 插件适配矩阵

鸿蒙侧插件生态与 pub.dev 是两套：官方适配版多数以 `*_ohos` 发布，少数只在
社区仓库里以 git 依赖提供。

### 已有鸿蒙实现

| 依赖 | 鸿蒙方案 |
| --- | --- |
| `shared_preferences` | `shared_preferences_ohos`（pub） |
| `path_provider` | `path_provider_ohos`（pub） |
| `connectivity_plus` | `connectivity_plus_ohos`（pub） |
| `permission_handler` | `permission_handler_ohos`（pub） |
| `file_picker` | `file_picker_ohos`（pub） |
| `flutter_secure_storage` | `flutter_secure_storage_ohos`（pub） |
| `flutter_js` | `flutter_js_ohos`（pub） |

### 需要替换/自建的

| 依赖 | 现状 | 处理方式 |
| --- | --- | --- |
| `just_audio` | pub 上的官方包无 ohos 实现，直接跑会卡在 Loading（MethodChannel 找不到宿主） | 改用社区适配版 `just_audio_ohos`（基于 just_audio 0.9.37）：`git: https://atomgit.com/openharmony-sig/fluttertpc_just_audio`，`path: just_audio/ohos` |
| `audio_session` | 同上 | 社区仓库 `flutter_audio_session` 提供 ohos 实现 |
| `audio_service` | **鸿蒙没有 MediaSession 等价物**，无适配版 | 需要自建：ArkTS 侧用通知服务发媒体通知 + `MethodChannel` 桥接；后台播放还要在 `module.json5` 声明 `ohos.permission.KEEP_BACKGROUND_RUNNING` 并在 `EntryAbility` 申请后台任务 |
| `audio_metadata_reader` | 依赖 dart:ffi，需按 ohos ABI 重新编译 | 鸿蒙侧暂不读取本地音频元数据 |
| `just_audio_windows` / `home_widget` / `live_activities` / `flutter_app_group_directory` | 桌面 / iOS 专用 | 鸿蒙构建时自然跳过，不影响 HAP |

> 说明：`just_audio_ohos` 与 `audio_session` 的鸿蒙版**尚未写入 `pubspec.yaml`**。
> 它们会改变所有平台的依赖解析（git 依赖 + 全局 override），在鸿蒙构建未跑通前
> 加入会连累现有五个平台的 CI 稳定性，因此留到音频链路正式移植时一并引入。

## 5. 尚未完成

1. 引擎工件下载（atomgit Release 需要登录），本机尚未跑通 `flutter build hap`。
2. 音频播放与后台播控（见上表），这是"能装能开"和"能听歌"的分界线。
3. 签名配置与发布渠道。
4. 真机 / 模拟器验证矩阵（当前只在 API 26 模拟器与 ALN-AL00 上有社区验证记录）。
