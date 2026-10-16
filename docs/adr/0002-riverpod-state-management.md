# ADR-0002: 使用 Riverpod 进行状态管理

## 状态
已接受

## 上下文
Flutter 应用需要一个可靠的状态管理方案来处理：
- 音乐播放器状态（播放/暂停/进度）
- 歌单管理
- 用户偏好设置
- 异步数据加载（搜索、同步）
- 跨组件通信

## 决策
使用 **Riverpod 2.x** 作为主要状态管理方案

## 理由

### 优势
1. **编译时安全**
   - 类型安全的依赖注入
   - 编译期错误检测（不是运行时）
   - 无需 BuildContext

2. **简洁的 API**
   - Provider 定义简单
   - 支持自动释放（AutoDispose）
   - 内置依赖追踪

3. **测试友好**
   - 易于 mock providers
   - 支持 ProviderContainer 独立测试
   - 无需 Widget 树

4. **性能优化**
   - 精确的重建控制
   - 仅订阅必要的状态
   - 支持 select() 细粒度监听

5. **生态成熟**
   - 官方维护（Remi Rousselet）
   - 大量社区资源
   - 与 flutter_hooks 集成良好

### 对比其他方案

| 方案 | 优点 | 缺点 | 得分 |
|------|------|------|------|
| **Riverpod** | 类型安全、编译时检查、无 context | 学习曲线 | 9/10 |
| BLoC | 清晰的数据流、企业级 | 样板代码多 | 7/10 |
| Provider | 简单易学 | 运行时错误、依赖 context | 6/10 |
| GetX | 快速开发 | 全局状态、测试困难 | 5/10 |
| setState | 内置、零依赖 | 难以扩展、状态分散 | 4/10 |

## 实现模式

### 1. StateNotifierProvider（业务逻辑）
```dart
final playerControllerProvider = 
  StateNotifierProvider<PlayerController, PlayerState>((ref) {
    return PlayerController(ref.watch(audioServiceProvider));
  });
```

### 2. FutureProvider（异步数据）
```dart
final searchResultsProvider = 
  FutureProvider.autoDispose.family<List<Song>, String>((ref, query) async {
    return ref.watch(musicSourceProvider).search(query);
  });
```

### 3. StreamProvider（实时更新）
```dart
final playbackPositionProvider = 
  StreamProvider.autoDispose<Duration>((ref) {
    return ref.watch(audioServiceProvider).positionStream;
  });
```

## 替代方案

### BLoC Pattern
**不选择的原因**：
- 过多样板代码（Event/State/Bloc 类）
- 对于音乐播放器这种中等复杂度应用过于重
- Riverpod 提供相似的数据流控制但更简洁

### GetX
**不选择的原因**：
- 全局状态难以追踪
- 测试时 mock 困难
- 社区存在争议（API 设计问题）

### Redux
**不选择的原因**：
- 学习曲线陡峭
- 大量样板代码（Action/Reducer/Store）
- 对于本项目过于复杂

## 后果

### 积极影响
- ✅ 代码类型安全，减少运行时错误
- ✅ 测试覆盖率提升（易于单元测试）
- ✅ 状态逻辑集中管理（不分散在 Widget 中）
- ✅ 性能优化（精确重建控制）

### 消极影响
- ⚠️ 团队需要学习 Riverpod 概念（Provider/StateNotifier）
- ⚠️ 从 Provider 迁移需要重构（已完成）

### 技术债务
- 部分老代码可能还在使用 StatefulWidget
- 需要逐步重构为 ConsumerWidget + Provider

## 迁移建议
新功能必须使用 Riverpod，老代码逐步重构：
1. 优先重构核心模块（播放器、歌单）
2. UI 组件可延后（低优先级）
3. 工具函数不需要改动

## 相关资源
- [Riverpod 官方文档](https://riverpod.dev/)
- [Riverpod Generator](https://pub.dev/packages/riverpod_generator)
- [项目 Provider 列表](../../lib/core/providers/)

## 审查日期
2023-06-01

## 参与者
- @kiseding

## 更新日志
- 2023-06-01: 初始决策，从 Provider 迁移到 Riverpod
- 2024-12-30: 已全面采用，状态管理稳定
