# Koyze — 修复进展报告

工作副本：`koyze-review\Koyze-main\`（已就地修改；`koyze-baseline\Koyze-main\` 是未改动的对照副本）
SDK：Flutter 3.44.9 / Dart 3.12.2，安装在 `E:\flutter_sdk`（与 CI 固定的版本一致）

这些修复已经铺到线上 `4940ca0`（2026-09-30 的 `main`）之上，不是旧的 `8f8d8bd`。
线上自带的 `source_health_monitor.dart`、`performance_monitor.dart` 和 `monitoring_service.dart` 保留；只在 `crash_reporter.dart` 上补了面包屑和 AppLog 镜像，并在 `main.dart` 里真正调用初始化。

## 验证结论（实测，非推断）— 已更新至第二轮

| 检查 | 结果 |
|---|---|
| `flutter test --exclude-tags live`（未改动对照副本） | +1415 **−71** |
| `flutter test --exclude-tags live`（修复后） | +1474 **−12** |
| 归因于本次改动的**新增**失败（回归） | **0** |
| 已修好的既有失败 | **55** |
| `dart analyze`（改动文件） | 无 error/warning |
| `workers` `npm run validate`（test + typecheck + batch-d） | 17/17 通过，退出码 0 |

诊断：`Compare-Object` 比对两端失败用例名 —— **新增失败集合为空**。

### 第一轮：47 个失败已修（按原因）

**A. 平台耦合（本轮主修，约 44 个）**
`LxAudioHandler` 原来在构造函数初始化列表里**内联**读取 `Platform.isWindows`，导致整套音频测试
只在非 Windows 主机上通过。现改为可注入接缝：

```dart
class AudioHandlerPlatformDefaults {
  static final host = AudioHandlerPlatformDefaults(
    useSilenceKeepalive: !Platform.isWindows,
    streamLocalFiles: Platform.isWindows,
  );
  static const posix = AudioHandlerPlatformDefaults(
    useSilenceKeepalive: true, streamLocalFiles: false);
  @visibleForTesting static AudioHandlerPlatformDefaults current = host;
  @visibleForTesting static void resetCurrent() => current = host;
}
```

- `_streamLocalFiles` **新增**为 `LxAudioHandler` 的可注入字段
  （此前 `streamLocalFiles` 直接写死 `Platform.isWindows`，连参数都没有）
- `_useSilenceKeepalive` 与 `_streamLocalFiles` 均从 `AudioHandlerPlatformDefaults.current` 取默认值
  （注意 `host` 必须是 `static final` —— `Platform.isWindows` 不是常量表达式）
- 8 个音频测试文件在 `setUpAll` 固定为 `posix`、`tearDownAll` 复位，
  把「测试断言的是非 Windows 行为」从**隐式依赖主机**变成**显式声明**
- 两处钉死源码文本的结构性断言同步更新为「断言生产默认值仍来自平台 + handler 走接缝」：
  `test/core/audio/seek_clamp_test.dart`、`test/build_configuration_test.dart:197-200`

**B. 顺带转绿的既有失败**
`playableUri treats windows drive paths as local files`、`windows next/previous skips silence
keepalive ...`、`skip-to-next suppresses engine idle while keepalive is installed`、
`repeat one completion reloads the current item` 等。

### 仍未修的 11 个（全部已在未改动副本上确认同样失败）

| 组 | 数量 | 备注 |
|---|---|---|
| 缓存服务 / 释放期 | 3 | `rejects dot-dot and sibling-prefix persisted paths`、`load repairs persisted path ...`、`empty playlist cannot submit stop after disposal begins during release` |
| `LocalMusicLibrary` | 3 | 见下 |
| 下载 | 3 | `never starts more than maxConcurrent downloads` 等 |
| **需产品判定** | 2 | 见下 |

**第三轮已修：缓存文件租约组 5 个中的 3 个。** 同 `patchQueueArtUri` 一类问题——
缓存路径要经 `PlaybackCacheService.toPlayableUri`（file URI）与缓存内部
`_normalizeAbsolute`（`Uri.file(...).normalizePath().toFilePath()`）往返，Windows 上分隔符
会被改写为 `\`，而断言按 POSIX 风格写死。新增 `nativeCachePath()` 辅助函数
（**只替换分隔符、不做绝对化**——我第一版误用了 `File(path).absolute`，
在 Windows 上产出 `C:\...\\cache\new.mp3` 这样的混合路径，已修正）。

#### 需要产品判定的 2 个（我没有强行改）

```
LxAudioHandler cached file reuse resolver cached lease commits as active ownership   (test:1124)
LxAudioHandler cached file reuse current resolution atomically publishes extras and stages its lease  (test:1585)
```

两个都是「**成功安装之后** `lease.releaseCount` 为 1，但断言期望 0」，其余断言
（`sourceInstallCount == 1`、`errors` 为空、quality 已发布、`stop()` 后为 1）全部通过。

**为什么不当场改**：若实现真的在成功安装后提前释放了租约，那是一个**真实且危险**的缺陷
——缓存文件可能在播放期间被 LRU 淘汰；反过来若实现是对的，那这两条断言就写错了。
在无法确认哪个才是意图的情况下，把断言改成迁就实现（或反之）都可能把缺陷固化，
因此留作需要产品判断的项。判定方法：跟踪 `acceptResolvedPlayback` 返回 true 后
`LxAudioHandler` 对 staged lease 的处理路径，确认释放是否发生在「新源已提交」之后。

### 关于 `LocalMusicLibrary` 那 3 个失败（**非本次引入**）

已逐条确认未改动的对照副本上同样失败。我对该文件唯一的改动是
`statSync()` → `await File(path).stat()`；`Compare-Object` 逐行比对显示，
除这一处与两行注释外与上游完全一致，行为等价。

成因分三类：
- `rescan removes deleted files` / `rescan reparses changed files` —— 仓库既有缺陷
  （`rescanAll()` 的删除清理与刮削身份作废未生效），需单独排查清理时序
- `builds MusicItem with dual identity` —— Windows 路径格式：断言期望 `file://C:\...`，
  实际 `file:///C:/...`。断言写死了 POSIX 风格，测试本身不可移植

---


## 已完成并验证

### Workers 后端（`npm run validate` 全绿）

1. **`db/schema.ts` — 移除表数硬编码 503 定时炸弹**
   `tableCount === 14` 精确相等改为「必需表集合是否齐全」（`REQUIRED_TABLES` + 缺失集合比对）。
   原先下一个新增/删除任何表的迁移都会让整个 API（除 `/ping`、`/version`）返回 503。
   现在多余的表不再影响就绪判定。同时删掉未使用的 `NOT_READY_CACHE_TTL`。

2. **`middleware/rateLimit.ts` — DO 分片显式化**
   `check`/`reset` 增加 `shard` 参数（默认仍为按 IP）。这是修复「每账号限流实际是每 IP 限流」的前提：
   原先 `account:` 桶和 IP 共用同一个 DO 分片，攻击者轮换 IP 即可对单账号无限尝试。

3. **`routes/user/auth.ts` — 登录账号桶独立分片**
   IP 桶与账号桶分别落在 `auth-ip:<ip>` 与 `auth-acct:<name>`，两者并发检查；登录成功只重置账号桶。

4. **`routes/user/auth.ts` — 管理员自我锁死防护**
   `PUT /api/admin/users` 原先**只校验登录态**就能覆写任意 `id` 的密码并递增 `token_version`。
   现增加：拒绝修改自己、修改管理员前确认至少还剩一个管理员、`Number.isSafeInteger` 校验 id、
   以及 `meta.changes === 0` 时返回 404（原先对不存在的 id 静默返回 `ok:true`）。
   `DELETE` 同理补上「用户不存在」与最后一管理员防护。

5. **`routes/user/auth.ts` — 为跑 PBKDF2 的写路径加限流**
   新增 `enforceAccountWriteLimit`（按账号分片）：改密码 10 次/10 分钟、管理员建号 20 次/10 分钟。
   同时抽出 `tooManyRequestsResponse`，消除原先重复的 429 构造。

### Dart 侧（`dart analyze` 干净，测试无回归）

6. **#1 本地曲库扫描同步 I/O（Critical）**
   根因确认：`audio_metadata_reader` 的 `readMetadata` 是**同步**函数，且没有异步版本。
   - 标签与内嵌封面解析移入 worker isolate（`compute(probeTagsOnWorker, ...)`），
     返回可序列化的 `LocalTagProbe`（不再跨 isolate 传递不可发送的解析器对象）。
   - `shouldSkip` 由 `bool Function` 改为 `Future<bool> Function`，`local_music_library.dart`
     的每文件 `File(path).statSync()` 改为 `await File(path).stat()`
     （扫描器内另一处 `statSync` 也在 `local_music_library.dart:406`）。
   - `onProgress` 增加 100ms 节流（末尾必定上报一次），消除「每个文件一次 `setState` →
     整列表重建」。

7. **#3/#9 接线休眠的监控与日志（Critical）**
   - `main.dart` 在 `_bootstrapUnsafe` 开头调用 `AppLog.instance.start()`。
     此前全仓库**唯一**的调用点在 `app_log_screen.dart:23`（设置里的诊断浮层），
     导致 `main.dart` 中 18 处 `AppLog.instance.record(...)` 全是空操作、发布版**没有任何崩溃捕获**。
   - 随后 `MonitoringService().initialize(MonitoringConfig.production)`，并包 try/catch 保证
     监控失败不阻塞启动。顺序刻意放在 `AppLog` 之后，使 `CrashReporter` 的全局
     handler 链接到 `AppLog` 的 handler 而不是覆盖它。
   - `CrashReporter._sendToService` 不再只 `debugPrint`：崩溃报告改为**镜像进 `AppLog`**
     （带堆栈、经过密钥脱敏），并注明接入真实后端的位置。
   - `addBreadcrumb` 从 TODO 变为真实实现（带上限的环形缓冲），新增 `breadcrumbs` getter
     与 `exportBundle()`。

---

## 既有 70 个测试失败：根因已定位（实测）

对照副本保持原样后，做了两次受控实验以分离原因：

| 配置 | 5 个音频测试文件的失败数 |
|---|---|
| 原始（`Platform.isWindows` 生效） | **58** |
| 强制「非 Windows」：`_useSilenceKeepalive` 默认 true + `streamLocalFiles: false` | **12** |

结论：**70 个失败中约 46 个是「测试套件按非 Windows 编写，但 `LxAudioHandler` 在 Windows 上刻意改变行为」**，
只有 **12 个是真实的跨平台缺陷**。

耦合点只有两处（`lib/core/audio/audio_handler.dart`）：
- `:868` `_useSilenceKeepalive = useSilenceKeepalive ?? !Platform.isWindows`
- `:3340` `streamLocalFiles: Platform.isWindows`

这两处已被结构性测试钉死（`test/core/audio/seek_clamp_test.dart:36` 断言源码含
`'streamLocalFiles: Platform.isWindows'`；`test/build_configuration_test.dart:198-199` 断言含
`'!Platform.isWindows'`），所以**修法不能直接删掉平台判断**，而要把它变成可注入的接缝
（测试里显式指定，生产里默认取平台值），并同步更新那两个结构性断言。

### 真正的 12 个缺陷（与平台无关，必须修）

```
empty playlist cannot submit stop after disposal begins during release
LxAudioHandler cached file reuse current resolution atomically publishes extras and stages its lease
LxAudioHandler cached file reuse old active lease releases only after replacement source commits
LxAudioHandler cached file reuse preloaded cached file is re-leased before authoritative reuse
LxAudioHandler cached file reuse resolver cached lease commits as active ownership
LxAudioHandler cached file reuse stale pending lease releases before rejected file re-resolves to stream
patchQueueArtUri during load keeps foreground identity
patchQueueArtUri during preload keeps preload identity
patchQueueArtUri fills artCacheFile when artUri already matches
patchQueueArtFile writes artCacheFile for lock screen artwork
patchQueueArtUri writes artCacheFile on an upcoming queue item
playableUri treats windows drive paths as local files      <- 不稳定（我的运行中通过了）
```

集中在三处：**缓存文件租约/所有权转移**（5 个）、**`patchQueueArtUri`**（5 个）、
以及**释放期空歌单 stop**（1 个）。另有 `playableUri` 那条断言 `scheme` 为空，
与实现刻意返回 `file` scheme 相矛盾（`audioSourceFor` 依赖它判断本地文件），
且在我的一次运行中通过、另一次失败 —— **属不稳定用例，需要先判定实现与断言谁是错的**。

### 修复建议顺序

1. 引入可注入接缝替代 `:868` / `:3340` 的 `Platform.isWindows`，同步更新两处结构性断言
   → 预期一步消除约 46 个失败。
2. 修 `patchQueueArtUri` 的 5 个（纯函数逻辑，最容易，先做）。
3. 修缓存租约所有权的 5 个（`PlaybackCommandCoordinator` ↔ `LxAudioHandler` 交界，最难）。
4. 判定 `playableUri` 与 `empty playlist ... stop` 两条的实现/断言对错。

## 续作状态（相对上面「未完成」表）

| # | 项 | 状态 |
|---|---|---|
| 0 | 文档里点名的封面补丁、缓存租约、空歌单 stop | 这几组用例现在通过。平台差异已走 `AudioHandlerPlatformDefaults`。全量音频套件没有在这次重跑。 |
| 2 | 自定义音源执行隔离 | **未做**。`evaluate` 与 Dart 回调是同步桥，整段搬进 isolate 会改掉 2000 行引擎的请求模型。 |
| 5 | 音源错误可区分 | **部分**。酷我/QQ/网易搜索失败抛 `SourceFailure`（离线、超时、HTTP），搜索页能显示，不再伪装成空列表。其余吞掉的 catch 没有逐个改完。 |
| 8 | `LxAudioHandler` 拆分 | **未做**。类仍在 `audio_handler.dart`，约 4000 行。 |
| 9 | 审查里点名的死代码 | 当前树里没有 `EnhancedScriptValidator`、`lib/core/ui/`、`startup_optimizer`、`a11y_helpers`、`high_performance_list`。 |
| 10 | 源码 grep 测试 | **未做**。仍有 32 个测试文件使用 `readAsStringSync`。 |
| 11 | 内置音源下载走地址策略 | **已做**。生产路径（未注入 Dio/downloader）走 `SourceMediaTransport`。解析到内网地址会在连接前拒绝。 |
| 12 | Dio 复用 | **已做**。`createDioForService` 按超时和请求头复用客户端。歌词请求用单次 `Options`，不再改共享客户端的 `responseType`。 |
| 13 | 封面解码尺寸 | **已做**。`ArtworkImage` 按布局宽度 × 像素比解码，上限 1080 物理像素；显式 `cacheWidth` 仍优先。 |

---

## 本轮需要更正的两处既有结论

1. **`test/features/custom_source/enhanced_script_validator_test.dart` 是存在的**
   （300 行、21 个用例）。此前「该文件不存在」的判断来自两条被截断的 PowerShell 输出
   （`Select-Object -First 15/20` 在结果按字母序排列时把该文件切掉了）。
   结论方向不变——`EnhancedScriptValidator` 在生产代码中**仍然零引用**，
   只有它自己的测试在调用——但「提交历史里那份测试根本不存在」是错的，**该提交确实补了测试**。

2. **`lib/` 规模**：208 个 Dart 文件 / 70,783 行（此前误报 379 / 108,609，原因是
   `Get-ChildItem -Recurse -Filter` 的统计口径把 `test/` 也算进去了）。

---

## 复现命令

```powershell
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$flutter = 'E:\flutter_sdk\flutter\bin\flutter.bat'
$dart    = 'E:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.exe'

Set-Location <repo>
& $dart analyze
& $flutter test --exclude-tags live

Set-Location <repo>\workers
npm ci; npm run validate
```

> Windows 上 `flutter pub get` 会对插件软链接报警告（需要开发者模式），
> 但依赖解析与 `test`/`analyze` 均不受影响。
