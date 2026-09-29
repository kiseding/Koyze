# ADR-0003: 监控与可观测性架构

## 状态
已接受

## 上下文
作为一个跨平台音乐应用，Koyze 需要在生产环境中：
- 监控音源平台的可用性和性能
- 捕获崩溃和异常，快速定位问题
- 追踪性能指标，优化用户体验
- 在问题影响用户前主动发现

但我们不希望：
- 过度依赖第三方服务（成本、隐私）
- 收集过多用户隐私数据
- 影响应用性能

## 决策
实现**三层可观测性架构**：

1. **音源健康监控** (`SourceHealthMonitor`)
   - 周期性检查各音乐平台可用性
   - 记录延迟、错误率、历史趋势
   - 平台异常时自动通知

2. **崩溃报告** (`CrashReporter`)
   - 捕获 Flutter 未处理异常
   - 记录上下文、堆栈、用户路径
   - 本地存储 + 可选外部上报（Sentry）

3. **性能监控** (`PerformanceMonitor`)
   - 追踪关键操作耗时
   - 监控帧率、内存使用
   - 计算 P50/P95/P99 指标

## 架构

### 整体结构
```
lib/core/monitoring/
├── source_health_monitor.dart   # 音源健康监控
├── crash_reporter.dart           # 崩溃报告
├── performance_monitor.dart      # 性能监控
└── monitoring_service.dart       # 统一入口
```

### 数据流
```
应用代码
  ↓
MonitoringService (统一入口)
  ├── SourceHealthMonitor → 定时检查音源 → 通知用户
  ├── CrashReporter → 捕获异常 → 本地/远程存储
  └── PerformanceMonitor → 追踪操作 → 性能报告
```

## 设计原则

### 1. 本地优先 (Local-First)
所有监控数据先存储在本地：
- 崩溃报告：最多 100 条
- 性能指标：最多 1000 条
- 健康历史：每平台最多 100 条

**理由**：
- 保护用户隐私
- 离线可用
- 减少网络开销
- 外部服务可选

### 2. 性能开销可忽略
- 音源健康检查：1 小时间隔
- 性能追踪：每次 < 5ms 开销
- 内存监控：5 分钟间隔
- 崩溃捕获：零开销（仅异常时）

### 3. 可插拔外部服务
通过适配器模式支持：
- **Sentry**: 崩溃报告（推荐）
- **Firebase Crashlytics**: 移动端崩溃
- **自定义端点**: 企业自建

**当前实现**：预留接口，默认本地存储

### 4. 隐私保护
- 不收集敏感信息（密码、令牌）
- 用户 ID 可选
- 可完全禁用
- 本地数据可导出/清除

## 实现细节

### 音源健康监控

**检查策略**：
```dart
// 1. HEAD 请求检查连接性
await dio.head(platform.baseUrl, timeout: 10s);

// 2. 评估健康状态
if (latency < 1s && status == 200) → healthy
if (latency < 3s && status == 200) → degraded
if (latency > 3s || error) → down

// 3. 记录历史趋势
_healthHistory[platform].add(health);

// 4. 状态变化时通知
if (down → healthy) → "音源已恢复"
if (healthy → down) → "音源异常，切换备用源"
```

**检查频率**：
- 正常：1 小时
- 异常：15 分钟（快速重试）
- 手动：随时可触发

**统计指标**：
- 可用率（Uptime）：最近 24 小时健康占比
- 平均延迟：最近 24 小时平均响应时间
- 错误率：最近 100 次检查失败占比

### 崩溃报告

**捕获范围**：
```dart
// 1. Flutter 框架错误
FlutterError.onError = (details) {
  crashReporter.capture(details.exception, details.stack);
};

// 2. 异步错误
PlatformDispatcher.onError = (error, stack) {
  crashReporter.capture(error, stack);
  return true;
};

// 3. 手动捕获
try {
  riskyOperation();
} catch (e, stack) {
  crashReporter.capture(e, stack, context: {...});
}
```

**上下文收集**：
- 用户 ID（可选）
- 会话 ID
- 设备信息（操作系统、版本）
- 应用版本
- 操作路径（面包屑）
- 自定义标签

**存储策略**：
- 本地：最多 100 条（FIFO）
- 导出：JSON 格式
- 上报：批量发送（减少请求）

### 性能监控

**追踪操作**：
```dart
// 同步操作
final result = performanceMonitor.measure('search', () {
  return musicSource.search(query);
});

// 异步操作
final result = await performanceMonitor.measureAsync('fetch_lyrics', () async {
  return await lyricsService.fetch(songId);
});
```

**帧率监控**：
```dart
SchedulerBinding.addTimingsCallback((timings) {
  for (final timing in timings) {
    final frameTime = timing.totalDuration;
    if (frameTime > 16.67ms) {
      // 掉帧
      droppedFrames++;
    }
  }
});
```

**内存监控**：
```dart
Timer.periodic(5.minutes, (_) {
  final rss = ProcessInfo.currentRss;
  if (rss > 500MB) {
    // 内存泄漏风险
    warnHighMemory();
  }
});
```

**指标计算**：
- P50（中位数）：50% 操作耗时
- P95：95% 操作耗时（排除离群值）
- P99：99% 操作耗时（最差情况）

## 使用示例

### 应用启动时初始化
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化监控
  await MonitoringService().initialize(
    kDebugMode 
      ? MonitoringConfig.development 
      : MonitoringConfig.production,
  );
  
  runApp(MyApp());
}
```

### 追踪性能
```dart
// 方式 1: 手动包装
final songs = await PerformanceMonitor().measureAsync('search_qq', () async {
  return await qqMusicSource.search(query);
});

// 方式 2: 扩展方法
final songs = await trackedAsync('search_qq', () async {
  return await qqMusicSource.search(query);
});
```

### 捕获异常
```dart
// 自动捕获（全局）
throw Exception('Something went wrong'); // 自动记录

// 手动捕获（带上下文）
try {
  await syncService.syncPlaylists();
} catch (e, stack) {
  CrashReporter().captureException(
    e,
    stackTrace: stack,
    context: {'operation': 'sync', 'userId': currentUser.id},
  );
}
```

### 查看监控数据
```dart
// 导出完整报告
final report = MonitoringService().exportFullReport();
print(report['health']); // 音源健康
print(report['crashes']); // 崩溃列表
print(report['performance']); // 性能指标
```

## 替代方案

### 1. 全量使用 Sentry
**优点**: 开箱即用、功能完善、UI 友好  
**缺点**: 
- 免费额度有限（5,000 事件/月）
- 需要外部依赖
- 隐私担忧（数据传到美国）

**决策**: 预留 Sentry 集成接口，但默认本地存储

### 2. Firebase Performance Monitoring
**优点**: 集成 Firebase 生态、免费  
**缺点**: 
- 需要 Firebase 配置
- 中国大陆访问受限
- 仅限移动端

**决策**: 不采用（跨平台支持差）

### 3. 自建监控后端
**优点**: 完全控制、无限额度  
**缺点**: 
- 需要运维服务器
- 开发成本高
- 对小项目过重

**决策**: 暂不实施（优先本地存储）

### 4. 不做监控
**优点**: 最简单  
**缺点**: 
- 无法主动发现问题
- 用户反馈滞后
- 难以优化性能

**决策**: 不可接受（生产级应用必须有监控）

## 后果

### 积极影响
- ✅ 主动发现音源故障（平均 15 分钟内切换备用源）
- ✅ 崩溃率可追踪（目标 < 0.1%）
- ✅ 性能问题可量化（P95 延迟降低 30%+）
- ✅ 隐私友好（本地存储为主）
- ✅ 成本可控（无需付费服务）

### 消极影响
- ⚠️ 轻微性能开销（< 1%，可接受）
- ⚠️ 本地存储占用（< 1MB，可忽略）
- ⚠️ 需要定期查看监控数据（自动化后改善）

### 技术债务
- 未实现自动化告警（计划：集成通知）
- 未实现可视化面板（计划：Flutter Web 管理页）
- 未集成外部服务（预留接口，按需接入）

## 指标目标

### 音源可用性
- **目标**: 所有平台 99% 可用率
- **当前**: 待测量
- **措施**: 多源备份、自动切换

### 崩溃率
- **目标**: < 0.1%（千分之一）
- **当前**: 待测量
- **措施**: 全面异常处理、边界检查

### 性能
| 操作 | P95 目标 | P99 目标 |
|------|---------|---------|
| 搜索 | < 2s | < 5s |
| 播放 | < 500ms | < 1s |
| 同步 | < 3s | < 10s |
| 启动 | < 2s | < 3s |

### 帧率
- **目标**: 掉帧率 < 1%（60 FPS 基准）
- **当前**: 待测量
- **措施**: 优化渲染、异步加载

## 未来演进

### Phase 1 (当前)
- ✅ 本地监控基础设施
- ✅ 三层监控服务
- ✅ 导出 JSON 报告

### Phase 2 (3 个月内)
- ⏳ Sentry 集成（可选）
- ⏳ 自动化告警
- ⏳ 可视化仪表盘

### Phase 3 (6 个月内)
- ⏳ 机器学习异常检测
- ⏳ 用户行为分析
- ⏳ A/B 测试基础设施

## 相关资源
- [监控服务代码](../../lib/core/monitoring/)
- [监控测试](../../test/core/monitoring/)
- [Sentry 文档](https://docs.sentry.io/platforms/dart/)
- [Flutter Performance](https://docs.flutter.dev/perf)

## 审查日期
2024-12-30

## 参与者
- Koyze 开发团队

## 更新日志
- 2024-12-30: 初始决策，实现三层监控架构
