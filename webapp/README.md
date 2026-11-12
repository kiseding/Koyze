# Koyze Web（Docker 部署）

浏览器打开 `http://<部署机 IP>:8080` 使用的就是 Koyze 原本的 Flutter 界面，
音源脚本与媒体流由同一个容器内的 Node 服务处理。

## 快速开始

```bash
cd webapp
KOYZE_TOKEN=你的口令 docker compose up --build
```

浏览器访问 `http://192.168.x.x:8080`。设了口令时，首次用
`http://192.168.x.x:8080/?token=你的口令` 打开，服务端会换成 HttpOnly 会话
cookie（30 天），之后正常访问即可 —— App 内的「登录」页是 Koyze 云账号，
不是这个访问口令。
不设 `KOYZE_TOKEN` 则不鉴权，仅建议在完全可信的家庭内网使用。

常用环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `KOYZE_PORT` | `8080` | 宿主机端口 |
| `KOYZE_TOKEN` | 空 | 访问口令 |
| `KOYZE_ALLOW_PRIVATE` | `0` | 是否允许音源脚本访问私网地址（如家里 NAS）；默认禁止 |
| `KOYZE_FLUTTER_MIRROR` | 官方 | 构建期 Flutter SDK 下载源，见下 |
| `KOYZE_PUB_MIRROR` | 官方 | 构建期 pub 包下载源，见下 |

### 构建慢？换镜像源

镜像分两阶段：第一阶段装 Flutter SDK 并**现场编译 Web 界面**，第二阶段只
打包 Node 服务。第一阶段要下 ~1GB 的 SDK，国内直连 `storage.googleapis.com`
和 `pub.dev` 经常慢到超时，构建时换镜像即可：

```bash
KOYZE_FLUTTER_MIRROR=https://storage.flutter-io.cn \
KOYZE_PUB_MIRROR=https://pub.flutter-io.cn \
docker compose up --build
```

两个变量只影响构建阶段，不会写进运行镜像。也可以设成系统环境变量长期生效。

构建要点：

- **context 是仓库根目录**（`context: ..`），因为要编译 `lib/`、跑
  `scripts/build-web.sh`。`.dockerignore` 已排除 `android/`、`ios/`、
  `windows/` 等无关平台目录和宿主机的 `build/`、`.dart_tool/`，
  实际送进 daemon 的 context 约 6 MB。
- 镜像里会 `rm -rf build .dart_tool` 再编译，避免复用宿主机（可能是
  Windows/macOS）的缓存导致路径解析错误。
- **构建时会先把 `scripts/` 下 `.sh` / `.py` 的 CRLF 洗成 LF。**
  `.gitattributes` 只保证仓库里存的是 LF，但 build context 取的是工作区，
  Windows 检出后就是 CRLF；Linux 内核会把 `#!/usr/bin/env bash\r` 原样交给
  `env`，它会去找一个名叫 `bash\r` 的程序并报 `No such file or directory`。
  Git Bash 自带 CRLF 兼容，所以这个坑在本地看不出来。
- 镜像里装了 `python3-pil`：`make_web_icons.py` 用它重绘 PWA 图标，
  缺了会直接中断构建。
- `webapp/public/` 不入库、也不进 context，产物只在镜像内生成。
- Flutter 版本由 `ARG FLUTTER_VERSION` 固定（默认 3.44.9，与 CI 六个平台一致）。

### CI 每次 push 都会构建

`.github/workflows/build-web-docker.yml` 在**任何分支的 push**、相关路径的 PR、
以及手动触发时都会构建一次镜像，然后：

1. 校验 `webapp/Dockerfile` 的 `FLUTTER_VERSION` 和各平台 workflow 的
   `flutter-version` 一致（不一致直接失败，避免 Web 与原生端分叉）；
2. 校验镜像体积 < 500 MB、`/app/public` 下的界面产物与图标齐全；
3. 起容器做冒烟测试：`/api/health` 返回四个音源、首页与 `main.dart.js` 可访问
   且体积正常、口令模式下 `/api/sources` 未带凭据返回 401 带凭据返回 200、
   镜像里的 `HEALTHCHECK` 命令能通过。

镜像**不推送到任何 registry**，这个 workflow 的职责只是「能不能构建、能不能跑」。
想拉镜像的话，自己在 `build-push-action` 那步加 `push: true` 和 `tags`。

构建阶段用 GitHub Actions 缓存（`type=gha`）缓存 Flutter SDK 那一层，
缓存命中时通常 3~5 分钟，冷缓存 10~20 分钟。

换音源脚本有两种方式：
- **界面里导入**（推荐）：设置 → 音源 → 导入，选文件 / 粘贴 / 填链接都行。
  浏览器没有 QuickJS，脚本会推给服务端编译执行，落盘在 `data/user-sources/`
  （compose 里是 `koyze-web-data` 卷），容器重建后仍在。
- **放进目录**：把你的 LX 音源 `.js` 放进 `webapp/sources/`，然后
  `curl -X POST http://127.0.0.1:8080/api/reload`（带口令时加 cookie）。

界面导入的脚本按 id 去重：改完脚本重新导入同一个源即可生效，不用重启容器。
镜像内已内置一份默认脚本。

## 架构

```
浏览器 ── HTTP ──> Node 容器 :8080
                     ├── /            Flutter Web 静态产物（原本的 UI）
                     ├── /api/search  内置搜索（酷狗）
                     ├── /api/url     音源脚本取链（服务端执行 LX 脚本）
                     ├── /api/lyric   歌词
                     ├── /api/proxy   内置音源的跨域请求代发 + 防盗链头
                     └── /api/stream  媒体流转发（支持 Range，绕过防盗链）
```

音源脚本在**服务端**用 Node 的 `vm` 执行，提供标准 LX 运行时
（`lx.request` / `lx.utils.crypto.md5` / `lx.on` / `lx.send`），
因此浏览器不需要 QuickJS，也不受 CORS 限制。

## Web 差异在哪里维护

**主仓库 `lib/` 一行不改。** 所有 Web 差异集中在 `scripts/web-patch/`，
由 `scripts/build-web.sh` 在 `build/web-workspace/` 临时副本里施加：

| 补丁 | 作用 |
| --- | --- |
| `lib/main_web.dart` | Web 启动入口，复用 `LxMusicApp`；跳过 `audio_service` / `path_provider` / 便携模式等原生初始化 |
| `lib/core/web/io_shim.dart` | 把 48 处 `import 'dart:io'` 收敛到 shim，只把 `Platform` 换成 Web 安全实现（原生平台零影响） |
| `lib/core/web/artwork_web.dart` | 封面字节走同源 `/api/stream`（浏览器没有 `HttpClient`，且 `Referer` 是禁止头设不上） |
| `lib/features/custom_source/domain/custom_source_engine.dart` | 音源引擎改走同源 `/api/*`，不加载 `flutter_js`（dart:ffi 在 Web 不可用）；导入的脚本推给服务端注册 |
| `lib/core/web/web_source_import.dart` | 链接导入改由服务端代取（浏览器没有 `HttpClient`）；音源检测的 Range 探测也走这里 |
| `lib/core/web/startup_gate_state.dart` | 首启登录门控状态，让侧栏在登录页让位 |
| `lib/core/performance/low_memory.dart` | 去掉 `dart:ffi` 内存探测 |
| `lib/core/network/app_http_client.dart` | 加拦截器，把内置音源的第三方请求改写到 `/api/proxy`；浏览器适配器打开 `withCredentials`；统一摘掉禁止头（`Origin` / `Referer` / `User-Agent` 等） |
| `lib/features/playlist/data/web_playlist_repository.dart` | 歌单存 localStorage |

另有 12 组必须动到主源码，由 `scripts/web-patch/edits.py` 做**锚点替换**
（每个锚点必须恰好命中一次，上游改动会让构建直接失败，而不是静默跑旧逻辑）：

- 链接导入走代理
- 导入脚本跳过 `blob:` 路径读取，直接用 `bytes`
- 音源检测的媒体探测改走浏览器 Range 请求（`dart:io` 的 pinned `HttpClient` 在浏览器里构造即失败，不补这个会一律显示 `0/N` 可用）
- QRC 歌词解压改用 `archive` 的纯 Dart inflate（`dart:io` 的 `zlib` 在 dart2js 下抛 `UnsupportedError`）
- 播放器时长改用实际值（`just_audio_web` 的 `setAudioSource` 会在元数据就绪前返回假时长）
- 门控状态广播
- 封面字节改走同源代理
- 封面磁盘缓存退回纯内存，且先落内存再尝试写盘
- 封面取色走同源代理
- 弹窗与歌词分享卡的封面改用 `ArtworkImage`（`Image.network` 走引擎原生 HTTP，Web 上过不了 CORS/防盗链）
- 登录页期间隐藏侧栏

> 导入与检测这两个功能在 Web 上有共同前提：**文件读取要跳过 `File.openRead()`**。
> 浏览器里 `File(blob:)` 的 `openRead()` 会从 StreamController 的 zone 抛错，
> 而且绕开 `try/catch` 直接中断整个流程，所以 Web 端统一走 `file.bytes` 一次性读入。

现有 Android / iOS / Windows / macOS / Linux / HarmonyOS 六个平台的源码与 CI
完全不受影响；不想要 Web 支持时删除 `scripts/web-patch/` 和 `webapp/` 即可。

## 本地开发

需要 Flutter 3.44.9（与 CI 一致）：

```bash
./scripts/build-web.sh          # 产物写入 webapp/public/
cd webapp && node server/index.js
```

`FLUTTER_BIN` 可指定 flutter 路径。构建脚本会自动处理 `.metadata` 里的
`ohos` 自定义平台条目（官方 SDK 的 migrate 解析会因它报错）。

## 图标与 PWA 元数据

`flutter create --platforms=web` 只会塞一套默认 Flutter logo，跟应用毫无关系。
构建脚本在 `flutter create` 之后调用 `scripts/web-patch/make_web_icons.py`，
用仓库里的 `assets/icon/app_icon.png` 重绘整套：

| 文件 | 尺寸 | 说明 |
| --- | --- | --- |
| `web/favicon.png` | 32×32 | 浏览器标签页 |
| `web/icons/Icon-192.png` | 192×192 | PWA 普通图标 |
| `web/icons/Icon-512.png` | 512×512 | PWA 普通图标 |
| `web/icons/Icon-maskable-192.png` | 192×192 | Android 自适应，内容缩到 80% 安全区 |
| `web/icons/Icon-maskable-512.png` | 512×512 | 同上 |

maskable 版本必须缩到 80%，否则系统裁圆角/圆形时会切掉图形边缘。
`index.html` 与 `manifest.json` 的版本在 `scripts/web-patch/web/`，
构建时覆盖 `flutter create` 生成的默认内容。

## 已知边界

浏览器版本不提供：本地曲库扫描、下载落盘、锁屏/桌面媒体会话、均衡器、
悬浮窗等原生能力。NAS / WebDAV / 云同步可用（凭据存浏览器 localStorage，
语义不等同于系统钥匙串）。

`SHA256SUMS.txt` 由鸿蒙构建流程生成，只含两个 HAP 的哈希，不覆盖其它平台产物。

## 安全说明

- 音源脚本是用户导入的任意 JS：服务端对每一跳请求做 DNS 校验，
  默认**禁止访问私网 / 回环地址**，并手动跟随重定向逐跳复查，防止 SSRF。
- `/api/proxy` 与 `/api/stream` 同样受上述限制；公网部署务必设置 `KOYZE_TOKEN` 并套 HTTPS。
- 不要把容器端口直接暴露到公网。
