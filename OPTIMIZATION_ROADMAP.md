# Koyze 优化路线图：7.5 → 9.5+ 分

**目标**：通过系统性改进将项目质量从 7.5 分提升至 9.5 分以上

**时间线**：3-4 周（取决于团队规模）

**当前评分分解**：
- 架构设计：8.5/10
- 代码质量：7.0/10
- 安全性：6.0/10
- 测试覆盖：6.5/10
- 文档完整性：7.0/10
- 运维能力：7.0/10
- 用户体验：8.0/10

---

## 🎯 Phase 1: 关键阻断问题（必须完成）

### 1.1 开源许可证 🚨 [优先级: P0]

**当前问题**：
- 无开源许可证导致法律风险
- README 明确声明"不授予复制、修改、分发权"
- 阻碍社区贡献和合法使用

**解决方案**：

```bash
# 选项 A: MIT License（最宽松，鼓励商业使用）
# 适合场景：希望项目被广泛采用，包括商业产品

# 选项 B: Apache 2.0（专利保护）
# 适合场景：有专利考虑，需要贡献者授予专利许可

# 选项 C: AGPL-3.0（网络 Copyleft）
# 适合场景：希望衍生项目开源，尤其是 SaaS 服务
```

**实施步骤**：
1. 创建 `LICENSE` 文件（建议 Apache 2.0）
2. 更新 README，移除"不授予权利"声明
3. 添加文件头注释模板
4. 在 `pubspec.yaml` 和 `package.json` 中声明许可证

**交付标准**：
- [ ] LICENSE 文件已添加
- [ ] README 中已更新许可证信息
- [ ] CI 检查所有新文件包含许可证头
- [ ] `third_party/` 许可证清单已审核

**影响**：+1.0 分（解除法律阻断）

---

### 1.2 JavaScript 沙箱强化 🔐 [优先级: P0]

**当前问题**：
- `flutter_js` 仅提供基础检测（同步循环、危险模式）
- 脚本可执行任意网络请求
- 无资源限制（内存、CPU、网络）
- 存在供应链攻击、凭据窃取风险

**漏洞分析**：
```dart
// lib/features/custom_source/domain/source_script_safety.dart
// 当前仅检测静态模式，无运行时防护
bool hasUnsafeSynchronousLoop(String script) {
  // 启发式正则检测，易绕过
}
```

**解决方案（三层防护）**：

#### Layer 1: 静态分析增强
```dart
class SourceScriptValidator {
  static const int MAX_SCRIPT_SIZE = 2 * 1024 * 1024; // 2MB
  
  static ValidationResult validate(String script) {
    final issues = <SecurityIssue>[];
    
    // 1. AST 解析（使用 Dart analyzer 或 JavaScript parser）
    // 2. 禁止的全局变量访问：process, require, eval
    // 3. 禁止动态代码执行：Function(), new Function, eval()
    // 4. 检测代码混淆标志
    // 5. 熵分析（检测加密恶意代码）
    
    if (_containsEval(script)) {
      issues.add(SecurityIssue.dynamicCodeExecution);
    }
    
    if (_detectsObfuscation(script)) {
      issues.add(SecurityIssue.suspiciousObfuscation);
    }
    
    return ValidationResult(issues);
  }
}
```

#### Layer 2: 运行时隔离
```dart
class SecureSourceEngine extends CustomSourceEngine {
  final Completer<void> _abortController = Completer();
  Timer? _executionTimer;
  
  @override
  Future<T> execute<T>(String operation, Map args) async {
    // 1. 超时保护（每次调用 5 秒上限）
    _executionTimer?.cancel();
    _executionTimer = Timer(Duration(seconds: 5), () {
      _abortController.complete();
      throw TimeoutException('Script execution timeout');
    });
    
    try {
      // 2. 限制网络请求（最多 10 次/分钟）
      await _rateLimiter.checkLimit(sourceId);
      
      // 3. 监控内存使用（iOS/Android 有限支持）
      if (Platform.isAndroid) {
        final memBefore = await _getProcessMemory();
        final result = await super.execute(operation, args);
        final memAfter = await _getProcessMemory();
        
        if (memAfter - memBefore > 100 * 1024 * 1024) { // 100MB
          throw SecurityException('Memory limit exceeded');
        }
        return result;
      }
      
      return await super.execute(operation, args);
    } finally {
      _executionTimer?.cancel();
    }
  }
}
```

#### Layer 3: 网络代理层
```dart
class SourceNetworkProxy {
  static const int MAX_REQUESTS_PER_MINUTE = 30;
  static const int MAX_RESPONSE_SIZE = 10 * 1024 * 1024; // 10MB
  static const Duration REQUEST_TIMEOUT = Duration(seconds: 10);
  
  static final _allowedDomains = <String>[
    // 白名单：仅允许已知音乐平台域名
    'qq.com', 'kuwo.cn', '163.com', 'kugou.com',
  ];
  
  Future<String> fetch(String url, Map<String, dynamic> options) async {
    // 1. 域名白名单检查
    final uri = Uri.parse(url);
    if (!_isAllowedDomain(uri.host)) {
      _logSuspiciousRequest(url);
      throw SecurityException('Domain not in whitelist: ${uri.host}');
    }
    
    // 2. 禁止本地网络访问
    if (_isPrivateIP(uri.host)) {
      throw SecurityException('Local network access forbidden');
    }
    
    // 3. 速率限制
    await _rateLimiter.acquire();
    
    // 4. 响应大小限制
    final response = await dio.get(
      url,
      options: Options(
        receiveTimeout: REQUEST_TIMEOUT,
        headers: {
          'User-Agent': 'Koyze/${appVersion}',
          'Referer': 'https://y.qq.com', // 防止 403
        },
      ),
      onReceiveProgress: (received, total) {
        if (received > MAX_RESPONSE_SIZE) {
          throw SecurityException('Response too large');
        }
      },
    );
    
    // 5. 日志记录（审计跟踪）
    _auditLog.add(AuditEntry(
      sourceId: currentSourceId,
      url: url,
      timestamp: DateTime.now(),
      statusCode: response.statusCode,
    ));
    
    return response.data;
  }
}
```

#### Layer 4: 用户可见的安全状态
```dart
class SourceSecurityMonitor extends StateNotifier<SecurityStatus> {
  SecurityStatus({
    required int networkRequestCount,
    required List<String> accessedDomains,
    required Duration totalExecutionTime,
    required List<SecurityWarning> warnings,
  });
  
  // UI 显示：
  // ⚠️ 此脚本已发起 127 次网络请求
  // 🌐 访问域名：music.163.com, y.qq.com, [+3 more]
  // ⏱️ 累计执行时间：23.4 秒
}
```

**实施步骤**：
1. 实现 Layer 1 静态分析（2 天）
2. 添加 Layer 2 运行时保护（3 天）
3. 构建 Layer 3 网络代理（2 天）
4. 添加 Layer 4 安全监控 UI（1 天）
5. 编写沙箱逃逸测试用例（1 天）

**测试用例**：
```dart
// test/security/source_sandbox_test.dart
void main() {
  test('should reject eval() usage', () {
    final script = '''
      function malicious() { eval('malicious code'); }
    ''';
    expect(
      () => SourceScriptValidator.validate(script),
      throwsA(isA<SecurityException>()),
    );
  });
  
  test('should block non-whitelisted domains', () async {
    final proxy = SourceNetworkProxy();
    await expectLater(
      proxy.fetch('https://attacker.com/steal', {}),
      throwsA(isA<SecurityException>()),
    );
  });
  
  test('should enforce execution timeout', () async {
    final script = '''
      function infiniteLoop() { while(true) {} }
    ''';
    await expectLater(
      engine.execute('infiniteLoop', {}),
      throwsA(isA<TimeoutException>()),
    );
  });
}
```

**交付标准**：
- [ ] 静态分析拦截 eval/Function 构造
- [ ] 网络白名单拦截未授权域名
- [ ] 执行超时保护（5 秒）
- [ ] 速率限制（30 请求/分钟）
- [ ] 安全审计日志可导出
- [ ] 通过 10+ 安全测试用例

**影响**：+1.5 分（消除重大安全隐患）

---

## 🧪 Phase 2: 测试与质量保证

### 2.1 测试覆盖率目标 [优先级: P1]

**当前状态**：
- 151 个测试文件
- 无覆盖率报告
- `live` 标签测试不在 CI 中

**目标覆盖率**：
- 整体：75%
- 核心模块（player, sync, local_music）：85%
- 关键路径（auth, payment, data loss）：95%

**实施方案**：

#### 步骤 1：基线测量
```bash
# 生成覆盖率报告
flutter test --coverage --exclude-tags live

# 安装 lcov
brew install lcov  # macOS
sudo apt install lcov  # Linux

# 生成 HTML 报告
genhtml coverage/lcov.info -o coverage/html

# 上传到 Codecov（可选）
bash <(curl -s https://codecov.io/bash)
```

#### 步骤 2：CI 集成
```yaml
# .github/workflows/ci.yml
- name: Run tests with coverage
  run: flutter test --coverage --exclude-tags live

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: ./coverage/lcov.info
    fail_ci_if_error: true
    flags: unittests

- name: Check coverage threshold
  run: |
    # 提取覆盖率
    coverage=$(lcov --summary coverage/lcov.info | grep 'lines' | grep -oP '\d+\.\d+')
    echo "Coverage: $coverage%"
    
    # 强制最低 70%
    if (( $(echo "$coverage < 70.0" | bc -l) )); then
      echo "::error::Coverage $coverage% is below 70% threshold"
      exit 1
    fi
```

#### 步骤 3：重点补充测试

**优先补充领域**：
1. **播放器状态机**（`lib/features/player/`）
   - 播放/暂停/跳转/队列操作
   - 音质降级逻辑
   - 后台播放恢复
   - 跨平台通知集成

2. **同步引擎**（`lib/features/sync/`）
   - 增量同步 vs 快照同步
   - 冲突解决
   - 离线队列
   - 事务回滚

3. **本地曲库**（`lib/features/local_music/`）
   - 元数据解析（MP3, FLAC, M4A）
   - 增量扫描
   - 标签写入
   - 数据库迁移

4. **自定义音源**（`lib/features/custom_source/`）
   - LX Music 脚本解析
   - 沙箱逃逸测试
   - 错误恢复

**示例测试**：
```dart
// test/features/player/player_state_machine_test.dart
void main() {
  group('PlayerStateMachine', () {
    late PlayerController controller;
    late MockAudioService audioService;
    
    setUp(() {
      audioService = MockAudioService();
      controller = PlayerController(audioService);
    });
    
    test('should transition from idle to playing', () async {
      final song = createTestSong();
      
      await controller.play(song);
      
      expect(controller.state, PlayerState.playing);
      verify(audioService.play(song.url)).called(1);
    });
    
    test('should fallback to lower quality on 403', () async {
      final song = createTestSong(qualities: ['flac', '320k', '128k']);
      
      // Mock 403 for FLAC
      when(audioService.play(contains('flac')))
          .thenThrow(DioException(statusCode: 403));
      when(audioService.play(contains('320k')))
          .thenAnswer((_) async => true);
      
      await controller.play(song);
      
      expect(controller.currentQuality, '320k');
      verify(audioService.play(contains('320k'))).called(1);
    });
    
    test('should restore playback after app restart', () async {
      // 模拟应用重启场景
      final session = PlaybackSession(
        songId: 'test-123',
        position: Duration(seconds: 45),
        queue: [song1, song2],
      );
      
      await storage.saveSession(session);
      
      // 重新初始化控制器
      final newController = PlayerController.fromSession(storage);
      
      expect(newController.currentSong.id, 'test-123');
      expect(newController.position, Duration(seconds: 45));
    });
  });
}
```

#### 步骤 4：集成测试
```dart
// integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  testWidgets('complete user journey: search -> play -> add to playlist', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    
    // 1. 搜索歌曲
    await tester.enterText(find.byType(SearchBar), '周杰伦');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    
    expect(find.text('周杰伦'), findsWidgets);
    
    // 2. 播放第一首
    await tester.tap(find.byType(SongCard).first);
    await tester.pumpAndSettle();
    
    expect(find.byType(PlayerBottomBar), findsOneWidget);
    
    // 3. 添加到歌单
    await tester.longPress(find.byType(SongCard).first);
    await tester.tap(find.text('添加到歌单'));
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    
    // 4. 验证歌单包含该歌曲
    await tester.tap(find.text('歌单'));
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    
    expect(find.byType(SongCard), findsWidgets);
  });
}
```

**交付标准**：
- [ ] 整体覆盖率 ≥ 75%
- [ ] 核心模块覆盖率 ≥ 85%
- [ ] CI 自动检查覆盖率阈值
- [ ] Codecov badge 添加到 README
- [ ] 至少 5 个集成测试场景

**影响**：+1.0 分（质量保证提升）

---

### 2.2 Workers 后端强化 [优先级: P1]

**当前问题**：
- 单一管理员账号
- 无用户角色系统
- 缺少审计日志
- D1 迁移向后兼容性警告

**改进方案**：

#### 2.2.1 多租户与 RBAC
```typescript
// workers/src/db/schema.sql (新增迁移)
-- Migration 003: Add RBAC
CREATE TABLE user_roles (
  user_id INTEGER NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin', 'user', 'readonly')),
  granted_at INTEGER NOT NULL,
  granted_by INTEGER,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL,
  PRIMARY KEY (user_id, role)
);

CREATE TABLE audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  resource_type TEXT,
  resource_id TEXT,
  ip_address TEXT,
  user_agent TEXT,
  created_at INTEGER NOT NULL,
  metadata TEXT, -- JSON
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_audit_user ON audit_logs(user_id, created_at DESC);
CREATE INDEX idx_audit_action ON audit_logs(action, created_at DESC);
```

#### 2.2.2 审计日志服务
```typescript
// workers/src/utils/audit.ts
export interface AuditEntry {
  userId: number;
  action: string;
  resourceType?: string;
  resourceId?: string;
  metadata?: Record<string, unknown>;
}

export async function logAudit(
  env: Env,
  entry: AuditEntry,
  request: Request,
): Promise<void> {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const userAgent = request.headers.get('User-Agent') || 'unknown';
  
  await env.DB.prepare(`
    INSERT INTO audit_logs (
      user_id, action, resource_type, resource_id,
      ip_address, user_agent, created_at, metadata
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(
    entry.userId,
    entry.action,
    entry.resourceType || null,
    entry.resourceId || null,
    ip,
    userAgent.slice(0, 200),
    Date.now(),
    JSON.stringify(entry.metadata || {}),
  ).run();
}

// 使用示例
await logAudit(env, {
  userId: user.id,
  action: 'playlist.delete',
  resourceType: 'playlist',
  resourceId: playlistId,
  metadata: { songCount: 42 },
}, request);
```

#### 2.2.3 速率限制增强
```typescript
// workers/src/middleware/advancedRateLimit.ts
export class AdvancedRateLimiter {
  // Tier-based limits
  private static LIMITS = {
    admin: { requests: 1000, window: 60000 },
    user: { requests: 100, window: 60000 },
    anonymous: { requests: 10, window: 60000 },
  };
  
  async check(
    env: Env,
    userId: number | null,
    action: string,
  ): Promise<void> {
    const tier = await this.getUserTier(env, userId);
    const limit = AdvancedRateLimiter.LIMITS[tier];
    
    const key = userId ? `user:${userId}` : `anon:${action}`;
    const stub = env.RATE_LIMITER.get(
      env.RATE_LIMITER.idFromName(key),
    );
    
    const result = await stub.fetch(
      new Request('https://internal/check', {
        method: 'POST',
        body: JSON.stringify({
          limit: limit.requests,
          window: limit.window,
        }),
      }),
    );
    
    if (result.status === 429) {
      throw new Error('Rate limit exceeded');
    }
  }
}
```

#### 2.2.4 备份与恢复
```typescript
// workers/src/routes/admin/backup.ts
export async function handleBackupDatabase(
  request: Request,
  env: Env,
): Promise<Response> {
  // 仅管理员可访问
  const user = await authenticate(request, env);
  if (!await hasRole(env, user.id, 'admin')) {
    return jsonResponse({ error: 'Forbidden' }, 403);
  }
  
  // 导出所有表
  const tables = ['users', 'playlists', 'love_list', 'sync_events'];
  const backup: Record<string, unknown[]> = {};
  
  for (const table of tables) {
    const { results } = await env.DB.prepare(
      `SELECT * FROM ${table}`,
    ).all();
    backup[table] = results;
  }
  
  await logAudit(env, {
    userId: user.id,
    action: 'database.backup',
    metadata: { tables: tables.length },
  }, request);
  
  return new Response(JSON.stringify(backup, null, 2), {
    headers: {
      'Content-Type': 'application/json',
      'Content-Disposition': `attachment; filename="koyze-backup-${Date.now()}.json"`,
    },
  });
}
```

**交付标准**：
- [ ] RBAC 系统实现（admin/user/readonly）
- [ ] 审计日志记录所有关键操作
- [ ] 分层速率限制
- [ ] 数据库备份/恢复端点
- [ ] Workers 单元测试覆盖率 ≥ 80%

**影响**：+0.5 分（后端健壮性）

---

## 📚 Phase 3: 文档与开发者体验

### 3.1 架构决策记录 (ADR) [优先级: P2]

创建 `docs/adr/` 目录，记录关键技术决策：

```markdown
# docs/adr/0001-cloudflare-workers-backend.md

# ADR-0001: 选择 Cloudflare Workers 作为同步后端

## 状态
已接受

## 上下文
需要一个轻量级后端处理用户账号与跨设备同步，但不希望：
- 运维传统服务器（成本、维护）
- 代理搜索/播放/歌词（隐私、带宽）
- 要求用户自行部署复杂后端

## 决策
使用 Cloudflare Workers + D1 + KV + Durable Objects

## 理由
1. **Serverless**：零运维，按需扩展
2. **免费额度**：10万请求/天（D1）+ 10万读取/天（KV）
3. **全球 CDN**：低延迟
4. **Durable Objects**：内置速率限制状态
5. **简单部署**：Wrangler CLI 一键发布

## 替代方案
- **Firebase**：需要 Google 账号，中国访问受限
- **Supabase**：需要 Postgres 实例，成本较高
- **自建 Node.js**：运维负担

## 后果
- ✅ 用户无需部署传统服务器
- ✅ 成本可控（小规模免费）
- ⚠️ 依赖 Cloudflare 生态
- ⚠️ D1 仍在 Beta（已接近生产就绪）

## 相关
- [Cloudflare Workers 文档](https://developers.cloudflare.com/workers/)
- Migration: `workers/migrations/`
```

更多 ADR 主题：
- ADR-0002: 为什么使用 Riverpod 而非 Bloc/Provider
- ADR-0003: 音质降级策略
- ADR-0004: 自定义音源沙箱设计
- ADR-0005: 为什么不支持 Web 平台

---

### 3.2 API 文档 [优先级: P2]

#### Workers API 参考
```markdown
# docs/api/workers-api.md

# Koyze Workers API 参考

Base URL: `https://your-worker.workers.dev`

## 认证
所有需要认证的端点使用 Bearer Token：
```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

令牌有效期：7 天  
刷新：重新登录

---

## 端点

### POST /api/user/login
登录并获取令牌

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
- 400: 缺少字段
- 401: 凭据无效
- 429: 速率限制（10 次/分钟）

---

### GET /api/user/list
获取用户歌单

**Headers**：
```
Authorization: Bearer <token>
```

**响应 200**：
```json
{
  "playlists": [
    {
      "id": "pl-123",
      "name": "我的收藏",
      "song_count": 42,
      "updated_at": 1704067200000
    }
  ]
}
```

[...完整 API 文档]
```

---

### 3.3 贡献指南 [优先级: P2]

```markdown
# CONTRIBUTING.md

# 贡献指南

感谢您考虑为 Koyze 做贡献！

## 行为准则
请遵守 [Code of Conduct](CODE_OF_CONDUCT.md)

## 开发环境

### 前置要求
- Flutter 3.44.0+
- Dart 3.12.0+
- Node.js 20+ (Workers 开发)

### 首次设置
```bash
git clone https://github.com/kiseding/koyze.git
cd koyze
flutter pub get

# 运行测试
flutter test --exclude-tags live

# 启动应用
flutter run -d macos  # 或 windows / linux
```

## 提交 PR

### 分支命名
- `feature/xxx` - 新功能
- `fix/xxx` - Bug 修复
- `docs/xxx` - 文档更新
- `refactor/xxx` - 重构

### Commit 规范
遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
feat: 添加歌词翻译功能
fix: 修复 Android 后台播放崩溃
docs: 更新 Workers 部署文档
test: 添加播放器状态机测试
```

### PR 检查清单
- [ ] 代码通过 `flutter analyze`
- [ ] 测试通过 `flutter test`
- [ ] 覆盖率未下降
- [ ] 已更新相关文档
- [ ] 已添加变更日志条目

### 代码审查
所有 PR 需要至少一名维护者审查。

## 测试

### 单元测试
```bash
flutter test test/features/player/
```

### 集成测试
```bash
flutter test integration_test/
```

### 覆盖率
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## 发布流程
1. 更新 `pubspec.yaml` 版本号
2. 更新 `CHANGELOG.md`
3. 创建标签：`git tag v3.1.0`
4. 推送：`git push origin v3.1.0`
5. GitHub Actions 自动构建发布

## 问题反馈
- Bug: 使用 [Bug Report 模板](.github/ISSUE_TEMPLATE/bug_report.md)
- Feature: 使用 [Feature Request 模板](.github/ISSUE_TEMPLATE/feature_request.md)

## 社区
- 讨论：[GitHub Discussions](https://github.com/kiseding/koyze/discussions)
- Telegram: [Koyze 中文群](https://t.me/koyze_cn)
```

**交付标准**：
- [ ] 至少 5 个 ADR 文档
- [ ] 完整 Workers API 参考
- [ ] CONTRIBUTING.md
- [ ] CODE_OF_CONDUCT.md
- [ ] PR/Issue 模板
- [ ] 开发者快速入门视频（可选）

**影响**：+0.5 分（开发者体验）

---

## 🚀 Phase 4: 运维与可观测性

### 4.1 健康监控 [优先级: P2]

#### 4.1.1 音源健康检查
```dart
// lib/core/monitoring/source_health_monitor.dart
class SourceHealthMonitor {
  static const CHECK_INTERVAL = Duration(hours: 1);
  
  final _healthStatus = <MusicPlatform, SourceHealth>{};
  
  Future<void> startMonitoring() async {
    Timer.periodic(CHECK_INTERVAL, (_) => _checkAllSources());
  }
  
  Future<void> _checkAllSources() async {
    for (final platform in MusicPlatform.values) {
      try {
        // 1. 搜索测试
        final searchResult = await platform.search('周杰伦', limit: 1);
        
        // 2. 播放 URL 测试
        if (searchResult.isNotEmpty) {
          final song = searchResult.first;
          final url = await platform.getPlayUrl(song, '128k');
          
          // 3. HEAD 请求验证
          final response = await dio.head(url);
          
          _healthStatus[platform] = SourceHealth(
            status: response.statusCode == 200 
              ? HealthStatus.healthy 
              : HealthStatus.degraded,
            lastCheck: DateTime.now(),
            latency: response.headers.value('x-response-time'),
          );
        }
      } catch (e) {
        _healthStatus[platform] = SourceHealth(
          status: HealthStatus.down,
          lastCheck: DateTime.now(),
          error: e.toString(),
        );
        
        // 发送通知
        await _notifySourceDown(platform, e);
      }
    }
  }
  
  Future<void> _notifySourceDown(MusicPlatform platform, dynamic error) async {
    // 1. 本地通知
    await localNotifications.show(
      title: '音源异常',
      body: '${platform.name} 暂时不可用，将自动切换备用源',
    );
    
    // 2. 上报到监控服务（可选）
    if (analyticsEnabled) {
      await analytics.logEvent('source_health_check_failed', {
        'platform': platform.name,
        'error': error.toString(),
      });
    }
  }
}
```

#### 4.1.2 崩溃报告
```dart
// lib/core/monitoring/crash_reporter.dart
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> initCrashReporting() async {
  await SentryFlutter.init(
    (options) {
      options.dsn = 'https://your-sentry-dsn';
      options.environment = kReleaseMode ? 'production' : 'development';
      options.tracesSampleRate = 0.1; // 10% 性能追踪
      
      // 隐私：排除敏感数据
      options.beforeSend = (event, {hint}) {
        // 移除可能包含用户数据的字段
        event.user = null;
        event.request?.data = null;
        return event;
      };
    },
    appRunner: () => runApp(MyApp()),
  );
  
  // 捕获 Flutter 错误
  FlutterError.onError = (details) {
    Sentry.captureException(
      details.exception,
      stackTrace: details.stack,
    );
  };
  
  // 捕获异步错误
  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
    return true;
  };
}
```

#### 4.1.3 性能监控
```dart
// lib/core/monitoring/performance_monitor.dart
class PerformanceMonitor {
  static final _metrics = <String, List<Duration>>{};
  
  static Future<T> measure<T>(String operation, Future<T> Function() fn) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      _recordMetric(operation, stopwatch.elapsed);
    }
  }
  
  static void _recordMetric(String operation, Duration duration) {
    _metrics.putIfAbsent(operation, () => []).add(duration);
    
    // 滑动窗口：只保留最近 100 次
    if (_metrics[operation]!.length > 100) {
      _metrics[operation]!.removeAt(0);
    }
    
    // 异常检测：P95 > 5 秒
    if (_getP95(operation) > Duration(seconds: 5)) {
      debugPrint('⚠️ Performance degradation: $operation P95=${_getP95(operation)}');
    }
  }
  
  static Duration _getP95(String operation) {
    final durations = _metrics[operation] ?? [];
    if (durations.isEmpty) return Duration.zero;
    
    final sorted = [...durations]..sort();
    final index = (sorted.length * 0.95).ceil() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}

// 使用
final songs = await PerformanceMonitor.measure(
  'search_songs',
  () => musicSource.search(query),
);
```

**交付标准**：
- [ ] 音源健康检查每小时运行
- [ ] 崩溃报告集成（Sentry 或开源替代）
- [ ] 性能异常自动告警
- [ ] 监控仪表板（可选，Grafana）

**影响**：+0.5 分（运维能力）

---

### 4.2 平台完整性 [优先级: P2]

**当前问题**：
- `linux/` 和 `macos/` 目录存在但未维护
- README 声明"不包含 Linux/macOS"

**解决方案（二选一）**：

#### 选项 A：移除未维护平台
```bash
# 清理
rm -rf linux/ macos/
git commit -m "chore: remove unmaintained platform targets"

# 更新 pubspec.yaml
# 移除 macOS/Linux 特定依赖
```

#### 选项 B：完整支持所有桌面平台
```yaml
# .github/workflows/build-macos.yml（已存在）
# 确保 macOS 构建正常工作

# 更新 README
## 平台支持
| 平台 | 状态 | 备注 |
|------|------|------|
| Android | ✅ 生产就绪 | API 21+ |
| iOS | ✅ 生产就绪 | iOS 13.0+ |
| Windows | ✅ 生产就绪 | Win 10/11 |
| macOS | ✅ 实验性 | macOS 10.14+ |
| Linux | ✅ 实验性 | Ubuntu 20.04+ |
```

**推荐**：选项 B（完整支持），因为：
- Flutter 桌面已稳定
- 工作流已存在，只需测试
- 扩大用户群

**交付标准**（选项 B）：
- [ ] macOS 构建成功通过 CI
- [ ] Linux 构建成功通过 CI
- [ ] 桌面平台手动测试通过
- [ ] README 平台支持表格更新
- [ ] 发布页面包含所有平台构建

**影响**：+0.3 分（平台完整性）

---

## 🎨 Phase 5: 用户体验优化

### 5.1 新用户推荐冷启动 [优先级: P2]

**当前问题**：
- 需要 100 首收藏才能生成推荐
- 新用户无推荐内容

**解决方案**：

```dart
// lib/features/recommend/domain/recommendation_service.dart
class RecommendationService {
  Future<List<MusicItem>> getRecommendations() async {
    final favoriteCount = await _getFavoriteCount();
    
    if (favoriteCount >= 100) {
      // 现有逻辑：基于偏好画像
      return _generatePersonalizedRecommendations();
    } else if (favoriteCount >= 10) {
      // 混合推荐：偏好 + 热门
      final personal = await _generatePartialRecommendations();
      final trending = await _getTrendingSongs(limit: 20);
      return [...personal, ...trending];
    } else {
      // 新用户：热门 + 分类探索
      return _getNewUserRecommendations();
    }
  }
  
  Future<List<MusicItem>> _getNewUserRecommendations() async {
    // 1. 各平台热门榜单
    final qqTop = await txSource.getLeaderboard('hot', limit: 10);
    final wyTop = await wySource.getLeaderboard('hot', limit: 10);
    final kwTop = await kwSource.getLeaderboard('hot', limit: 10);
    
    // 2. 分类推荐
    final genres = ['流行', '摇滚', '电子', '古典', '民谣'];
    final byGenre = <MusicItem>[];
    for (final genre in genres) {
      final results = await musicSource.search('$genre 推荐', limit: 2);
      byGenre.addAll(results);
    }
    
    // 3. 去重并打乱
    final all = {...qqTop, ...wyTop, ...kwTop, ...byGenre}.toList();
    all.shuffle();
    
    return all.take(50).toList();
  }
}
```

---

### 5.2 缓存与下载 UX 改进 [优先级: P3]

**当前混淆点**：
- "播放缓存可复用于下载"
- "清除缓存不等于删除下载"

**改进方案**：

#### UI 明确化
```dart
// lib/features/settings/presentation/storage_settings.dart
class StorageSettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cacheSize = ref.watch(cacheSizeProvider);
    final downloadSize = ref.watch(downloadSizeProvider);
    
    return ListView(
      children: [
        ListTile(
          title: Text('播放缓存'),
          subtitle: Text(
            '临时文件，用于流畅播放\n'
            '大小：${_formatSize(cacheSize)}\n'
            '⚠️ 清除后需要重新缓冲',
          ),
          trailing: TextButton(
            onPressed: () => _showClearCacheDialog(context),
            child: Text('清除'),
          ),
        ),
        ListTile(
          title: Text('已下载歌曲'),
          subtitle: Text(
            '永久保存在本地曲库\n'
            '大小：${_formatSize(downloadSize)}\n'
            'ℹ️ 删除需进入"下载管理"',
          ),
          trailing: TextButton(
            onPressed: () => context.push('/downloads'),
            child: Text('管理'),
          ),
        ),
        SwitchListTile(
          title: Text('智能缓存复用'),
          subtitle: Text('播放缓存自动转为下载，避免重复下载'),
          value: ref.watch(cacheReuseEnabledProvider),
          onChanged: (value) {
            ref.read(cacheReuseEnabledProvider.notifier).state = value;
          },
        ),
      ],
    );
  }
}
```

---

### 5.3 Windows 便携模式改进 [优先级: P3]

**当前问题**：
- 需要手动创建 `portable.flag`
- 用户期望 ZIP 解压即用

**改进方案**：

#### 首次启动检测
```dart
// windows/runner/main.cpp（或 Dart 层）
bool shouldUsePortableMode() {
  // 1. 检查是否存在 portable.flag
  if (File("portable.flag").existsSync()) {
    return true;
  }
  
  // 2. 检查是否有写入权限到程序目录
  final testFile = File("${Directory.current.path}/.write_test");
  try {
    testFile.writeAsStringSync("test");
    testFile.deleteSync();
    
    // 3. 如果可写，询问用户
    return showPortableModeDialog();
  } catch (e) {
    // 无写入权限，使用用户目录
    return false;
  }
}

bool showPortableModeDialog() {
  // 显示对话框
  final result = MessageBox(
    title: "数据存储位置",
    message: "选择 Koyze 的数据存储方式：\n\n"
             "• 便携模式：数据保存在程序目录，可随文件夹移动\n"
             "• 标准模式：数据保存在用户配置目录\n\n"
             "后续可在设置中更改",
    buttons: ["便携模式", "标准模式"],
  );
  
  if (result == 0) {
    // 创建 portable.flag
    File("portable.flag").writeAsStringSync("");
    return true;
  }
  return false;
}
```

**交付标准**：
- [ ] 首次启动自动询问存储模式
- [ ] 设置中可切换模式（需重启）
- [ ] README 更新说明

**影响**：+0.2 分（用户体验）

---

## 📊 最终验收标准

### 量化指标

| 类别 | 当前 | 目标 | 权重 |
|------|------|------|------|
| 代码覆盖率 | ? | ≥75% | 15% |
| 安全评分 | 6.0 | 9.0 | 20% |
| 文档完整性 | 7.0 | 9.5 | 10% |
| 构建成功率 | ~95% | 100% | 10% |
| 平台支持 | 3/5 | 5/5 | 10% |
| 性能（启动） | ? | <3s | 10% |
| 运维成熟度 | 7.0 | 9.0 | 15% |
| 社区健康 | 7.5 | 9.0 | 10% |

### 检查清单

#### 必须完成 (Phase 1-2)
- [ ] LICENSE 文件（Apache 2.0）
- [ ] JS 沙箱四层防护
- [ ] 测试覆盖率 ≥75%
- [ ] Workers RBAC + 审计日志
- [ ] 所有平台构建通过 CI

#### 应该完成 (Phase 3-4)
- [ ] 5+ ADR 文档
- [ ] Workers API 参考
- [ ] CONTRIBUTING.md
- [ ] 音源健康监控
- [ ] 崩溃报告集成

#### 可选完成 (Phase 5)
- [ ] 新用户推荐冷启动
- [ ] 存储 UX 改进
- [ ] Windows 便携模式对话框

### 最终评分公式

```
总分 = Σ(类别得分 × 权重)

预期提升：
- Phase 1: +2.5 分（7.5 → 10.0 的 100%）
- Phase 2: +1.5 分（质量保证）
- Phase 3: +0.5 分（文档）
- Phase 4: +0.8 分（运维）
- Phase 5: +0.5 分（UX）

总计：7.5 + 5.8 = 13.3 → 归一化后 9.7/10
```

---

## 🛠️ 实施建议

### 人员配置
- **1 名后端工程师**：Workers RBAC、审计、备份（1 周）
- **2 名移动端工程师**：JS 沙箱、测试覆盖、UX（2 周）
- **1 名技术写作**：ADR、API 文档、贡献指南（1 周）
- **1 名 DevOps**：监控、CI 优化、平台构建（1 周）

### 时间线
```
Week 1: Phase 1 (LICENSE + 沙箱设计)
Week 2: Phase 1 (沙箱实现 + 测试)
Week 3: Phase 2 (测试覆盖 + Workers)
Week 4: Phase 3-5 (文档 + 运维 + UX)
Week 5: 集成测试 + Bug 修复
Week 6: Beta 测试 + 发布
```

### 风险缓解
1. **JS 沙箱实现复杂**
   - 风险：可能需要 2 周而非 1 周
   - 缓解：先实现 Layer 1-2，Layer 3-4 可后续迭代

2. **覆盖率目标过高**
   - 风险：历史代码难以测试
   - 缓解：只强制新代码 ≥80%，历史代码渐进提升

3. **平台构建失败**
   - 风险：Linux/macOS 依赖问题
   - 缓解：先修复 CI，实在不行回退到选项 A（移除）

---

## 🎉 发布计划

### v3.1.0 - 安全与质量版本
**发布日期**：优化完成后 1 周

**发布说明**：
```markdown
# Koyze v3.1.0 - 安全与质量提升

## 🔐 安全
- **JS 沙箱强化**：四层防护（静态分析、运行时隔离、网络白名单、审计日志）
- **网络请求限制**：自定义音源最多 30 次/分钟
- **执行超时**：脚本执行 5 秒超时保护

## 🧪 质量
- **测试覆盖率**：从 ? → 75%+
- **集成测试**：5+ 端到端场景
- **性能监控**：自动检测 P95 异常

## 📚 文档
- **开源许可证**：Apache 2.0
- **架构决策记录**：5 篇 ADR
- **贡献指南**：完整开发者文档

## 🚀 运维
- **音源健康监控**：自动检测平台可用性
- **崩溃报告**：集成 Sentry
- **RBAC**：Workers 多用户角色

## 🎨 体验
- **新用户推荐**：无需 100 首收藏
- **存储管理**：清晰区分缓存/下载
- **便携模式**：Windows 首次启动询问

## 📦 平台
- ✅ Android
- ✅ iOS  
- ✅ Windows
- ✅ macOS（新增）
- ✅ Linux（新增）

[完整变更日志](CHANGELOG.md)
```

---

## 附录：工具与资源

### 测试工具
- **覆盖率**：`flutter test --coverage`
- **集成测试**：`integration_test` package
- **性能分析**：Flutter DevTools
- **安全扫描**：`flutter analyze` + Dart Code Metrics

### 监控服务
- **崩溃报告**：[Sentry](https://sentry.io)（开源自托管或云端）
- **分析**：Firebase Analytics / Mixpanel
- **APM**：Datadog / New Relic

### 文档工具
- **API 文档**：Swagger / Redoc
- **静态站点**：VitePress / Docusaurus
- **架构图**：Mermaid / PlantUML

### CI/CD
- **GitHub Actions**（当前）
- **GitLab CI**（自托管选项）
- **Fastlane**（移动端发布自动化）

---

**总结**：
通过这 6 周的系统性优化，Koyze 将从 7.5 分提升至 **9.5+ 分**，成为一个**生产级、安全、高质量、文档完善**的开源音乐应用。

关键提升：
- ✅ 消除法律阻断（LICENSE）
- ✅ 消除安全风险（JS 沙箱）
- ✅ 提升质量保证（75% 覆盖率）
- ✅ 完善文档（ADR + API + 贡献指南）
- ✅ 增强运维（监控 + 审计）
- ✅ 优化体验（新用户推荐 + 便携模式）

**下一步**：选择优先级最高的 Phase 1，从 LICENSE 和 JS 沙箱开始实施。
