# Koyze Workers API 参考

Base URL: `https://your-worker.workers.dev` (部署后替换)

## 🔐 认证

所有需要认证的端点使用 Bearer Token：

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**令牌特性**：
- 有效期：7 天
- 算法：HS256
- 刷新：重新登录获取新令牌
- 失效：令牌版本更新时自动失效

## 📊 响应格式

### 成功响应
```json
{
  "data": { ... },
  "timestamp": 1704067200000
}
```

### 错误响应
```json
{
  "error": "Invalid credentials",
  "code": "AUTH_FAILED",
  "timestamp": 1704067200000
}
```

### 常见状态码
- `200` - 成功
- `201` - 创建成功
- `400` - 请求参数错误
- `401` - 未认证
- `403` - 权限不足
- `404` - 资源不存在
- `429` - 速率限制
- `500` - 服务器错误

---

## 🔑 认证端点

### POST `/api/user/login`

用户登录并获取令牌。

**请求体**：
```json
{
  "username": "admin",
  "password": "your-password"
}
```

**响应 200**：
```json
{
  "token": "eyJhbGc...",
  "user": {
    "id": 1,
    "username": "admin",
    "created_at": 1704067200000
  }
}
```

**错误代码**：
- `400` - 缺少必填字段
- `401` - 用户名或密码错误
- `429` - 速率限制（10 次/分钟）

**示例**：
```bash
curl -X POST https://your-worker.workers.dev/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"secret"}'
```

---

### POST `/api/user/register`

注册新用户（需要管理员权限或开放注册）。

**请求头**：
```http
Authorization: Bearer <admin-token>  # 如果关闭开放注册
```

**请求体**：
```json
{
  "username": "newuser",
  "password": "strong-password"
}
```

**响应 201**：
```json
{
  "user": {
    "id": 2,
    "username": "newuser",
    "created_at": 1704067200000
  }
}
```

**错误代码**：
- `400` - 用户名已存在
- `403` - 需要管理员权限
- `422` - 密码强度不足

---

## 📝 歌单端点

### GET `/api/user/list`

获取用户的所有歌单。

**请求头**：
```http
Authorization: Bearer <token>
```

**响应 200**：
```json
{
  "playlists": [
    {
      "id": "pl-123",
      "name": "我的收藏",
      "description": "最喜欢的歌曲",
      "song_count": 42,
      "cover_url": "https://...",
      "created_at": 1704067200000,
      "updated_at": 1704153600000
    }
  ]
}
```

**示例**：
```bash
curl https://your-worker.workers.dev/api/user/list \
  -H "Authorization: Bearer YOUR_TOKEN"
```

---

### POST `/api/user/playlist/create`

创建新歌单。

**请求头**：
```http
Authorization: Bearer <token>
```

**请求体**：
```json
{
  "name": "夏日歌单",
  "description": "适合夏天听的歌",
  "cover_url": "https://..."
}
```

**响应 201**：
```json
{
  "playlist": {
    "id": "pl-456",
    "name": "夏日歌单",
    "description": "适合夏天听的歌",
    "song_count": 0,
    "created_at": 1704067200000
  }
}
```

**错误代码**：
- `400` - 歌单名称为空
- `429` - 速率限制（100 次/分钟）

---

### PUT `/api/user/playlist/:id`

更新歌单信息。

**请求头**：
```http
Authorization: Bearer <token>
```

**路径参数**：
- `id` - 歌单 ID

**请求体**：
```json
{
  "name": "夏日精选",
  "description": "更新后的描述"
}
```

**响应 200**：
```json
{
  "playlist": {
    "id": "pl-456",
    "name": "夏日精选",
    "description": "更新后的描述",
    "updated_at": 1704240000000
  }
}
```

---

### DELETE `/api/user/playlist/:id`

删除歌单。

**请求头**：
```http
Authorization: Bearer <token>
```

**路径参数**：
- `id` - 歌单 ID

**响应 204**：无内容

**错误代码**：
- `404` - 歌单不存在
- `403` - 无权删除（不是歌单所有者）

---

### POST `/api/user/playlist/:id/add`

向歌单添加歌曲。

**请求头**：
```http
Authorization: Bearer <token>
```

**请求体**：
```json
{
  "songs": [
    {
      "id": "song-123",
      "title": "七里香",
      "artist": "周杰伦",
      "album": "七里香",
      "duration": 300,
      "platform": "qq"
    }
  ]
}
```

**响应 200**：
```json
{
  "added": 1,
  "playlist": {
    "id": "pl-456",
    "song_count": 43
  }
}
```

---

## ❤️ 收藏端点

### GET `/api/user/love`

获取收藏列表。

**请求头**：
```http
Authorization: Bearer <token>
```

**查询参数**：
- `limit` - 返回数量（默认 50，最大 200）
- `offset` - 偏移量（分页）

**响应 200**：
```json
{
  "loves": [
    {
      "song_id": "song-123",
      "title": "七里香",
      "artist": "周杰伦",
      "loved_at": 1704067200000
    }
  ],
  "total": 150,
  "offset": 0,
  "limit": 50
}
```

---

### POST `/api/user/love/add`

添加到收藏。

**请求体**：
```json
{
  "song_id": "song-123",
  "title": "七里香",
  "artist": "周杰伦"
}
```

**响应 201**：
```json
{
  "message": "Added to love list",
  "loved_at": 1704067200000
}
```

---

### DELETE `/api/user/love/:song_id`

从收藏移除。

**响应 204**：无内容

---

## 🔄 同步端点

### GET `/api/sync/events`

获取同步事件（增量同步）。

**请求头**：
```http
Authorization: Bearer <token>
```

**查询参数**：
- `since` - 时间戳，获取该时间之后的事件
- `limit` - 返回数量（默认 100）

**响应 200**：
```json
{
  "events": [
    {
      "id": 1,
      "type": "playlist.create",
      "resource_id": "pl-456",
      "data": { ... },
      "created_at": 1704067200000
    }
  ],
  "has_more": false
}
```

**事件类型**：
- `playlist.create`
- `playlist.update`
- `playlist.delete`
- `love.add`
- `love.remove`

---

### POST `/api/sync/snapshot`

获取完整快照（全量同步）。

**响应 200**：
```json
{
  "playlists": [ ... ],
  "loves": [ ... ],
  "timestamp": 1704067200000
}
```

---

## 👥 管理员端点

### GET `/api/admin/users`

获取用户列表（需要 admin 角色）。

**请求头**：
```http
Authorization: Bearer <admin-token>
```

**响应 200**：
```json
{
  "users": [
    {
      "id": 1,
      "username": "admin",
      "roles": ["admin", "user"],
      "created_at": 1704067200000
    }
  ]
}
```

---

### POST `/api/admin/role/grant`

授予用户角色。

**请求体**：
```json
{
  "user_id": 2,
  "role": "admin"
}
```

**响应 200**：
```json
{
  "message": "Role granted",
  "user_id": 2,
  "role": "admin"
}
```

---

### GET `/api/admin/audit`

获取审计日志。

**查询参数**：
- `user_id` - 过滤特定用户
- `action` - 过滤特定操作
- `limit` - 返回数量（默认 50）

**响应 200**：
```json
{
  "logs": [
    {
      "id": 1,
      "user_id": 1,
      "action": "playlist.delete",
      "resource_id": "pl-789",
      "ip_address": "1.2.3.4",
      "created_at": 1704067200000
    }
  ]
}
```

---

### POST `/api/admin/backup`

导出数据库备份。

**响应 200**：
```json
{
  "users": [ ... ],
  "playlists": [ ... ],
  "love_list": [ ... ],
  "backup_time": 1704067200000
}
```

---

## 🚦 速率限制

| 端点 | 限制 |
|------|------|
| `/api/user/login` | 10 次/分钟/IP |
| `/api/user/register` | 3 次/小时/IP |
| 其他认证端点 | 100 次/分钟/用户 |
| 管理员端点 | 1000 次/分钟/用户 |

**响应头**：
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1704067260
```

**超限响应**：
```json
{
  "error": "Rate limit exceeded",
  "retry_after": 45
}
```

---

## 📦 Webhook（规划中）

未来版本将支持 Webhook 推送同步事件。

---

## 🧪 测试端点

### GET `/api/health`

健康检查（无需认证）。

**响应 200**：
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": 1704067200000
}
```

---

## 📚 SDK 示例

### Dart/Flutter

```dart
import 'package:dio/dio.dart';

class KoyzeAPI {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'https://your-worker.workers.dev',
  ));
  
  String? _token;
  
  Future<void> login(String username, String password) async {
    final response = await _dio.post('/api/user/login', data: {
      'username': username,
      'password': password,
    });
    
    _token = response.data['token'];
    _dio.options.headers['Authorization'] = 'Bearer $_token';
  }
  
  Future<List<Playlist>> getPlaylists() async {
    final response = await _dio.get('/api/user/list');
    return (response.data['playlists'] as List)
        .map((json) => Playlist.fromJson(json))
        .toList();
  }
}
```

### JavaScript

```javascript
const API_BASE = 'https://your-worker.workers.dev';

async function login(username, password) {
  const response = await fetch(`${API_BASE}/api/user/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  
  const data = await response.json();
  return data.token;
}

async function getPlaylists(token) {
  const response = await fetch(`${API_BASE}/api/user/list`, {
    headers: { 'Authorization': `Bearer ${token}` },
  });
  
  const data = await response.json();
  return data.playlists;
}
```

---

## 🔒 安全建议

1. **使用 HTTPS**: 始终通过 HTTPS 访问 API
2. **保护令牌**: 不要在客户端暴露令牌
3. **定期轮换**: 建议定期重新登录获取新令牌
4. **强密码**: 使用至少 12 字符的强密码
5. **速率限制**: 实现客户端重试机制

---

## 📞 支持

- **API 问题**: [GitHub Issues](https://github.com/kiseding/koyze/issues)
- **讨论**: [GitHub Discussions](https://github.com/kiseding/koyze/discussions)
