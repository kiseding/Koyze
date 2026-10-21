# audio_service 的 HarmonyOS 移植（vendored）

来源：<https://gitcode.com/CPF-Flutter/fluttertpc_audio_service>，分支
`br_v0.18.18_ohos`，版本 0.18.18（基于上游 ryanheise/audio_service 0.18.18）。

## 为什么 vendored 而不是 git 依赖

上游仓库把 `example/assets/video2.mp4` 用 git-lfs 托管：

- 本机没装 git-lfs：checkout 报 `git-lfs: command not found`；
- GitHub 托管 runner 装了 git-lfs：smudge 时向 gitcode 的 LFS 端点请求匿名
  下载，gitcode 返回 401，五个平台的 CI 全部挂在 `flutter pub get`。

跳过 LFS 的配置（`GIT_LFS_SKIP_SMUDGE` / 自定义 `GIT_CONFIG_GLOBAL`）能修
本地，但没法保证每台 CI 机器都生效，而且把构建稳定性押在一个第三方仓库的
LFS 策略上不划算。这里只保留 `lib/ android/ darwin/ ohos/` 与元数据（共
~550KB），example 及其中的 LFS 大文件不进入仓库。

## 更新方法

1. 从上游仓库 checkout 对应分支；
2. 覆盖本目录的 `lib/ android/ darwin/ ohos/ pubspec.yaml`；
3. 在项目根目录跑 `flutter analyze` 确认无回归；
4. 提交并同步 `docs/harmonyos.md` 里的版本矩阵。

`pubspec.yaml` 里的 `ohos: pluginClass: AudioServicePlugin` 声明保留原样，
鸿蒙侧实现（AVSession + 后台任务 + WantAgent）在 `ohos/src/main/ets/` 下。
