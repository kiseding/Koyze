# 依赖版本基线

本文件记录**已验证可用的依赖版本组合**。升级任何一项前，请先在本表登记新组合并跑完
对应平台的回归测试。

## 当前基线

| 包 | `pubspec.yaml` 约束 | `pubspec.lock` 实际 | 状态 |
| --- | --- | --- | --- |
| `just_audio` | `^0.9.42` | `0.9.46` | ✅ 已验证 |
| `just_audio_windows` | `^0.2.2` | `0.2.3` | ✅ 已验证 |
| `audio_service` | `^0.18.17` | `0.18.19` | ✅ 已验证 |
| `audio_session` | `^0.1.25` | `0.1.25` | ✅ 已验证 |
| `flutter_js` | `^0.8.2` | `0.8.7` | ✅ 已验证 |
| `flutter_riverpod` | `^2.6.1` | `2.6.1` | ✅ 已验证 |
| `go_router` | `^14.8.1` | `14.8.1` | ✅ 已验证 |
| `dio` | `^5.7.0` | `5.11.1` | ✅ 已验证 |

工具链：

| 项 | 版本 |
| --- | --- |
| Flutter | `3.44.9`（CI 锁定） |
| Dart | `3.12.2` |
| Node.js（workers） | `>= 20` |

## 为什么需要这张表

`pubspec.yaml` 里的 `^` 约束允许补丁与次版本漂移。例如 `flutter_js: ^0.8.2` 在
`pub get` 时实际解析到了 `0.8.7`——这意味着**一次普通 `pub get` 就能改变 JS 引擎版本**，
而 JS 引擎是自定义音源的地基。

锁定 `pubspec.lock` 让 CI 与本地保持一致，但 `flutter pub upgrade` 仍会引入未验证版本。
本表的作用是：**任何 `pubspec.lock` 的变更都应该是显式的、经过验证的，而不是顺手升级的副产品**。

## 升级流程

1. 在分支上修改 `pubspec.yaml`
2. 跑 `flutter pub get`，记录 `pubspec.lock` 的新版本到本表（标注「待验证」）
3. 跑 `flutter analyze --no-fatal-infos` 和 `flutter test --exclude-tags live`
4. 在**受影响平台的真机/模拟器**上手动回归（见下表）
5. 通过后把状态改为「✅ 已验证」并合并

## 平台回归清单

任何涉及 `just_audio` / `audio_service` / `flutter_js` 的升级，至少验证：

| 平台 | 必须验证 |
| --- | --- |
| Android | 在线播放、本地播放、后台播放、媒体通知、均衡器、下载、SAF 目录 |
| Windows | 本地文件播放（走 HTTP 代理路径）、系统托盘、便携模式、关闭窗口行为 |
| iOS | 后台音频、锁屏控制、文件目录授权、Live Activity |
| macOS | 本地曲库、窗口行为 |
| Linux | 本地播放（需 GTK3 环境） |
| HarmonyOS | 自定义音源初始化（vendored QuickJS）、AVSession 媒体控制、后台播放 |

自定义音源相关改动额外验证：

- 导入 `.js` 文件、粘贴脚本、HTTPS 直链三种入口
- 音源启用/停用/切换
- `lx.request` 出网、私有网段被拒绝
- 超时与取消
- 脚本语法错误时的提示文案

## 已知的版本耦合

- `just_audio_windows` 的版本必须与 `just_audio` 的 API 版本匹配。升级主包前先确认
  Windows 实现是否已有对应版本，否则 Windows 平台会直接构建失败
- `audio_service` 与 `just_audio` 共享 `AudioPlayer` 的流语义，两者需同批验证
- 鸿蒙版 `flutter_js` 走 `third_party/flutter_js` 的 path 依赖，与 pub.dev 版本**解耦**；
  升级 pub.dev 版本不影响鸿蒙，但也不代表鸿蒙已验证
