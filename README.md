# Koyze

<p align="center">
  <img src="assets/icon/app_icon.png" alt="Koyze" width="112" height="112">
</p>

> [!NOTE]
> **本项目衍生自 [yingjunda/LX-Music-Flutter-Mobile](https://github.com/yingjunda/LX-Music-Flutter-Mobile)。**
> Koyze 的初始代码库、目录结构与部分模块（自定义音源引擎、内置平台元数据源、播放器与歌单
> 基础设施）来自该项目。上游仓库未声明开源许可证，因此其原始代码的版权归原作者所有；
> 本项目仅对自身新增与修改的部分适用 Apache License 2.0，详见 [NOTICE](NOTICE)。
> 如果你是上游作者并希望调整这里的署名方式，请提 Issue，我们会配合。

<p align="center">
  面向 Android、Windows、iOS、macOS、Linux 与 HarmonyOS 的跨平台音乐查找、播放和本地曲库管理工具。
</p>

Koyze 使用 Flutter 构建，把 QQ 音乐、酷我音乐、网易云音乐、酷狗音乐的**元数据**（搜索、歌单、榜单、歌词、封面）与本地文件、NAS 媒体库整合到同一套界面里。

**本项目不内置、也不分发任何音频音源。** 在线歌曲的播放地址全部由用户自行导入并启用的 LX Music 音源脚本解析；没有可用音源时，在线歌曲无法播放，也不会回落到任何内置通道。本地文件、NAS 与 Subsonic 不受影响。Cloudflare Workers 后端只负责可选的账号与跨设备同步。

> [!IMPORTANT]
> 本项目基于 Apache 2.0 许可证开源。仅用于技术研究和个人学习。请遵守所在地法律、平台服务条款与内容版权要求，不要将它用于侵犯版权或绕过付费授权。

## 界面预览

以下截图取自 HarmonyOS 7.0 x86_64 模拟器中的实际界面（Koyze 4.1.0，浅色主题），未做裁剪或合成。

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-home.png" width="176" alt="首页"><br>首页</td>
    <td align="center"><img src="docs/screenshots/02-leaderboard.png" width="176" alt="榜单"><br>榜单</td>
    <td align="center"><img src="docs/screenshots/03-playlist.png" width="176" alt="歌单"><br>歌单</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04-settings.png" width="176" alt="设置"><br>设置</td>
    <td align="center"><img src="docs/screenshots/05-player.png" width="176" alt="播放器"><br>播放器</td>
    <td align="center"><img src="docs/screenshots/06-lyrics.png" width="176" alt="歌词"><br>歌词</td>
  </tr>
</table>

## 下载

前往 [Releases](https://github.com/kiseding/Koyze/releases) 获取当前版本 `v4.1.1` 的构建产物：

| 平台 | 文件 | 说明 |
| --- | --- | --- |
| Android | `Koyze-4.1.1-arm64-v8a.apk`<br>`Koyze-4.1.1-armeabi-v7a.apk`<br>`Koyze-4.1.1-x86_64.apk` | 按 ABI 拆分，已签名；按设备架构选择 |
| Windows | `Koyze-Windows-x64.zip` | 免安装压缩包，解压后运行 `Koyze.exe` |
| macOS | `Koyze-macOS.zip` | 未签名 `Koyze.app`，首次打开需在“隐私与安全性”中放行 |
| Linux | `Koyze-Linux-x64.tar.gz` | 便携包，解压后运行 `koyze` |
| iOS | `Koyze-Apple-ID-Sideload.ipa` | 未签名，需自行用 Apple ID 侧载；不含小组件与 Live Activity 扩展 |
| HarmonyOS | `Koyze-4.1.1-ohos-arm64.hap`<br>`Koyze-4.1.1-ohos-x64.hap` | 已用发布证书签名，可直接 `hdc install`；真机用 arm64，x86_64 模拟器用 x64 |
| 校验 | `SHA256SUMS.txt` | 全部产物的 SHA-256 |

> [!TIP]
> 鸿蒙 HAP 的架构必须与设备匹配：`ohos-arm64` 用于 ARM64 真机，`ohos-x64` 用于 x86_64 模拟器。装错架构会在启动时崩溃。校验示例：`sha256sum -c SHA256SUMS.txt`。

## 功能

### 搜索与音源

- 聚合搜索 QQ 音乐、酷我音乐、网易云音乐和酷狗音乐，也可只搜索指定平台。
- 同时检索本地曲库、NAS 乐库与收藏，支持搜索历史、热门搜索和分页加载。
- 内置平台只提供元数据：搜索、歌单、榜单、歌词与封面，**不含任何音频地址解析**。
- 在线播放完全依赖你导入并启用的 LX Music 格式 JavaScript 音源；设置中可启用、编辑、导出并查看运行日志。
- 没有启用音源时，点击播放会明确提示，而不会静默回落到任何内置接口。
- 可从四个平台的歌单链接或数字 ID 导入公开歌单，无需登录对应平台。

### 播放与歌词

- 基于 `just_audio` 与 `audio_service`，支持后台播放、媒体通知和系统媒体控制。
- 支持顺序播放、随机播放、单曲循环、播放队列、进度拖动与前后 10 秒跳转。
- 自动预取后续歌曲并保存播放会话，可按设置在下次启动时恢复。
- 支持 LRC、逐字歌词、翻译歌词、腾讯 QRC 与网易 YRC，逐字歌词可显示 KTV 填充效果。
- 内置均衡器，提供预设与自定义频段调节；目前仅在 Android 上生效，iOS、macOS 与 Windows 的播放引擎未开放音频特效通道。
- 提供 128 kbps、320 kbps、FLAC、FLAC 24-bit 和 Hi-Res 目标音质；实际音质取决于音源返回的结果，界面显示最终值。
- 支持 10、15、30、60、90 分钟睡眠定时。

> [!NOTE]
> 音质选项代表向音源请求的目标音质。音源若没有对应资源，可在较低音质间降级；实际音质以播放器显示为准。

### 本地曲库与下载

- 递归扫描本地目录，并增量更新曲库。
- 支持 MP3、FLAC、M4A、AAC、WAV、OGG、Opus、WMA、APE、AIFF 和 ALAC。
- 读取歌曲标签与封面；缺少标签时可从文件名推断基本信息。
- Android 支持 MediaStore、系统目录授权（SAF）和从其他应用打开音频文件。
- iOS 支持通过系统文件选择器授权目录访问。
- 可在线匹配本地歌曲的元数据、封面与歌词，并提供实验性的标签写入功能。
- 下载任务支持并发、暂停、继续、重试、取消、进度与速度显示，以及仅 Wi-Fi 下载策略。
- 下载完成的歌曲会自动加入本地曲库；播放缓存也可复用于下载。

### NAS 与自建媒体库

- 支持 Subsonic 兼容服务（Navidrome、Airsonic、Gonic）、Emby、Jellyfin、Plex 与群晖 Audio Station。
- 连接后可浏览服务器上的歌单与音乐库，并可把该服务器作为搜索源参与统一检索与播放队列。
- 账号密码或访问令牌只保存在本机钥匙串，不会上传到 Koyze 的同步后端。

### 歌单、统计与推荐

- 内置“我的收藏”“最近播放”“本地音乐”和“NAS 乐库”，并支持创建自定义歌单。
- 支持歌单内搜索、排序、拖动重排、批量收藏；收藏列表可检测重复歌曲并勾选要移除的版本。
- 可导入或导出 JSON 备份；恢复过程带事务回滚，避免只写入部分数据。
- 提供周、月、年和全部时间范围的播放统计，包括播放次数、时长、活跃天数、歌曲/歌手/专辑排行与每日趋势。
- 根据收藏和播放记录在本地建立偏好画像，再从在线音源生成推荐结果。

> [!NOTE]
> 推荐功能需要至少 100 首收藏歌曲，推荐结果会缓存 12 小时。

### 可选云同步

- Cloudflare Workers + D1 + KV + Durable Objects 后端。
- 支持账号注册、登录、修改密码和会话失效管理。
- 可同步收藏、自定义歌单、评分、部分设置与自定义音源定义。
- 搜索、播放、歌词和媒体文件不经过该后端；未配置服务器时，核心功能仍可正常使用。
- 自定义音源的启用状态仅保存在当前设备，不参与同步。

## 平台支持

| 平台 | 最低要求 | 平台能力与注意事项 |
| --- | --- | --- |
| Android | Android 7.0（API 24） | 后台播放、媒体通知、MediaStore、SAF 目录授权、音频文件打开、下载与均衡器 |
| Windows | Windows 10/11 x64 | 本地曲库、系统托盘、关闭窗口时退出/隐藏选择、可选便携数据模式 |
| iOS | iOS 15.0 | 后台音频与文件目录授权；小组件、Live Activity 和灵动岛需要 iOS 16.1 及正确签名 |
| macOS | macOS 12.0 | 桌面窗口与本地曲库；发布包未签名，需手动放行 |
| Linux | 带 GTK 3 的 x86_64 发行版 | 便携 tar.gz；运行依赖 GTK 3、libsecret、libjsoncpp 等系统库 |
| HarmonyOS | HarmonyOS 7.0（API 26） | arm64 真机与 x86_64 模拟器双架构 HAP；后台播放与 AVSession 媒体控制，详见 [鸿蒙构建说明](docs/harmonyos.md) |

当前仓库不包含 Web 目标。

## 快速开始

### 环境要求

- Flutter `3.44.0` 或更高版本；持续集成使用 Flutter `3.44.9`。
- Dart `3.12.0` 或更高版本（随 Flutter 提供）。
- Android：Android Studio/SDK 与 JDK 17。
- Windows：Visual Studio 2022，并安装“使用 C++ 的桌面开发”。
- iOS/macOS：macOS、Xcode 与 CocoaPods。
- Linux：`clang`、`cmake`、`ninja-build`、`pkg-config`、`libgtk-3-dev`、`libsecret-1-dev`、`libjsoncpp-dev`。
- HarmonyOS：DevEco Studio 26.0.0（API 26）与鸿蒙 Flutter fork，版本必须整套自洽，详见 [docs/harmonyos.md](docs/harmonyos.md)。

### 运行应用

```bash
git clone https://github.com/kiseding/Koyze.git
cd Koyze
flutter pub get
flutter run
```

如果连接了多个设备，可先查看设备 ID：

```bash
flutter devices
flutter run -d <device-id>
```

首次启动时可以跳过登录。进入“设置”后可调整默认搜索平台、播放/下载音质、缓存、下载策略、本地目录、NAS 服务器和自定义音源；设置项多起来以后，用设置页右上角的放大镜直接搜索——输入“音质”“wifi”“night”都能落到那一行。

## 构建发行版

### Android

调试 APK：

```bash
flutter build apk --debug
```

Release 构建必须配置签名。在 `android/key.properties` 中填写：

```properties
storeFile=release.jks
storePassword=your-store-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

将密钥文件放在与 `storeFile` 对应的位置，然后执行：

```bash
flutter build apk --release --split-per-abi
```

### Windows

```bash
flutter build windows --release
```

输出位于 `build/windows/x64/runner/Release/`。发布时需要保留该目录内的 DLL、数据文件和可执行文件，不能只复制 `Koyze.exe`。

#### 便携数据模式

在 `Koyze.exe` 同级目录创建一个名为 `portable.flag` 的空文件，应用会将配置、曲库索引、下载记录和缓存写入同级的 `portable_data/`，而不是用户配置目录。

> [!TIP]
> GitHub Actions 生成的 Windows ZIP 是免安装压缩包，但默认仍使用用户配置目录。需要数据也随目录移动时，请自行添加 `portable.flag`。

### macOS

```bash
flutter build macos --release
```

输出位于 `build/macos/Build/Products/Release/Koyze.app`。仓库产出的 ZIP 未做代码签名与公证，分发前需自行配置开发者证书。

### Linux

```bash
flutter build linux --release
```

输出位于 `build/linux/x64/release/bundle/`，需要连同 `lib/` 与 `data/` 一起分发：

```bash
tar -C build/linux/x64/release/bundle -czf Koyze-Linux-x64.tar.gz .
```

### iOS

```bash
cd ios
pod install
cd ..
flutter build ios --release
```

需要在 Xcode 中为主应用和 Widget Extension 配置开发团队、Bundle ID、App Group 以及签名。只验证编译而不签名时可以使用：

```bash
flutter build ios --release --no-codesign
```

### HarmonyOS

```bash
flutter build hap --release --target-platform ohos-arm64
flutter build hap --release --target-platform ohos-x64
```

`ohos-arm64` 用于 ARM64 真机，`ohos-x64` 用于 x86_64 模拟器，单次构建只产出一个架构。默认产物未签名，安装到真机前需要用 `scripts/ohos/sign-hap.sh` 配合发布证书与 profile 签名；CI 产出的 HAP 已完成签名，可直接 `hdc install`。

工具链版本锁定、引擎与 AOT 生成器一致性门禁、签名所需 Secrets 等细节见 [docs/harmonyos.md](docs/harmonyos.md)。

## 自定义音源

这是在线音频的**唯一来源**。Koyze 不附带、不内置、也不代下载任何音源脚本，仓库与发行包中都不包含音频地址解析代码。

在“设置 → 高级 → 自定义源”中可通过以下方式导入：

- 选择本地 `.js` 文件（最大 2 MiB）。
- 粘贴 LX Music 格式脚本或 Koyze 导出的 JSON 配置。
- 填写 HTTPS 直链下载脚本。

脚本可声明支持的平台、操作和音质。Koyze 同一时间只启用一个自定义音源，启用新音源会停用原音源。

> [!WARNING]
> 自定义音源是可执行 JavaScript。应用会进行格式检查、超时和部分危险模式检测，但这不是安全沙箱，脚本仍可发起网络请求。只导入来源可信、内容经过审查的脚本。

## 部署可选同步服务

不需要跨设备同步时，可以跳过本节。

### 准备资源

后端位于 `workers/`，要求 Node.js 20 或更高版本、Cloudflare 账号和 Wrangler 登录状态。

```bash
cd workers
npm ci
npx wrangler login
npx wrangler d1 create koyze-api
npx wrangler kv namespace create CACHE
```

将命令返回的 D1 `database_id` 和 KV `id` 填入 `workers/wrangler.toml` 对应占位项，然后执行数据库迁移：

```bash
npx wrangler d1 migrations apply koyze-api --remote
```

### 手动部署与 Worker 密钥

```bash
npm run deploy
npx wrangler secret put ADMIN_USERNAME
npx wrangler secret put ADMIN_PASSWORD
```

可选的第三方接口密钥：

```bash
npx wrangler secret put TINYAPI_KEY
```

请在首次注册或登录前设置管理员账号与密码。部署完成后检查：

```bash
curl https://<your-worker>.workers.dev/api/health
```

然后在 Koyze 的“设置 → 同步”中填写该 HTTPS 地址。登录令牌会保存在系统安全存储中，并按服务器来源隔离。

### 使用 GitHub Actions 自动部署

仓库内的 `.github/workflows/deploy-workers.yml` 会在以下情况运行：

- `main` 分支中的 `workers/**` 或部署工作流本身发生变化。
- 在 GitHub 的“Actions → Deploy Workers API”页面手动选择“Run workflow”。

运行前，进入仓库的“Settings → Secrets and variables → Actions → Repository secrets”，添加以下 6 个 Secret：

| Repository Secret | 填写内容 | 用途 |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | 远程执行 D1 迁移、部署 Worker 和写入 Worker Secret |
| `CLOUDFLARE_ACCOUNT_ID` | Worker 所属 Cloudflare 账号的 Account ID | 指定 Wrangler 操作的账号 |
| `D1_DATABASE_ID` | `npx wrangler d1 create koyze-api` 返回的数据库 UUID | 替换 `wrangler.toml` 中的 D1 占位符 |
| `KV_NAMESPACE_ID` | `npx wrangler kv namespace create CACHE` 返回的命名空间 ID | 替换 `wrangler.toml` 中的 KV 占位符 |
| `ADMIN_USERNAME` | 初始管理员用户名 | 部署后写入 Worker，并用于登录健康检查 |
| `ADMIN_PASSWORD` | 足够强的初始管理员密码 | 部署后写入 Worker，并用于登录健康检查 |

当前工作流不读取 GitHub Repository Variables，以上项目必须添加在 **Repository secrets**，不是 Variables。D1 和 KV 资源需要提前创建，填写的是资源 ID，不是 `koyze-api` 或 `CACHE` 这两个名称。

创建 `CLOUDFLARE_API_TOKEN` 时，可从 Cloudflare 的“Edit Cloudflare Workers”模板开始，并额外授予所选账号的 **D1 Edit** 权限；资源范围应尽量只包含实际部署账号。可参考 [Cloudflare GitHub Actions 指南](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/) 与 [API Token 权限列表](https://developers.cloudflare.com/fundamentals/api/reference/permissions/)。

也可以使用 GitHub CLI 逐项设置，命令会安全地提示输入 Secret 内容：

```bash
gh secret set CLOUDFLARE_API_TOKEN
gh secret set CLOUDFLARE_ACCOUNT_ID
gh secret set D1_DATABASE_ID
gh secret set KV_NAMESPACE_ID
gh secret set ADMIN_USERNAME
gh secret set ADMIN_PASSWORD
```

配置完成后手动运行工作流。它会依次执行 Workers 类型检查与测试、把 D1/KV ID 注入临时的 `wrangler.toml`、应用远程迁移、部署 Worker、上传管理员凭据，并验证 `/api/health`、管理员登录和令牌校验。工作流中的占位符替换只发生在 Actions Runner 内，不会修改仓库文件。

> [!NOTE]
> 当前 Actions 工作流不会读取或上传 `TINYAPI_KEY`。需要该可选密钥时，请在首次部署后本地执行 `npx wrangler secret put TINYAPI_KEY`，或者自行扩展部署工作流。

> [!WARNING]
> 如果复用旧版 D1，且已有 `users` 表缺少 `token_version` 字段，工作流会主动停止，不会继续部署。请先备份数据库并完成对应的一次性结构迁移，再重新运行 Actions；全新数据库不受影响。

### 本地调试 Workers

在 `workers/.dev.vars` 中配置本地密钥（该文件已被 Git 忽略）：

```dotenv
ADMIN_USERNAME=admin
ADMIN_PASSWORD=replace-with-a-strong-password
```

初始化本地 D1 并启动开发服务器：

```bash
cd workers
npm ci
npx wrangler d1 migrations apply koyze-api --local
npm run dev
```

后端包含登录与注册限流、PBKDF2-SHA256 密码派生、7 天 HS256 会话令牌、令牌版本失效、增量事件同步与快照同步。生产环境请使用足够强的管理员密码，并妥善保管 Cloudflare 密钥。

## 项目结构

```text
Koyze/
├─ lib/
│  ├─ core/                 # 通用模型、服务、主题与基础组件
│  ├─ features/             # 搜索、播放、歌单、本地曲库、NAS、下载、同步等功能
│  └─ router/               # go_router 路由
├─ test/                    # Flutter 单元、组件与服务测试
├─ android/                 # Android 原生配置与桥接
├─ ios/                     # iOS 主应用、Widget 与 Live Activity
├─ macos/                   # macOS Runner 与配置
├─ linux/                   # Linux Runner 与 CMake 配置
├─ windows/                 # Windows Runner、系统托盘与便携模式
├─ ohos/                    # HarmonyOS 工程（ArkTS 入口与签名配置）
├─ workers/                 # Cloudflare Workers 同步后端、迁移与测试
├─ docs/                    # 鸿蒙构建说明、API 参考、ADR 与截图
├─ scripts/ohos/            # HAP 签名脚本
├─ third_party/             # 仓库内使用的第三方源码
└─ .github/workflows/       # 各平台构建、发布与后端部署
```

核心数据流：

```mermaid
flowchart LR
    UI[Flutter 页面与组件] --> State[Riverpod 状态与业务服务]
    State --> Sources[MusicSourceService]
    Sources --> BuiltIn[QQ / 酷我 / 网易内置源]
    Sources --> Custom[自定义 JavaScript 音源]
    Sources --> Nas[NAS 媒体库]
    State --> Player[播放器与队列]
    Player --> Audio[audio_service / just_audio]
    Player --> Cache[播放缓存与下载]
    State --> Local[本地曲库、歌单与偏好]
    State --> Sync[可选同步客户端]
    Sync --> Worker[Cloudflare Worker]
    Worker --> D1[(D1)]
    Worker --> KV[(KV)]
    Worker --> DO[Durable Object 限流]
```

## 开发与测试

Flutter 静态检查和不依赖外部网络的测试：

```bash
flutter analyze --no-fatal-infos
flutter test --exclude-tags live
```

带 `live` 标签的测试会访问真实音乐平台接口，容易受网络、地区限制和第三方接口变化影响，请按需单独运行：

```bash
flutter test --tags live
```

Workers 的测试、TypeScript 类型检查和批处理结构检查：

```bash
cd workers
npm ci
npm run validate
```

持续集成按平台拆分，推送到 `main` 或 `v*` 标签时分别执行分析、测试与构建；标签构建会把产物上传到对应的 GitHub Release：

| 工作流 | 覆盖平台 | 产物 |
| --- | --- | --- |
| `build-android.yml` | Android | `Koyze-<版本>-<abi>.apk` |
| `build-windows.yml` | Windows | `Koyze-Windows-x64.zip` |
| `build-macos.yml` | macOS | `Koyze-macOS.zip` |
| `build-linux.yml` | Linux | `Koyze-Linux-x64.tar.gz` |
| `build-ios.yml` | iOS | `Koyze-Apple-ID-Sideload.ipa` |
| `build-harmonyos-online.yml` | HarmonyOS | `Koyze-<版本>-ohos-arm64.hap`、`Koyze-<版本>-ohos-x64.hap` |
| `deploy-workers.yml` | 同步后端 | Cloudflare Worker |

正式 Android 产物需要在仓库 Secrets 中提供签名材料；HarmonyOS 产物需要发布证书与 profile，缺少任意一项都会构建失败，不会上传无法安装的 unsigned HAP。

## 数据与隐私说明

- 本地歌单、搜索历史、播放记录、下载记录、曲库索引、NAS 凭据与多数设置默认保存在设备上。
- 云同步是可选能力，不会代理搜索请求、播放地址、歌词或媒体文件。
- JSON 备份可能包含歌单、自定义音源和设置，分享前请检查其中是否有不希望公开的信息。
- 清除缓存不会等同于删除下载；退出云账号也不会自动删除本地曲库和歌单。

## 常见问题

**必须部署 Workers 才能使用吗？** 不需要。只有账号与跨设备同步依赖 Workers；搜索、歌词、本地曲库、NAS 乐库、歌单都能在本机使用。在线播放与下载需要你自备音源。

**为什么选择无损后最终播放的是较低音质？** 你使用的音源可能不提供该音质，链接也可能暂时失效。Koyze 会在较低音质间降级，并在播放器中显示实际音质。

**为什么推荐页面没有结果？** 需要至少 100 首收藏歌曲才能建立偏好画像。收藏达到要求后重新生成即可。

**为什么搜到了歌却播不了？** 内置平台只负责找到这首歌，不提供音频地址。点播放时如果没有启用音源，或音源不支持该平台 / 该曲目，就会解析失败。请先在“设置 → 高级 → 自定义源”导入并启用音源。

**以前不装音源也能播，为什么现在不行？** 旧版本把各平台的取址逻辑打包进了应用，这正是版权风险所在。现在这些实现已全部移除，只保留元数据能力。

**Windows 压缩包为什么没有把数据放在应用目录？** 免安装与便携数据模式是两回事。请在 `Koyze.exe` 同级创建 `portable.flag` 后再启动应用。

**鸿蒙应该装哪个 HAP？** 真机（ARM64）用 `ohos-arm64`，x86_64 模拟器用 `ohos-x64`。装错架构会在启动时因引擎与快照不匹配而崩溃，卸载后重装正确架构即可。

## 许可证

本项目**新增与修改的部分**使用 [Apache License 2.0](LICENSE) 授权。

本项目衍生自 [yingjunda/LX-Music-Flutter-Mobile](https://github.com/yingjunda/LX-Music-Flutter-Mobile)，该上游仓库未声明开源许可证，其原始代码的版权归原作者所有，**不在 Apache-2.0 授权范围内**。完整的归属说明与受影响文件清单见 [NOTICE](NOTICE)。如果你需要使用上游衍生部分的代码，请自行联系上游作者取得授权。

`third_party/` 中的组件按其各自许可证执行。
