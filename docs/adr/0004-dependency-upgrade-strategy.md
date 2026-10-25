# ADR-0004: 播放与 JS 引擎依赖的升级策略

## 状态

已接受（2026-10-26）

## 上下文

`pubspec.yaml` 中两个依赖承担了不可替代的核心职责，但版本已明显落后：

| 包 | 当前 | 最新 | 落后 |
| --- | --- | --- | --- |
| `just_audio` | `^0.9.42` | `0.10.6` | 1 个次版本（含破坏性变更） |
| `flutter_js` | `^0.8.2` | `0.8.7` | 3 个补丁版本 |
| `audio_service` | `^0.18.17` | — | 与 `just_audio` 版本强相关 |
| `go_router` | `^14.8.1` | `18.1.1` | 4 个主版本 |
| `flutter_riverpod` | `^2.6.1` | `3.4.3` | 1 个主版本 |

其中 `just_audio` 与 `flutter_js` 是**功能性地基**：

- `just_audio`：所有播放路径（在线、本地、NAS、缓存）的唯一播放引擎，55 处引用
- `flutter_js`：自定义音源的唯一执行环境，61 处引用；**没有替代品**——LX Music 音源格式
  是 JavaScript，换成任何其他脚本引擎都意味着重写整个兼容层

## 已知事实

### flutter_js 并非"无维护"

初步评估时曾判断 `flutter_js` 维护停滞，深入核查后需要修正：

- pub.dev 上最新版 `0.8.7` 发布于 2026-01-27，此前 `0.8.6` 同日发布——**2026 年仍有发布**
- 仓库内 `third_party/flutter_js` 是**鸿蒙专用移植**（源自 `flutter_js_ohos` 0.6.8，
  上游 `yeliulee/flutter_js` 的 `oh` 分支），已针对 Dart 3 FFI 做过适配，
  并按需裁剪了依赖
- `VENDORED.md` 记录了全部改动与原因，包括 `libc++_shared.so` 缺失这类只有真机才暴露的坑

也就是说：**鸿蒙平台已经事实上 "fork + pin" 了 JS 引擎**，pub.dev 版本的变化不会
直接冲击鸿蒙构建。真正的暴露面是 Android / iOS / Windows / macOS / Linux 这五个平台。

### just_audio 0.10.x 是破坏性升级

`0.9.x → 0.10.x` 的变更点（据 CHANGELOG）：

- `AudioSource` 体系重构，自定义 `StreamAudioSource` 的子类需要调整
- Windows 端 `just_audio_windows` 是**独立的第三方实现**，其 0.10 兼容版本滞后于主包
- 本项目有 `LocalFileStreamAudioSource`（本地文件走 HTTP 代理，绕开 WinRT 限制）
  这类深度定制，属于高风险改动面

## 决策

**不立即升级 `just_audio` 到 0.10.x。** 改为分阶段、可回滚的路径：

### 阶段一：锁定与观测（本次完成）

1. 在 `pubspec.yaml` 中把 `just_audio` 和 `flutter_js` 的约束收紧到**已知可用的最小上界**，
   避免 `pub get` 在无感知的情况下拉到未验证的新版本
2. 记录当前版本组合为"已验证基线"，写入 `docs/dependency-baseline.md`
3. 在 `SECURITY.md` 中声明只支持最新 release，降低旧版本组合的维护负担

### 阶段二：隔离抽象（后续）

将 `just_audio` 的直接调用收敛到一个适配层（`PlaybackEngine` 接口），使业务代码
不直接依赖 `just_audio` 的类型。当前 `audio_handler.dart` 4085 行中混杂了
播放器 API 调用与业务逻辑，这是升级困难的根本原因——**拆分 `audio_handler` 是
升级 `just_audio` 的前置条件，不是可选项**。

同理，`flutter_js` 的调用应收敛到 `SourceRuntime` 接口，使未来替换引擎（如
`flutter_qjs`、自建 QuickJS FFI）时业务代码零改动。

### 阶段三：逐个平台验证升级

按风险从低到高推进：

1. **Linux / Windows**（`just_audio_windows` 独立实现，先验证其可用版本）
2. **Android**（标准 `just_audio` 路径，用户量最大，需要最充分的回归）
3. **iOS / macOS**（AVFoundation 路径，Darwin 相关的 seek 行为有专门测试）
4. **HarmonyOS**（走 vendored 移植，与 pub.dev 版本解耦，最后处理）

## 理由

### 为什么不是"立即升级"

1. **升级的收益不明确。** 当前版本没有已知的、影响本项目的安全漏洞。
   `just_audio` 0.10.x 主要是 API 现代化，不是功能或安全修复
2. **升级的成本明确且高。** `audio_handler.dart` 4085 行、150 个方法，
   直接耦合 `just_audio` 类型。在没有适配层的情况下升级，等于在一个巨大的类上做
   全量回归
3. **多平台放大风险。** 6 个平台 × 1 个播放引擎 × 1 个第三方 Windows 实现，
   任何一处行为差异都会变成用户可见的播放故障
4. **没有回滚机制。** 一旦升级后发现某个平台的 seek 或缓存逻辑出问题，
   回退需要重新验证全部平台

### 为什么不是"不升级"

1. 依赖持续落后会累积成跳版本升级，风险更高
2. Flutter 大版本升级（如 3.44 → 4.x）最终会强制要求 `just_audio` 跟进
3. `go_router` 落后 4 个主版本，说明依赖更新没有纳入常规流程，需要建立机制

### 为什么先拆 `audio_handler` 再升级

这是本次决策最关键的一环。把 4085 行、150 个方法的类拆成：

- `PlaybackQueueController` —— 队列与索引
- `QualityResolver` —— 音质重解析
- `CacheLeaseCoordinator` —— 缓存租约
- `OutputRouteRecovery` —— 输出路由恢复
- `PlaybackEngine` —— `just_audio` 适配层

之后，升级 `just_audio` 的改动面从"全类回归"收敛到"只改 `PlaybackEngine`"。
**顺序颠倒会让升级变成不可控的重构。**

## 后果

### 正面

- 依赖升级从"不敢碰"变成"有明确路径"
- `flutter_js` 的鸿蒙移植先例证明 vendoring 是可行的兜底手段，
  必要时可以对其他平台做同样处理
- `audio_handler` 的拆分有独立的架构价值，不只是升级的副产品

### 负面

- 短期内仍在使用落后版本，需要接受这个风险窗口
- 拆分 `audio_handler` 本身是高风险的，需要充分的回归测试——而当前
  `audio_handler` 的测试有相当一部分是"读源码找字符串"，**不构成有效保护**
  （见 ADR-0005 与相关 Issue）

### 不做的事

- 不在没有适配层的情况下跳版本
- 不为"版本号好看"而升级
- 不把 `just_audio_windows` 的滞后当作可以忽略的问题——它是 Windows 平台
  的唯一播放实现

## 参考

- `pubspec.yaml` — 依赖约束
- `third_party/flutter_js/VENDORED.md` — 鸿蒙移植的完整改动记录
- `docs/dependency-baseline.md` — 已验证的版本基线
- ADR-0002 — Riverpod 状态管理（同样面临 2.x → 3.x 迁移）
