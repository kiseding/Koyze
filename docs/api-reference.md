# Koyze Workers API 参考

Base URL: `https://your-worker.workers.dev`（部署后替换为实际地址）

> 本文档按 `workers/src/` 的实际实现编写。若与代码不一致，以代码为准，并请提 Issue 修正本文档。

## 通用约定

### 响应格式

**没有统一信封。** 每个端点直接返回业务对象，字段平铺在顶层：

```json
{
  "token": "eyJhbGc...",
  "username": "alice",
  "role": "user",
  "accountId": "1"
}
```

错误响应统一为单字段对象：

```json
{ "error": "用户名或密码错误" }
```

部分错误会附带额外字段，例如版本冲突：

```json
{ "error": "revision_conflict", "currentRevision": 42 }
```

`error` 字段的值是**面向最终用户的中文文案**，可以直接展示；需要程序判断的场景请依据 HTTP 状态码或 `error` 的固定英文值（如 `revision_conflict`）。

### 响应头

| 头 | 说明 |
| --- | --- |
| `Content-Type` | 恒为 `application/json; charset=utf-8` |
| `X-Request-ID` | 请求追踪 ID；客户端可通过请求头传入，未传则服务端生成 UUID |
| `Access-Control-Allow-Origin` | 回显请求的 `Origin`；无 `Origin` 时为 `*` |

### 认证

除 `/api/ping`、`/api/version`、`/api/health`、`/api/user/login`、`/api/user/register` 外，所有端点都需要 Bearer Token：

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**令牌特性**

- 有效期：7 天
- 算法：HS256，密钥保存在 D1 的 `system_settings` 表（首次使用时自动生成）
- 载荷：`{ sub, username, role, tv, iss: "koyze-api", iat, exp }`
- 失效：`users.token_version` 与令牌中的 `tv` 不一致时立即失效。修改密码、管理员重置密码都会触发

### 状态码

| 码 | 含义 |
| --- | --- |
| `200` | 成功（所有成功响应都是 200，包括注册） |
| `400` | 请求体/字段无效 |
| `401` | 未登录、令牌无效或已失效 |
| `403` | 权限不足（非管理员、或违反业务约束） |
| `404` | 资源不存在 |
| `409` | 冲突（用户名已存在、`revision_conflict`、暂存会话不存在） |
| `429` | 触发限流 |
| `500` | 服务器内部错误 |
| `503` | 数据库迁移未完成，或管理员尚未初始化 |

### 数据库就绪检查

除 `/api/ping`、`/api/version` 外，所有请求都会先检查 D1 迁移状态。未就绪时直接返回：

```json
{ "error": "服务尚未完成数据库迁移", "requestId": "..." }
```
状态码 `503`。检查结果在 KV 中缓存，正常请求不会每次打库。

---

## 🔑 认证端点

### POST `/api/user/login`

**请求体**

```json
{ "username": "alice", "password": "your-password" }
```

**响应 200**

```json
{
  "token": "eyJhbGc...",
  "username": "alice",
  "role": "user",
  "accountId": "1"
}
```

**错误**

| 码 | `error` | 说明 |
| --- | --- | --- |
| 400 | `用户名和密码不能为空` | 缺少字段 |
| 400 | `输入过长` | 用户名或密码超长 |
| 401 | `用户名或密码错误` | 账号不存在或密码错误（不区分，防用户枚举） |
| 429 | `登录过于频繁，请稍后再试` | 限流 |

**限流**：按 IP 与按账号双桶独立计数，登录成功后只重置账号桶，保留 IP 桶。

**示例**

```bash
curl -X POST https://your-worker.workers.dev/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"secret"}'
```

---

### POST `/api/user/register`

注册普通用户。需要管理员账号已初始化（`ADMIN_USERNAME` / `ADMIN_PASSWORD` 已配置），否则返回 `503`。

**请求体**

```json
{ "username": "newuser", "password": "strong-password" }
```

用户名规则：2–32 字符，仅允许字母、数字、下划线、连字符、中文。密码 6–128 字符。

**响应 200**

```json
{ "token": "eyJhbGc...", "username": "newuser", "accountId": "2" }
```

注意：注册成功**不返回 `role` 字段**（新用户固定为 `user`）。

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `用户名和密码不能为空` / `用户名至少2字符` / `密码至少6位` / `密码不能超过128位` / `用户名只能包含字母、数字、下划线、中文字符` |
| 409 | `用户名已存在` |
| 429 | `注册过于频繁，请稍后再试` |
| 503 | `管理员尚未初始化，请先配置 ADMIN_USERNAME/PASSWORD` |

---

### GET `/api/user/auth/verify`
### POST `/api/user/auth/verify`

校验当前令牌是否仍然有效，并返回最新角色（角色变更会即时反映）。

**响应 200**

```json
{ "valid": true, "username": "alice", "role": "user" }
```

**响应 401**（令牌无效、用户已删除、`token_version` 已提升）

```json
{ "valid": false }
```

---

### POST `/api/user/password`

修改自己的密码。旧密码通过后，`token_version` 自增，**所有旧令牌立即失效**，响应会返回一个新令牌。

**请求体**

```json
{ "oldPassword": "old", "newPassword": "new-strong-password" }
```

**响应 200**

```json
{ "ok": true, "token": "eyJhbGc..." }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `请填写新旧密码` / 密码长度校验失败文案 |
| 401 | `未登录` |
| 403 | `原密码错误` |
| 404 | `用户不存在` |

---

## 👤 用户数据端点

### GET `/api/user/list`

一次性拉取该用户的全部收藏与自定义歌单，用于首次同步或全量恢复。

**响应 200**

```json
{
  "loveList": [
    {
      "id": "songmid-or-hash",
      "name": "七里香",
      "singer": "周杰伦",
      "source": "tx",
      "songmid": "0039MnYb0qxYhV",
      "album": "七里香",
      "artwork": "https://...",
      "duration": 299,
      "hash": "",
      "meta": {}
    }
  ],
  "userList": [
    {
      "id": "pl-123",
      "name": "夏日歌单",
      "source": null,
      "source_id": null,
      "list": []
    }
  ],
  "revision": 42,
  "syncProtocol": 1,
  "complete": true,
  "playlistTotal": 1,
  "songTotal": 0
}
```

**字段说明**

| 字段 | 说明 |
| --- | --- |
| `loveList` | 收藏列表的歌曲数组 |
| `userList` | 自定义歌单（不含 `love`、不含内部 `__stage__:` 记录） |
| `revision` | 当前同步版本号；写入时作为乐观锁基线 |
| `complete` | 为 `false` 表示歌单数超过 200 或歌曲数超过 20000，本次为截断结果，应改用 `/api/sync/snapshot` 做完整拉取 |

**响应 409**

读取过程中若有其他写入推进了 revision，返回：

```json
{ "error": "revision_conflict", "currentRevision": 43 }
```

客户端应重试；这不是错误状态，是并发保护。

---

### GET `/api/user/sync/status`

轻量查询当前版本号，用于判断是否需要拉取。

**响应 200**

```json
{ "revision": 42, "syncProtocol": 1 }
```

---

### POST `/api/user/list`

全量覆盖写入收藏与歌单。**这是一个"保存快照"语义的接口，不是增量。**

**请求体**

```json
{
  "loveList": [ { "id": "...", "name": "...", "singer": "...", "source": "tx" } ],
  "userList": [ { "id": "pl-123", "name": "夏日歌单", "list": [] } ],
  "baseRevision": 42
}
```

**响应 200**

```json
{ "ok": true, "saved": 12, "revision": 43 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `收藏数据无效` / `歌单数据无效或数量超限` / `歌曲数量超限` |
| 409 | `revision_conflict` + `currentRevision` |
| 500 | `保存失败` / `清空失败` |

**限制**：单个歌单最多 20000 首。

---

### DELETE `/api/user/playlist?id=<playlistId>`

删除一个自定义歌单。`id` 走查询参数，**不是路径参数**。`love` 不可删除。

**响应 200**

```json
{ "ok": true, "revision": 43 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `无效歌单ID` |
| 404 | `歌单不存在` |
| 409 | `revision_conflict` |

---

### POST `/api/user/playlist/refresh`

重新从原始平台拉取某个导入歌单的最新内容。

**请求体**

```json
{ "id": "pl-123" }
```

**响应 200**

```json
{ "ok": true, "revision": 44, "playlist": { "id": "pl-123", "name": "...", "count": 30 } }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `无效歌单ID` / `该歌单不支持刷新` |
| 404 | `歌单不存在` |

---

## ❤️ 收藏端点

### POST `/api/user/love/add`

批量添加收藏。幂等：已存在的歌曲会跳过。

**请求体**

```json
{
  "songs": [
    { "name": "七里香", "singer": "周杰伦", "source": "tx", "songmid": "0039MnYb0qxYhV" }
  ],
  "baseRevision": 42
}
```

**响应 200**

```json
{ "ok": true, "added": 1, "revision": 43 }
```

全部已存在时返回：

```json
{ "ok": true, "added": 0, "revision": 43, "message": "全部已存在" }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `无歌曲` / `单批最多500首` |
| 409 | `revision_conflict` |

---

### POST `/api/user/love/remove`

批量移除收藏。

**请求体**

```json
{ "songs": [ { "source": "tx", "songmid": "0039MnYb0qxYhV" } ] }
```

**响应 200**

```json
{ "ok": true, "removed": 1, "revision": 44 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `无歌曲` / `单批最多500首` |

---

## 🔄 同步端点（增量协议）

同步采用「事件日志 + 游标」模型。`/api/user/list`、`/api/user/love/*` 是旧的全量接口，保留兼容；新客户端应优先使用本节端点。

### GET `/api/sync/account-status`

检查云端是否已有该账号的数据，用于首次登录时决定「用云端 / 用本地 / 合并」。

**响应 200**

```json
{
  "cursor": 128,
  "hasCloudData": true,
  "eventCount": 128,
  "favoriteCount": 42
}
```

---

### GET `/api/sync/pull?cursor=<n>`

拉取游标之后的所有同步事件。

**查询参数**

- `cursor` — 上次拉到的位置，首次传 `0`。非整数返回 400。

**响应 200**

```json
{
  "cursor": 129,
  "hasMore": false,
  "events": [
    {
      "serverSequence": 129,
      "eventId": "evt-uuid",
      "deviceId": "device-uuid",
      "localUserId": "local-1",
      "eventType": "favorite.add",
      "entityId": "0039MnYb0qxYhV",
      "payload": {},
      "createdAt": 1704067200000,
      "serverCreatedAt": "2026-01-01 00:00:00"
    }
  ]
}
```

**字段说明**

| 字段 | 说明 |
| --- | --- |
| `cursor` | 本次拉取后的新游标，直接作为下次请求的 `cursor` |
| `hasMore` | 为 `true` 表示还有更多事件，应立即用新游标继续拉取 |
| `serverSequence` | 服务端单调递增序号，游标即基于此值 |
| `createdAt` | 客户端产生事件的时间戳（毫秒） |
| `serverCreatedAt` | 服务端落库时间（D1 时间字符串） |

单次最多返回 200 条。`payload` 解析失败时返回空对象，不会让整个请求失败。

> `eventType` 的具体取值由服务端演进，客户端应忽略无法识别的类型而非报错。

---

### GET `/api/sync/full`

等价于 `GET /api/sync/pull?cursor=0`，用于一次性拉全量事件历史。

---

### POST `/api/sync/push`

推送一批本地变更事件。

**请求体**

```json
{ "events": [ { "type": "favorite.add", "payload": { } } ] }
```

**响应 200** — 直接返回写入结果对象，包含服务端分配的新游标与冲突信息。

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `同步事件请求无效` / `同步事件无效` / `同步事件字段无效` |

---

### GET `/api/sync/snapshot`

拉取完整的云端状态快照（歌单、歌曲、设置、音源、评分），不受 `complete` 截断限制。用于新设备首次同步。

**响应 200**

```json
{
  "version": 1,
  "cursor": 128,
  "playlists": [
    {
      "id": "pl-123",
      "name": "夏日歌单",
      "position": 10,
      "songs": [
        {
          "id": "0039MnYb0qxYhV",
          "name": "七里香",
          "singer": "周杰伦",
          "source": "tx",
          "platform": "tx",
          "songmid": "0039MnYb0qxYhV",
          "album": "七里香",
          "artwork": "https://...",
          "duration": 299,
          "hash": "",
          "playlistItemId": "pi-1",
          "meta": {}
        }
      ]
    }
  ],
  "settings": {},
  "sources": [],
  "ratings": { "0039MnYb0qxYhV": 5 }
}
```

---

### GET `/api/user/sync/state`

读取设置与自定义音源定义。

**响应 200**

```json
{ "settings": { }, "sources": [ ], "revision": 42, "syncProtocol": 1 }
```

---

### POST `/api/user/sync/state`

写入设置与音源。

**请求体**

```json
{ "settings": { }, "sources": [ ], "baseRevision": 42 }
```

**响应 200**

```json
{ "ok": true, "revision": 43 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `同步状态数据无效` |
| 409 | `revision_conflict` + `currentRevision` |

---

### POST `/api/user/sync/stage`

分片上传大量歌单数据的第一步：把一批歌曲写入暂存区。

**请求体**

```json
{ "playlistId": "pl-123", "songs": [ ] }
```

**响应 200**

```json
{ "ok": true, "staged": 500 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `同步暂存数据无效` |
| 409 | `同步暂存会话不存在` |

---

### POST `/api/user/sync/commit`

分片上传的第二步：提交暂存区，原子替换目标歌单。

**请求体**

```json
{ "playlistId": "pl-123", "manifest": [ ] }
```

**响应 200**

```json
{ "ok": true, "revision": 43 }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `同步提交数据无效` / `同步提交清单无效` |
| 409 | `同步暂存会话不存在` |

---

### DELETE `/api/user/sync/stage?id=<playlistId>`

放弃分片上传，清理暂存区。`id` 走查询参数。

**响应 200**

```json
{ "ok": true }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `同步暂存会话无效` |

---

## 🎵 歌单导入

### POST `/api/music/playlist/import`

从 QQ 音乐 / 酷我 / 网易云 的歌单链接或数字 ID 抓取歌单，并把结果重新匹配到本地可识别的曲目结构。

支持两种模式：

**模式一：仅预览（不落库）**

```json
{ "url": "https://y.qq.com/n/ryqq/playlist/1234567890" }
```

或纯数字 ID + 平台：

```json
{ "url": "1234567890", "platform": "tx" }
```

**响应 200**

```json
{
  "songs": [ ],
  "name": "歌单名称",
  "source": "tx",
  "listId": "1234567890"
}
```

**模式二：预览并保存到账号**

额外提供 `playlistId`（追加到已有歌单）或 `name`（新建歌单）：

```json
{ "url": "...", "name": "导入的歌单" }
```

**响应 200**

```json
{
  "ok": true,
  "revision": 43,
  "playlist": {
    "id": "pl-789",
    "name": "导入的歌单",
    "source": "tx",
    "count": 30,
    "appended": false
  }
}
```

**平台识别**：优先按 URL 域名判断（`y.qq.com` → `tx`，`kuwo.cn` → `kw`，`music.163.com` → `wy`）；URL 无法识别且传入的是纯数字时，回退到 `platform` 字段。

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `缺少歌单链接` / `无法识别，请选择平台后输入歌单链接或ID` |
| 500 | `歌单获取失败` / `保存失败` |

> 上游错误详情（URL、堆栈、内部端点名）只写入 Worker 日志，不回传给客户端。

---

## 🛠 管理端点

所有 `/api/admin/*` 都要求调用者是 `admin` 角色。角色从登录时的 JWT 读取，并在每次请求时与服务端 `users.role` 同步，降权立即生效。

### GET `/api/admin/users`

列出所有用户。

**响应 200**

```json
{
  "users": [
    { "id": 1, "username": "admin", "created_at": "2026-01-01 00:00:00", "role": "admin" }
  ]
}
```

---

### POST `/api/admin/users`

创建用户（角色固定为 `user`）。

**请求体**

```json
{ "username": "newuser", "password": "strong-password" }
```

**响应 200**

```json
{ "ok": true }
```

**限流**：每个管理员账号 600 秒内最多 20 次（该操作会跑 PBKDF2，需防滥用）。

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `缺少参数` / `用户名长度需2-32字符` / 密码长度校验失败文案 |
| 403 | `仅管理员` |
| 409 | `用户已存在` |

---

### DELETE `/api/admin/users`

删除用户。级联删除其歌单、收藏与播放进度，其活跃会话随之失效。

**请求体**

```json
{ "id": 2 }
```

**响应 200**

```json
{ "ok": true }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `缺少ID` |
| 403 | `仅管理员` / `不能删除自己` / `不能删除管理员` |
| 404 | `用户不存在` |

---

### PUT `/api/admin/users`

重置指定用户的密码，并提升其 `token_version`（该用户在所有设备上被登出）。

**请求体**

```json
{ "id": 2, "password": "new-password" }
```

**响应 200**

```json
{ "ok": true }
```

**错误**

| 码 | `error` |
| --- | --- |
| 400 | `缺少ID` / `缺少参数` / 密码长度校验失败文案 |
| 403 | `仅管理员` / `不能在此修改自己的密码，请使用修改密码接口` / `不能修改最后一个管理员` |
| 404 | `用户不存在` |

> 不能在这里改自己的密码：那会把调用者自己的令牌作废。请用 `POST /api/user/password`。

---

## 🩺 运维端点

### GET `/api/ping`

最轻量的存活探测，不查数据库。

```json
{ "ok": true, "service": "koyze-api" }
```

### GET `/api/version`

```json
{ "version": "<git-sha> (<build-date>)" }
```

### GET `/api/health`

```json
{ "status": "ok", "version": "<git-sha> (<build-date>)" }
```

> `deploy-workers.yml` 用 `/api/health` 做部署后验证。

### 根路径 `GET /`

非 `/api/` 前缀的请求会返回一份自述信息，方便用户确认 URL 填对了：

```json
{
  "name": "koyze-api",
  "version": "...",
  "hint": "Configure this URL in the app Sync settings",
  "endpoints": ["/api/health", "/api/user/login", "/api/user/list"]
}
```

---

## 附录：限流一览

| 场景 | 维度 | 限制 |
| --- | --- | --- |
| 登录 | IP | 20 次 / 60 秒 |
| 登录 | 账号 | 5 次 / 60 秒 |
| 注册 | IP | 10 次 / 3600 秒 |
| 注册 | 账号 | 3 次 / 3600 秒 |
| 管理员建用户 | 管理员账号 | 20 次 / 600 秒 |

限流由 Durable Object 实现，IP 桶与账号桶**刻意分开**：共用会让攻击者通过更换 IP 绕过对单一账号的爆破防护。

限流器不可用时服务端**拒绝请求**（fail-closed），不会降级为放行。
