# Koyze

Koyze 基于 **Flutter** 开发，覆盖 **Android / Windows / iOS**。内置酷我（KW）、QQ 音乐（TX）、网易云（WY）三个音源，支持通过脚本接入洛雪音源；自带一套 Cloudflare Workers 后端用于账号认证与云歌单同步。

| 项 | 值 |
| --- | --- |
| 应用版本 | `1.4.0+4` |
| Flutter | `3.44.9+`（Dart `3.12+`，Stable） |
| 目标平台 | Android · Windows · iOS |
| 音源 | 酷我（kw）、腾讯（tx）、网易云（wy）+ 自定义脚本音源 |
| 后端 | Cloudflare Workers（TypeScript + D1 + KV + Durable Object） |

---

## 目录

- [设计动机](#设计动机)
- [快速开始](#快速开始)
- [功能特性](#功能特性)
  - [多音源与搜索](#多音源与搜索)
  - [播放器](#播放器)
  - [音质选择与回退](#音质选择与回退)
  - [歌词](#歌词)
  - [播放增强](#播放增强)
  - [歌单](#歌单)
  - [下载](#下载)
  - [统计与猜你喜欢](#统计与猜你喜欢)
  - [自定义音源脚本引擎](#自定义音源脚本引擎)
  - [云同步与后端](#云同步与后端)
  - [设置项一览](#设置项一览)
  - [平台专属能力](#平台专属能力)
- [路由与页面](#路由与页面)
- [安全设计](#安全设计)
- [技术栈](#技术栈)
- [架构与目录结构](#架构与目录结构)
- [构建与发布](#构建与发布)
- [CI / CD](#ci--cd)
- [后端 API](#后端-api)
  - [部署方式](#部署方式)
- [测试](#测试)
- [免责声明](#免责声明)

---

## 设计动机

聚合平台。

Koyze 的取舍：**保留一个界面，把音源藏到背后**。

- 搜索跨平台出结果，命中可播的版本；
- 播放按音质阶梯选择，主源不可用自动回退，必要时跨平台兜底；
- 歌词、榜单、歌单多平台交叉获取；
- 所有歌单、收藏、统计留在本地文件里，属于你而不是某个平台；
- 可选自建账号，把收藏与自定义歌单同步到云端。

---

## 快速开始

环境要求：Flutter `3.44.9+`（Dart `3.12+`），各平台独立工程，无需额外代码生成。

```bash
flutter pub get

# Android：发布需配置签名；产物为按 ABI 拆分的 3 个 APK + 1 个 AAB
flutter build apk --release --split-per-abi
flutter build appbundle --release

# Windows：x64 便携版
flutter build windows --release

# iOS：无证书构建，供 Apple ID 侧载
flutter build ios --release --no-codesign
```

运行测试：

```bash
flutter test --exclude-tags live   # 前端全部确定性测试
```

---

## 功能特性

### 多音源与搜索

**统一抽象**：三个内置平台实现同一个 `MusicPlatform` 接口，由 `MusicSourceService` 统一调度。上层任何能力（搜索、榜单、歌词、播放地址、封面）都按"主平台优先、其余平台按匹配度兜底"的方式交叉回退，单个平台故障不会让整个功能不可用。

**内置平台技术细节**

| 平台 | ID | 能力要点 |
| --- | --- | --- |
| 酷我 KW | `kw` | 搜索 / 榜单（41 类）/ 歌单 / 歌词 / 播放地址；CSRF Cookie 获取、`convert_url` 链式解析（3 级回退）、Kuwo 加密歌词解码 |
| 腾讯 TX | `tx` | 搜索 / 榜单（8 类）/ 歌单 / 歌词（QRC 逐字 + 传统 base64）/ 播放地址（`vkey` 签名，按音质选 `filename` 前缀） |
| 网易云 WY | `wy` | 搜索 / 榜单（8 类）/ 歌单 / 歌词（`yrc` 逐词转 LRCX）/ 播放地址（`weapi`/`eapi` AES + RSA 加密参数） |

**搜索**：

- 单曲与歌单两种形态；
- 可限定"全部 / 酷我 / 腾讯 / 网易云"，"全部"模式多平台结果融合并按相关度排序；
- 分页加载，滚动到底自动取下一页；
- 搜索历史本地持久化，可复用、可清理。

### 播放器

- 基于 `just_audio` + `audio_service`，支持后台播放与 Android 通知栏常驻控制；
- 播放队列**懒加载**、下一首**预加载**，减少切换卡顿；
- 所有播放命令（播放、暂停、切歌、跳转、音质变更、恢复）经 **`PlaybackCommandCoordinator`** 串行化执行，快速连点不会产生竞态或乱序；
- 实时进度用 Timer 轮询 `just_audio` 的 position，比纯 Stream 更稳定；拖动跳转后进度立即校正；
- **播放恢复**：记忆上次队列与位置，下次启动按"自动恢复播放"设置决定是否续播（默认只载入队列并暂停）。

### 音质选择与回退

**音质链**：`128k → 320k → flac → flac24bit（臻品母带）→ hires` 五档：

- 播放音质与下载音质**分开设置**；
- 支持按单曲覆盖默认音质，改设置后当前队列立即按新音质重新解析；
- 解析结果带有效期，过期自动重新获取；
- 首选不可用时沿质量链**逐级回退**；必要时在 `tx / kw / wy` 之间按最佳匹配分数**跨平台兜底**；
- 质量链带有"诚实校验"：若解析出的地址实际音质低于请求档位，视为失败并继续回退，避免"假成功"低码率；
- FLAC 走流式 HTTPS 播放；iOS 端使用精确时长与定时，保证 FLAC 拖动定位准确。

**播放地址解析优先级**（`resolvePlayableUrl`）：

1. 已启用的自定义脚本音源（优先且允许即时降级）；
2. 内置平台同源精确匹配（按 `exactAttemptKey` 去重候选）；
3. 同平台搜索刷新（名称 +2、歌手包含 +2 的匹配打分，≥4 分命中）；
4. 跨平台兜底（按 `tx / kw / wy` 顺序逐个搜索并解析）。

### 歌词

- 支持 **LRC / LRCX / QRC** 三种格式。QRC（QQ 逐字歌词）自带解码器，无需外部转换；
- 网易云 `yrc` 逐词歌词自动转换为 LRCX `<start,dur>` 格式，多平台都能逐字高亮；
- 逐行与逐词双时间轴；滚动居中 + 卡拉 OK 逐字高亮，当前行始终居中；
- 支持手动歌词偏移校正；
- 多平台歌词交叉获取：一个平台没有就从另一个平台补。

### 播放增强

**播放统计**：

- 播放历史按"分段计时"记录，拖动进度条的部分不计入时长，防刷量；
- 记录最近播放、总播放次数 / 时长 / 活跃天数 / 去重歌曲数；
- 支持"周 / 月 / 年 / 全部"时间跨度、每日热力图、TOP 歌曲 / 歌手 / 专辑。

**猜你喜欢**：

- 内置推荐引擎：以收藏歌曲构建用户画像（歌手 / 专辑 / 平台三个特征维度，权重归一化到 0~1）；
- 候选歌曲按加权内容相似度评分（歌手 0.55 / 专辑 0.30 / 平台 0.15），叠加播放历史隐含反馈，输出推荐理由（"常听 XX 歌手""专辑 XX"等）；
- 推荐结果**严格排除已收藏歌曲**（同 ID，以及跨平台同名同歌手的重复版本）;
- 当本地没有足够的未收藏候选时（例如用户只有一个收藏列表），自动从画像中权重最高的常听歌手、在收藏最常用的音源上搜索补足候选，保证始终返回 30 首；
- 搜索失败自动降级为本地候选，不影响结果；仅在收藏 / 播放历史变化时重新计算，不会反复联网。

**睡眠定时**：10 / 15 / 30 / 60 / 90 分钟，设置页实时倒计时并可取消。

**播放缓存**：

- 本地磁盘缓存 + 租约管理 + 下载式后台续传；
- 命中缓存直接复用；带签名的远程 URL 一律不缓存（避免过期签名污染缓存）；
- 缓存可按分类清理（设置页多选对话框）。

### 歌单

- **本地持久化**：歌单以本地文件存储，**原子写入**；文件损坏自动隔离并尝试恢复；大歌单**惰性解析**，进入详情页才加载歌曲列表；
- **管理**：收藏（喜欢）、自定义歌单；创建 / 重命名 / 删除 / 清空；批量添加；手动排序；编辑模式拖拽重排；
- **去重与重复检测**：同歌单去重，跨歌单检测同一首歌出现的位置（`/duplicates` 页）；
- **导入**：解析 QQ / 酷我 / 网易云第三方歌单链接，跨平台重匹配到可播放版本；
- **备份 / 恢复**：一键导出 / 导入完整配置。备份文件 `koyze_backup_<时间戳>.json`，内容含版本 / 歌单 / 搜索历史 / 主题 / 音质 / 下载与恢复行为 / 默认搜索平台；导入带严格校验（体积 / 深度 / 数量上限、未知字段拒绝）+ 事务回滚。

### 下载

- 下载任务中心：进行中 / 已完成 / 全部；
- 最多 3 并发，速度采样，进度持久化（重启后续传）；
- 暂停 / 恢复 / 取消；
- 断链（401 / 403 / 404 / 410 / 416）自动重新解析地址，重试不超过 2 次；
- **仅 Wi-Fi 下载**开关（默认开启）；
- 缓存上限可配（默认 2GB）；
- iOS 端启用后台文件保护。

### 统计与猜你喜欢

- 播放历史按"分段计时"记录（拖动进度条不计时长，防刷量）；
- 统计维度：最近播放、总次数 / 时长 / 活跃天数 / 去重歌曲数；
- 视图：周 / 月 / 年 / 全部、每日热力图、TOP 歌曲 / 歌手 / 专辑；
- 推荐引擎：歌手 / 专辑 / 平台三维画像 + 加权相似度评分 + 播放历史反馈 + 推荐理由 + 严格排除已收藏 + 常听歌手音源搜索补足 30 首。

### 自定义音源脚本引擎

- 内置 **QuickJS**（`flutter_js`）脚本运行时，兼容 LX Music / phg-music 等流行脚本格式；
- **导入方式**：本地文件 / URL / 手动粘贴；导入后可开关、更新、删除、导出；
- **沙箱环境**：`lx.request` 网络桥接（SSRF 防护 + IP 固定传输）、`window / document / XMLHttpRequest / localStorage / crypto` 等 DOM 与加密 polyfill；
- 支持混淆脚本自检；控制台与错误日志可视化；
- 导入前有内容扫描与格式校验。

### 云同步与后端

自建 **Cloudflare Workers** API 承载账号与云歌单，**不代理搜索 / 播放 / 歌词**（直接走音源，避免中间人风险）。

- 账号：注册 / 登录 / 登录态校验；
- Token 用 `flutter_secure_storage`（Keychain）按服务地址分域保存，旧明文 Token 自动迁移；
- 云歌单双向同步：收藏列表 + 自定义歌单，按 `source|songmid` 去重合并、只增不删；
- 反滥用：按 IP 与账号双维度限流（Durable Object）、登录失败上锁、修改密码后所有会话立即失效。

### 设置项一览

设置值统一由 `StorageService`（SharedPreferences）持久化，带**代际计数**（慢加载不覆盖新修改）与**串行写队列**（失败回滚）。以下为全部设置项：

| 设置 | Provider | 存储键 | 默认值 | 说明 |
| --- | --- | --- | --- | --- |
| 主题模式 | `themeModeProvider` | `theme_mode` | 跟随系统 | 深色 / 浅色 / 跟随系统 |
| 播放音质 | `audioQualityProvider` | `audio_quality` | 320k | 五档音质，改后当前队列立即重解析 |
| 下载音质 | `downloadQualityProvider` | `download_quality` | 320k | 与播放音质独立 |
| 仅 Wi-Fi 下载 | `wifiOnlyDownloadProvider` | `wifi_only_download` | true | 仅 Wi-Fi 时允许下载 |
| 自动恢复播放 | `autoResumePlaybackProvider` | `auto_resume_playback` | false | 启动后是否自动续播 |
| 默认搜索平台 | `defaultSearchPlatformProvider` | `default_search_platform` | `tx` | 搜索页默认音源 |

**设置页分区**：外观（深色 / 跟随系统）、播放（音质、睡眠定时、自动恢复、默认搜索平台、听歌统计）、歌单（重复歌曲）、下载（下载管理、仅 Wi-Fi、下载音质）、高级功能（本地音乐目录、自定义源）、同步（云端账号）、数据（备份 / 恢复 / 清除缓存）、关于（版本、实时诊断日志）。

### 平台专属能力

**iOS**

- 锁屏歌词同步（App Group）；
- 桌面小组件（`home_widget`）；
- "灵动岛 / 实况活动"深链（`koyze://nowplaying`，冷启动与小组件点击均可直达播放器）；
- Keychain 安全存储、后台播放。

**Windows**

- 系统托盘：双击还原，右键菜单"打开 / 退出"；
- 关闭窗口时弹主题化对话框：最小化到托盘 / 退出 / 取消，可勾选"下次不再询问"并记忆行为；
- 进程单实例：重复启动自动唤起已运行窗口。

---

## 路由与页面

`go_router` 单一 `GoRouter`，底部四 Tab 用 `StatefulShellRoute` + 滑动切换，顶层页面用 `expandablePage` 卡片展开转场。

**底部 Tab**

| 索引 | 路径 | 页面 |
| --- | --- | --- |
| 0 | `/` | 首页 |
| 1 | `/leaderboard` | 榜单 |
| 2 | `/playlist` | 歌单 |
| 3 | `/settings` | 设置 |

**顶层路由**

| 路径 | 页面 | 备注 |
| --- | --- | --- |
| `/playlist/detail/:playlistId` | 歌单详情 | 支持 `?focusSongId=` 定位 |
| `/search` | 搜索 | |
| `/player` | 播放器 | 全屏播放页，支持边缘滑动关闭 |
| `/local-music` | 本地音乐 | |
| `/download` | 下载管理 | |
| `/custom-source` | 自定义音源 | |
| `/leaderboard-settings` | 榜单设置 | |
| `/leaderboard/detail` | 榜单歌曲 | `?id=` `?name=` |
| `/sync` | 云同步 | |
| `/stats` | 听歌统计 | |
| `/duplicates` | 重复歌曲 | |
| `/recommend` | 猜你喜欢 | |

---

## 安全设计

网络与脚本是第三方音乐源的入口，也是风险最高的位置。Koyze 在此做了多层防护：

**SSRF 防护**

- `SourceRequestSandbox` 阻止私网 / 回环 / 链路本地地址；
- DNS 先解析并校验，再用固定 IP 直连（`SourcePinnedTransport`），防止 DNS 重绑定攻击；
- 请求头清洗：剔除逐跳头，仅同源请求保留 Authorization / Cookie；
- 重定向最多 5 跳；并发与字节预算限制；响应体上限 10MB。

**脚本安全**

- 自定义音源脚本导入前做内容扫描与格式校验；
- 脚本运行在受限 QuickJS 沙箱内，网络能力被桥接层约束。

**凭据安全**

- 密码 PBKDF2-SHA256（16 字节盐、100k 迭代）+ 常数时间比较；
- JWT（HS256）携带 `token_version`，改密 / 降权可即时踢下线所有会话；
- 日志脱敏：Token / Cookie / 密码在日志中一律打码。

**工程健壮性**

- 启动依赖全部可回溯（`ResourceDisposalTracker`），失败自动清理；
- 文件读写带字节上限保护；JSON 解析带预算限制；文件歌单损坏自愈；
- 设置写入失败抛出 `StorageWriteException`，调用方可感知。

---

## 技术栈

| 类别 | 选型 |
| --- | --- |
| 框架 | Flutter 3.44.9（Dart 3.12，Stable 渠道） |
| 状态管理 | flutter_riverpod（Provider / Consumer，ProviderContainer 预初始化 + 生命周期托管） |
| 路由 | go_router（`StatefulShellRoute` + 滑动切换 + 深链） |
| 音频 | just_audio、audio_service、audio_session、just_audio_windows |
| 网络 | dio、connectivity_plus |
| 存储 | shared_preferences、flutter_secure_storage、path_provider |
| 脚本引擎 | flutter_js（QuickJS / JSCore） |
| iOS 增值 | home_widget、live_activities、flutter_app_group_directory |
| 后端 | Cloudflare Workers（TypeScript + D1 + KV + Durable Object + Wrangler 4） |

---

## 架构与目录结构

```
lib/
├── main.dart                  # 启动入口：依赖注入、音频会话、脚本初始化、会话恢复
├── app.dart                   # 根 Widget：主题 / 路由 / 通知 / Windows 关闭处理
├── startup_lifecycle.dart     # 启动依赖追踪与资源回收（失败自动清理）
├── core/
│   ├── audio/                 # 音频处理、播放缓存租约、播放命令协调器
│   ├── music_source/          # 音源抽象 + 内置平台（kw / tx / wy）与签名算法
│   ├── network/               # HTTP 客户端、音源请求沙箱、IP 固定传输
│   ├── storage/               # 设置持久化、Keychain、缓存维护、TTL 缓存
│   ├── logging/               # 环形日志与脱敏
│   ├── pagination/            # 分页工具
│   ├── theme/                 # 配色与主题
│   ├── widgets/               # 通用组件（通知横幅、分页栏、封面缓存、渐变栏等）
│   └── windows/               # Windows 关闭对话框与托盘
├── router/                    # go_router 路由表 + 深链解析
├── features/                  # 按功能分层（domain / data / presentation）
│   ├── home/                  # 首页与四 Tab 导航 + 迷你播放条
│   ├── search/                # 搜索
│   ├── leaderboard/           # 排行榜
│   ├── recommend/             # 猜你喜欢
│   ├── playlist/              # 歌单（文件持久化、导入、去重）
│   ├── player/                # 播放器（队列、音质、睡眠定时、会话恢复）
│   ├── lyric/                 # 歌词解析与滚动视图
│   ├── download/              # 下载管理
│   ├── custom_source/         # 自定义音源脚本引擎与沙箱
│   ├── cloud/                 # Cloud API 客户端与会话
│   ├── sync/                  # 云歌单合并与同步页
│   ├── stats/                 # 听歌统计与推荐数据源
│   └── settings/              # 设置、备份 / 恢复、诊断日志
├── android/ ios/ windows/     # 各平台原生工程
└── workers/                   # Cloudflare Workers 后端
```

**分层约定**：每个功能按 `domain`（纯 Dart 领域模型与规则）、`data`（存储 / 网络实现）、`presentation`（Riverpod 状态 + 页面）三层组织。领域层不依赖 Flutter，方便单测。

**状态管理细节**：持久化设置用 `_PersistedSettingNotifier`，带代际计数防竞态；播放进度用 Timer 轮询；播放命令用协调器串行化；推荐候选可联网补足；渐变栏 / 分页栏等为共享组件。

---

## 构建与发布

环境要求：Flutter `3.44.9+`（Dart `3.12+`），各平台独立工程，无需额外代码生成。

```bash
flutter pub get

# Android：发布需配置签名；产物为按 ABI 拆分的 3 个 APK + 1 个 AAB
flutter build apk --release --split-per-abi
flutter build appbundle --release

# Windows：x64 便携版
flutter build windows --release

# iOS：无证书构建，供 Apple ID 侧载
flutter build ios --release --no-codesign
```

**发布约定**

- Android Release 关闭 R8 混淆（保证脚本音源与插件运行时稳定）；
- CI 缺少签名 Secret 时在构建前失败，不使用 debug key 发布；仅本地开发可显式传入 `-PallowDebugReleaseSigning=true`；
- CI 校验 APK 签名与 16KB zip alignment。

**GitHub Releases 产物命名**（v1.4 起）：

- `Koyze-Android-arm64-v8a.apk`
- `Koyze-Android-armeabi-v7a.apk`
- `Koyze-Android-x86_64.apk`
- `Koyze-Apple-ID-Sideload.ipa`
- `Koyze-Windows-x64.zip`

---

## CI / CD

`.github/workflows/` 下共 4 个工作流，推送 `main` 自动触发：

| 工作流 | 内容 |
| --- | --- |
| `build-android.yml` | 签名 Secret 预检 → `analyze` + 全量确定性测试 → 构建 APK 与 AAB → 校验签名 / alignment → 上传产物（`Koyze-Android-APKs` / `Koyze-Android-AAB`） |
| `build-windows.yml` | `analyze` + 平台配置测试 → `flutter build windows --release` → 校验可执行文件与依赖 → 打包 ZIP（`Koyze-Windows-x64`） |
| `build-ios.yml` | `analyze` + 测试 → `pod install` → 无签名构建 → 校验 IPA 结构与隐私清单 → 上传（`Koyze-Apple-ID-Sideload-IPA`） |
| `deploy-workers.yml` | 后端校验（tsc + vitest + 结构门禁）→ D1 迁移 → `wrangler deploy` → 写入 ADMIN 密钥 → 健康检查与登录冒烟 |

每个前端工作流在上传前运行 `flutter analyze` 与全量确定性测试，避免坏构建进入发布链路。

---

## 后端 API

账号与云歌单服务，仅处理认证、歌单数据与歌单导入。

**数据层**

- **D1**：8 张表（users、system_settings、playlists、playlist_songs、user_artists、user_albums、user_settings、playback_progress），版本化迁移；
- **KV**：只读缓存（歌单、就绪状态、种子锁），D1 为唯一数据源；
- **Durable Object**（SQLite 后端）：按 IP / 账号双维限流。

**接口一览**

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/user/register` | 注册（用户名 / 密码，6–128 位，PBKDF2-SHA256 100k 迭代） |
| POST | `/api/user/login` | 登录，返回 7 天 JWT；旧 SHA-256 密码自动升级 PBKDF2 |
| GET/POST | `/api/user/auth/verify` | 校验 Token（验签 + `token_version` 联网核对），返回实时角色 |
| POST | `/api/user/password` | 改密，原子自增 `token_version`，其它会话立即失效 |
| GET | `/api/user/list` | 拉取收藏（loveList）+ 自定义歌单（≤200 个 / ≤20000 首） |
| POST | `/api/user/list` | 全量提交云歌单快照（原子替换写入） |
| POST | `/api/user/love/add` · `/api/user/love/remove` | 收藏增量增删（面向 256KB 请求体上限的分批方案） |
| POST | `/api/user/playlist/refresh` | 按来源重新拉取导入歌单并重匹配 |
| DELETE | `/api/user/playlist?id=` | 删除歌单（`love` 受保护） |
| POST | `/api/music/playlist/import` | 两阶段歌单导入：解析链接跨三平台重匹配 → 落库（支持追加） |
| GET/POST/DELETE/PUT | `/api/admin/users` | 管理员用户管理（不可删自己或其它管理员） |
| GET | `/api/health` · `/api/version` · `/api/ping` | 健康检查与版本（构建 SHA / 日期） |

**限流策略**：登录 `20ip / 5account / 60s`，注册 `10ip / 3account / 3600s`，导入 `30ip / 30user / 300s`；限流器故障时"失败即关"（503 + Retry-After）。

**JWT**：HS256，claims 含 `sub / username / role / tv(token_version) / iss:koyze-api / exp`；密钥存于 D1 `system_settings`（首启从 KV 迁移或生成）。

### 部署方式

**架构绑定**（`wrangler.toml`）：

- **D1** `DB`（`koyze-api`）：用户、歌单、设置，`migrations_dir = "migrations"`；
- **KV** `CACHE`：只读缓存（歌单、就绪状态、种子锁）；
- **Durable Object** `RATE_LIMITER`（`RateLimiterDO`）：SQLite 后端，用于按 IP / 账号双维限流；
- `workers_dev = true`，免费套餐下 `*.workers.dev` 可直接访问。

**首次部署（本机）**

```bash
cd workers
npm install

# 1) 创建云资源并记录返回的 ID
npx wrangler d1 create koyze-api
npx wrangler kv namespace create CACHE

# 2) 把上面得到的 D1 / KV ID 填入 wrangler.toml
#    （或配置到 GitHub Secrets 由 CI 替换占位符）

# 3) 本地执行数据库迁移
npx wrangler d1 migrations apply koyze-api --local

# 4) 设置管理员密钥（登录/注册引导用）
npx wrangler secret put ADMIN_USERNAME
npx wrangler secret put ADMIN_PASSWORD

# 5) 校验 + 部署
npm run deploy          # = npm run validate && wrangler deploy
```

**本地调试**：`npm run dev`（`wrangler dev`）；**类型检查**：`npm run typecheck`；**完整校验**：`npm run validate`（vitest + tsc + 结构门禁脚本）。

**数据库迁移**

Schema 变更只通过 `workers/migrations/` + Wrangler 在部署时执行，请求路径不再跑 DDL。

```bash
npx wrangler d1 migrations apply koyze-api --local    # 本地
npx wrangler d1 migrations apply koyze-api --remote   # 生产（部署前）
```

CI（`deploy-workers.yml`）会在 dry-run / deploy 前自动 apply 迁移。若远程库是旧版且没有 `users.token_version` 列，需先手动补丁：

```bash
npx wrangler d1 execute koyze-api --remote \
  --command "ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0"
```

未完成迁移时，除 `/api/ping` 与 `/api/version` 外的 `/api/*` 返回 **503**（服务尚未完成数据库迁移）。

**自动化部署（CI）**

推送 `main` 且改动 `workers/**`，或手动运行 **Deploy Workers API** 工作流触发 `deploy-workers.yml`：

1. `actions/checkout@v4` + Node 安装依赖；
2. `npm run typecheck` → `npm test` → `npm run check:batch-d`（结构门禁：禁止请求期 DDL、禁止敏感信息日志）；
3. 写入构建版本（`src/generated/version.ts`：SHA7 + 构建日期）；
4. 用仓库 Secrets 替换 `wrangler.toml` 中的 `D1_DATABASE_ID` / `KV_NAMESPACE_ID` 占位符；
5. 检查 D1 `users.token_version` 列，按需 apply 迁移；
6. `wrangler deploy --dry-run` 预检 → 正式部署 → 写入 ADMIN 密钥；
7. 部署后冒烟：`GET /`、`GET /api/health`、`POST /api/user/login`、`GET /api/user/auth/verify`。

**所需 GitHub Secrets（6 个）**

| Secret | 说明 |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | Workers / D1 部署权限 |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare Account ID |
| `D1_DATABASE_ID` | D1 数据库 ID |
| `KV_NAMESPACE_ID` | KV 命名空间 ID |
| `ADMIN_USERNAME` | 管理员用户名（引导种子） |
| `ADMIN_PASSWORD` | 管理员密码（引导种子） |

**App 端接入**：设置 → 云端账号 / 歌单，填写 `https://koyze-api.<account>.workers.dev`。

---

## 测试

```bash
# 前端：全部确定性测试（剔除 live 标签，不依赖真实网络）
flutter test --exclude-tags live

# 平台构建 / 差异化配置门禁
flutter test test/build_configuration_test.dart

# 后端
cd workers && npm run validate
```

前端测试覆盖：平台 CI 配置门禁（Android 签名预检、拆分 APK / AAB、签名与 alignment 校验；Windows 便携包与单实例；iOS 侧载 IPA 结构）、R8 关闭、后台播放声明、构建配置、核心状态与同步逻辑（含推荐引擎、渐变栏结构、歌单懒加载等）。

后端用 Vitest 覆盖：限流（Durable Object）、错误响应、请求体校验、结构门禁（禁止请求期 DDL、禁止敏感信息日志）。

---

## 免责声明

本项目仅供学习与技术交流。内置音源与对外接口由对应平台提供，不保证长期可用；请尊重各音乐平台版权，仅将本项目用于个人、非商业用途。
